/**
 * AI 대화 가이드(generateBriefing) 프롬프트 조립.
 *
 * 2026-08-26에 index.ts에서 **한 글자도 고치지 않고** 이 파일로 옮겼다.
 *
 * 왜 옮겼나: index.ts는 firebase-admin을 초기화하므로 테스트에서 import할
 * 수가 없고, 그래서 **프롬프트 문자열이 의도대로 조립되는지 자동으로 확인할
 * 방법이 없었다.** 프롬프트는 서버에 배포해야만 실물 확인이 되는 물건이라,
 * 배포 전에 잡을 수 있는 것은 조립 단계뿐이다. 이 저장소가 이미 쓰는 방식
 * (usageReset·chunk·creditGrant 등 순수 로직 모듈 + node:test)을 따른다.
 *
 * ⚠️ 이 커밋에서는 **동작이 하나도 바뀌지 않는다.** 옮기면서 같이 고치면
 * 나중에 프롬프트가 달라진 것이 이동 때문인지 수정 때문인지 못 가린다.
 */

export interface GenerateBriefingRequest {
  contactSummary: string;
  myProfileSummary: string;
  communicationLogs: string[];
  // 클라이언트(AiDataReviewSheet)가 Open-Meteo로 미리 조회해 동의 화면에
  // 보여준 뒤 함께 넘기는 오늘 상대방 지역 날씨 요약(예: "맑음, 24°C").
  // 상대방 위치 정보가 없거나 조회에 실패했으면 넘어오지 않는다(optional) —
  // 그 경우 프롬프트에서 조용히 생략한다. 클라이언트 측 동일 로직은
  // lib/core/services/weather_service.dart, lib/core/services/ai_briefing_service.dart 참고.
  weatherSummary?: string;
  // 상대방 명함에 등록된 관심사(쉼표 구분 등은 클라이언트가 이미 문자열로
  // 합쳐서 넘김). 클라이언트 측 필드는 ContactModel.interests 참고.
  interests?: string;
  // 2026-08-07: 통화/문자/카카오톡 자동 연동이 플랫폼 정책상 안 되는 경우가
  // 많아, 사용자가 AiDataReviewSheet에서 직접 몇 줄 적어 넣은 메모(선택).
  // 비어 있으면 넘어오지 않는다.
  extraNote?: string;
  // F-07(재생성 다양성): "새로 생성"을 누르기 직전 화면에 떠 있던 대화 포인트.
  // 클라이언트가 그대로 넘기면(briefing_overlay_view.dart) 프롬프트가 이
  // 문장들을 피해 새 각도로 만들도록 지시한다. 최초 생성이면 비어 있거나
  // 넘어오지 않는다 — 그때는 제외 지시를 생략한다.
  previousPoints?: string[];
}

export function buildPrompt(
  data: GenerateBriefingRequest,
  variationSeed?: string,
): string {
  const commLogSummary =
    data.communicationLogs.length === 0
      ? "최근 소통 기록 없음"
      : data.communicationLogs.map((l) => `- ${l}`).join("\n");

  const contextLines = [
    data.contactSummary,
    `관심사: ${data.interests && data.interests.trim() ? data.interests : "없음"}`,
    ...(data.weatherSummary ? [`오늘 상대방 지역 날씨: ${data.weatherSummary}`] : []),
  ];

  const extraNoteSection = data.extraNote?.trim()
    ? `\n[사용자가 직접 남긴 메모]\n${data.extraNote.trim()}\n`
    : "";

  // F-07: "새로 생성" 직전에 화면에 있던 포인트를 받으면, 그 문장들을 피해
  // 다른 각도로 만들도록 지시한다. 최초 생성(빈 배열)이면 이 절을 생략한다 —
  // 없는 이전 결과를 언급하면 모델이 혼란스러워한다.
  const previousPoints = (data.previousPoints ?? [])
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
  const diversitySection = previousPoints.length > 0
    ? `\n[직전에 제안했던 대화 포인트 — 반드시 피할 것]\n${
      previousPoints.map((p) => `- ${p}`).join("\n")
    }\n위 문장들과는 화제·접근 각도·표현이 겹치지 않는, 완전히 새로운 대화 ` +
      "포인트를 만들어 주세요.\n"
    : "";

  // 회차 시드: 같은 입력이라도 매 호출 문자열이 미세하게 달라져 응답이
  // 굳어지는 것(및 Gemini 암묵적 캐싱)을 막는다. 식별자 자체는 답변에 넣지
  // 않도록 명시한다.
  const seedLine = variationSeed
    ? `\n\n(생성 다양성 시드: ${variationSeed} — 이 식별자는 답변에 포함하지 ` +
      "말고, 매번 서로 다른 표현과 화제를 고르는 데에만 참고하세요.)"
    : "";

  return `당신은 비즈니스 네트워킹 어시스턴트입니다. 사용자는 낯을 가리는 편이라 먼저
연락하는 것을 어색해합니다. 아래 정보를 참고해 사용자가 상대방에게 부담 없이
자연스럽게 안부를 전하며 인연을 이어갈 수 있는 대화 포인트를 만들어 주세요.

[나(사용자) 정보]
${data.myProfileSummary}

[상대방 정보]
${contextLines.join("\n")}

[최근 소통 기록]
${commLogSummary}
${extraNoteSection}${diversitySection}
각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 날씨 정보가 있다면 그중 한 문장 정도에 자연스럽게 녹여도 좋습니다.
단, 날씨는 사실만 담백하게 언급하고 "상쾌하다", "완벽한 날씨" 같은 주관적 단정은
피하세요. 상대방의 관심사나 직함/업종과 관련된 일반적인 화제(업계 동향, 최근 이슈 등 당신이
알고 있는 상식 수준의 내용)를 자연스럽게 언급하는 문장을 하나 포함해도 좋습니다 —
단, 확인되지 않은 구체적 사실·사건을 지어내지 마세요. 번호/불릿/설명 없이 대화
포인트 문장만 줄바꿈으로 구분해서 정확히 3개 작성하세요.${seedLine}`;
}
