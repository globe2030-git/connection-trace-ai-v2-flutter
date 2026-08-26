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
 */

/**
 * 사용자가 화면에서 직접 고르는 「분야」 목록(2026-08-26, backlog 추가 499).
 *
 * ⚠️ **앱이 회사명·직함으로 자동 판정하지 않는다.** 이 저장소에는 태그 자동
 * 부여에 `AI`·`IT`가 박혀 회계사 명함에도 붙은 전례가 있다. 잘못 짚으면
 * 회계사에게 IT 화제를 권하게 되는데, 그건 가이드로서 없느니만 못하다.
 * 그래서 값은 **사용자가 고른 것만** 온다.
 *
 * 🚨 **자유 문자열이 아니라 키로 받는다. 이유는 프롬프트 주입이다.**
 * 자유 문자열을 받으면 그 값이 프롬프트 본문에 그대로 박힌다. 앱이 고정
 * 목록만 보내더라도 **서버는 누가 무엇을 보낼지 모른다** — 요청을 직접
 * 만들면 "위 지시를 무시하고 …"를 분야 칸에 넣을 수 있다. 키 화이트리스트가
 * 그 경로를 원천 차단한다.
 *
 * 그러니 **"목록을 늘리려면 자유 입력이 편한데"라는 생각으로 이 화이트리스트를
 * 풀지 마라.** 목록을 늘리는 것은 이 상수에 줄을 더하는 것이지 검사를 없애는
 * 것이 아니다.
 *
 * 한글 이름은 화면설계 캔버스의 「AI 대화 가이드 → 분야 고르기」 보드와 같은
 * 값이다. 앱 화면을 만들 때 이 목록을 기준으로 맞춘다.
 */
export const FIELD_LABELS: Readonly<Record<string, string>> = {
  finance: "금융·경제",
  it: "IT·기술",
  industry: "산업·제조",
  construction: "건설·부동산",
  medical: "의료·바이오",
  legal: "법률·회계",
  education: "교육",
  public: "공공·행정",
  media: "미디어·콘텐츠",
  retail: "유통·소비재",
};

/**
 * 목록에 있는 키면 한글 이름을, 아니면 null(= 분야 없음)을 준다.
 *
 * 모르는 키를 거절하지 않고 분야 없이 진행하는 이유: 앱과 서버의 목록이
 * 어긋났을 때 AI 가이드가 통째로 실패하는 것보다 분야만 빠진 채 나오는 것이
 * 낫다. 다만 **조용히 넘어가면 안 된다** — 부르는 쪽(index.ts)이 로그를
 * 남긴다. 조용히 좁아지는 것은 다음 사람에게 "AI가 원래 그런가 보다"로
 * 읽힌다.
 */
export function resolveFieldLabel(fieldKey?: string): string | null {
  const key = fieldKey?.trim();
  if (!key) return null;
  return Object.prototype.hasOwnProperty.call(FIELD_LABELS, key)
    ? FIELD_LABELS[key]
    : null;
}

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
  // 2026-08-26(추가 499): 사용자가 화면에서 직접 고른 분야 키(FIELD_LABELS).
  // 선택이다 — 안 오거나 목록에 없는 값이면 이 절을 통째로 생략하고 이전과
  // 똑같이 동작한다.
  //
  // 앱 화면은 아직 없다. 사용자 확정 순서가 "프롬프트를 먼저 고쳐 답이 실제로
  // 나아지는지 재고, 그다음 화면"이다 — 화면부터 만들면 효과가 없을 때 버릴
  // 것이 커진다.
  fieldKey?: string;
}

export function buildPrompt(
  data: GenerateBriefingRequest,
  variationSeed?: string,
): string {
  const commLogSummary =
    data.communicationLogs.length === 0
      ? "최근 소통 기록 없음"
      : data.communicationLogs.map((l) => `- ${l}`).join("\n");

  const fieldLabel = resolveFieldLabel(data.fieldKey);

  const contextLines = [
    data.contactSummary,
    `관심사: ${data.interests && data.interests.trim() ? data.interests : "없음"}`,
    ...(fieldLabel ? [`분야(사용자가 직접 고름): ${fieldLabel}`] : []),
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
${buildInstructionSection(fieldLabel)}${seedLine}`;
}

/**
 * 마지막 지시 절.
 *
 * ⚠️ 분야가 없으면 **2026-08-26 이전과 한 글자도 다르지 않은 문장**을 낸다.
 * 분야를 안 고른 사용자의 결과가 이번 변경으로 달라지면 안 된다 — 달라지면
 * 나중에 "분야를 넣어서 나아진 것"인지 "지시문을 건드려서 달라진 것"인지
 * 가릴 수 없고, 그러면 이 기능이 효과가 있는지 재는 것 자체가 불가능해진다.
 * 아래 첫 번째 분기의 문자열은 손대지 마라(자동 테스트가 고정하고 있다).
 */
function buildInstructionSection(fieldLabel: string | null): string {
  if (!fieldLabel) {
    return `각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 날씨 정보가 있다면 그중 한 문장 정도에 자연스럽게 녹여도 좋습니다.
단, 날씨는 사실만 담백하게 언급하고 "상쾌하다", "완벽한 날씨" 같은 주관적 단정은
피하세요. 상대방의 관심사나 직함/업종과 관련된 일반적인 화제(업계 동향, 최근 이슈 등 당신이
알고 있는 상식 수준의 내용)를 자연스럽게 언급하는 문장을 하나 포함해도 좋습니다 —
단, 확인되지 않은 구체적 사실·사건을 지어내지 마세요. 번호/불릿/설명 없이 대화
포인트 문장만 줄바꿈으로 구분해서 정확히 3개 작성하세요.`;
  }

  // 분야를 받으면 세 문장을 서로 다른 축에서 하나씩 뽑게 한다.
  //
  // 왜 축을 나누나: 기존 다양성 장치 둘(직전 포인트 회피 · 생성 시드)은
  // "다르게 말해라"이지 "다른 곳을 봐라"가 아니다. 셋 다 근황 인사로
  // 수렴하면 표현만 바꾼 같은 말 세 개가 나온다. 분야 축이 그 빈자리에
  // 들어간다.
  //
  // 🚨 지어내기 금지를 이 경로에서 훨씬 세게 거는 이유: 분야를 주면 모델이
  // **그 분야 뉴스처럼 들리는 문장**을 만들 유인이 커진다. 모델은 최신 동향을
  // 모르는데 아는 것처럼 쓴다. 기존의 "확인되지 않은 구체적 사실·사건을
  // 지어내지 마세요" 한 줄로는 약하다 — 그 문장은 무엇을 쓰지 말라고만 하고
  // **무엇을 대신 쓰라고는 안 한다.** 그래서 (1) 금지 대상을 구체적으로
  // 열거하고, (2) 사실을 주장하는 형태 대신 **묻는 형태**라는 대안을 준다.
  //
  // 프롬프트 본문에는 굵게(**) 같은 서식을 쓰지 않는다 — 모델이 그 서식을
  // 답변에 따라 쓰면 parseTalkingPoints가 걸러내지 못하고 화면에 그대로
  // 나온다. 불릿은 "-"만 쓴다(그건 파서가 이미 벗겨낸다).
  return `각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 세 문장은 서로 다른 축에서 하나씩 뽑아, 축이 서로 겹치지 않게 하세요.
- 분야 화제: 「${fieldLabel}」 분야에서 일하는 사람이라면 누구나 공감할 만한
  일반적인 관심사
- 관계·근황: 위 [최근 소통 기록]과 [상대방 정보]에 실제로 있는 내용에 기댄 근황
- 가벼운 안부: 부담 없는 인사. 날씨 정보가 있다면 이 문장에 자연스럽게 녹여도
  좋습니다. 단, 날씨는 사실만 담백하게 언급하고 "상쾌하다", "완벽한 날씨" 같은
  주관적 단정은 피하세요.

「${fieldLabel}」 분야 문장에서 반드시 지킬 것:
- 그 분야의 구체적인 사건·뉴스·정책·법령·수치·통계·기업명·제품명·인물명을
  언급하지 마세요. 당신은 최신 동향을 알지 못합니다. 아는 것처럼 쓰면 안 됩니다.
- "요즘 ~라고 하더라구요", "최근 ~가 화제죠" 처럼 사실을 주장하는 형태로 쓰지
  말고, "요즘 그쪽은 좀 어떠세요" 처럼 상대에게 묻는 형태로 쓰세요.
- 그 분야에 오래 있었던 사람이라면 늘 겪는 일(바쁜 시기, 일하는 방식, 사람을
  만나는 자리 같은 것) 수준으로만 다루세요.
- 상대방이 그 분야 안에서 정확히 무슨 일을 하는지 단정하지 마세요.

나머지 두 문장에서도 확인되지 않은 구체적 사실·사건을 지어내지 마세요.
번호/불릿/설명 없이 대화 포인트 문장만 줄바꿈으로 구분해서 정확히 3개
작성하세요.`;
}
