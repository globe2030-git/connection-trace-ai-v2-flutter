/**
 * 커넥션센스 AI 브리핑 서버 프록시.
 *
 * BYOK(사용자가 직접 AI API 키 발급)가 비개발자에게 진입장벽이 너무 높다는
 * 피드백에 따라, 서버(이 함수)가 앱 운영사 소유의 Gemini 키로 대신 호출하는
 * 구조로 전환한다. 설계 근거·비용 추정·리스크는
 * docs/planning/server-setup-plan.md 14번 섹션, 실제 적용 결정은
 * docs/planning/backlog.md 추가 68 참고.
 *
 * 배포 전제조건: Firebase 프로젝트가 Blaze(종량제) 요금제여야 한다(Cloud
 * Functions는 Spark 요금제에서 아예 실행되지 않음). 2026-08-07 Blaze 전환 후
 * asia-northeast3에 배포 완료됐다.
 *
 * 반드시 지킬 것(카드 등록 후 실제 배포 전 재확인):
 * - GEMINI_API_KEY는 반드시 결제가 연결된 유료 등급 계정에서 발급할 것.
 *   무료 등급은 입력을 사람이 검수·모델 개선에 활용하는 정책이 있어,
 *   타인(사용자의 지인)의 개인정보를 그 등급으로 보내는 건 위험하다(14.2절).
 * - 원문 프롬프트/응답을 로그(console.log)에 남기지 않는다 — Cloud Logging은
 *   기본 30일 보관되므로 그대로 찍으면 의도치 않은 개인정보 장기 보관이 된다.
 * - 대화 내용 자체는 Firestore 등에 영구 저장하지 않는다. 호출량 카운터만
 *   남긴다(아래 incrementAndCheckUsage).
 */

import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";

initializeApp();

const geminiApiKey = defineSecret("GEMINI_API_KEY");

// 정상 사용 범위와 명백한 어뷰징 사이의 안전한 상한선(14.4절 근거).
// 실사용 데이터가 쌓이면 재조정 가능 — 사용자 확인 후 조정.
const DAILY_LIMIT = 10;
const MONTHLY_LIMIT = 100;

// 출력 토큰 상한. 2026-08-07: 원래 400이었는데 gemini-3.6-flash가 "*Draft
// A:*" 같은 내부 사고/초안 텍스트를 답변 앞에 먼저 쓰는 습성이 있어 진짜 최종
// 답변에 도달하기 전에 토큰이 바닥나 버렸다(실기기 확인 — "contact since
// exchanging cards)." 같은 초안 파편만 남고 끝남). 사고 과정 몫 여유를 넉넉히
// 두고, 최종 파싱에서 한국어 문장만 걸러낸다(parseTalkingPoints).
//
// 이 값은 **과금액이 아니라 최악의 경우를 묶는 천장**이다(과금은 실제 사용한
// 토큰 기준). 다만 Gemini는 **사고(thinking) 토큰을 출력과 같은 단가로 과금**
// 하므로($7.50/1M, 입력은 $1.50/1M), 모델이 마음껏 생각하면 이 천장까지 요금이
// 오를 수 있다 — 2026-08-08 실측에서 사고 토큰이 회당 1,275~1,328개로 과금
// 출력의 91%를 차지했다. 그래서 천장을 낮추는 대신 아래 THINKING_LEVEL로
// 사고량 자체를 줄였고, 그 뒤 실측은 사고 0~590 / 출력 97~108이다.
// 천장을 3000으로 남겨 두는 이유는 2026-08-07의 응답 잘림 버그 재발 방지다.
const MAX_OUTPUT_TOKENS = 3000;

const GEMINI_MODEL = "gemini-3.6-flash";

// 사고(reasoning) 깊이. 위치와 형식은 **추측하지 말고 API 디스커버리 문서에서
// 확인한 것**이다(2026-08-08):
//
//   GET https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta
//   GenerationConfig.thinkingConfig → ThinkingConfig.thinkingLevel
//   enum: THINKING_LEVEL_UNSPECIFIED | MINIMAL | LOW | MEDIUM | HIGH
//
// 이 자리에서 두 번 틀렸다. 2026-08-07엔 `thinkingConfig.thinkingBudget: 0`이
// 거부됐고(그래서 "스키마를 확신할 수 없다"며 옵션을 통째로 뺐다),
// 2026-08-08엔 문서 예시만 보고 `generationConfig.thinkingLevel`(한 단계 바깥,
// 소문자)로 넣었다가 또 거부됐다 — 실기기 로그에 "Unknown name thinkingLevel
// at 'generation_config'". **모델 파라미터는 문서 예시가 아니라 그 API 버전의
// 디스커버리 문서를 봐야 한다.**
//
// LOW를 고른 이유: 이 작업은 "짧은 한국어 문장 3개 쓰기"라 깊은 추론이 필요
// 없다. MINIMAL이 더 싸지만 품질 저하 위험이 있어 한 단계 보수적으로 잡고,
// 아래 usageMetadata 로그로 실측한 뒤 조정한다.
const THINKING_LEVEL = "LOW";

interface GenerateBriefingRequest {
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
}

interface GenerateBriefingResponse {
  talkingPoints: string[];
}

function buildPrompt(data: GenerateBriefingRequest): string {
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

  return `당신은 비즈니스 네트워킹 어시스턴트입니다. 사용자는 낯을 가리는 편이라 먼저
연락하는 것을 어색해합니다. 아래 정보를 참고해 사용자가 상대방에게 부담 없이
자연스럽게 안부를 전하며 인연을 이어갈 수 있는 대화 포인트를 만들어 주세요.

[나(사용자) 정보]
${data.myProfileSummary}

[상대방 정보]
${contextLines.join("\n")}

[최근 소통 기록]
${commLogSummary}
${extraNoteSection}
각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 날씨 정보가 있다면 그중 한 문장 정도에 자연스럽게 녹여도 좋습니다.
상대방의 관심사나 직함/업종과 관련된 일반적인 화제(업계 동향, 최근 이슈 등 당신이
알고 있는 상식 수준의 내용)를 자연스럽게 언급하는 문장을 하나 포함해도 좋습니다 —
단, 확인되지 않은 구체적 사실·사건을 지어내지 마세요. 번호/불릿/설명 없이 대화
포인트 문장만 줄바꿈으로 구분해서 정확히 3개 작성하세요.`;
}

// 프롬프트가 "한국어로" 작성하라고 명시했으므로, 진짜 대화 포인트는 항상
// 한글을 포함한다. gemini-3.6-flash가 답변 앞에 남기는 영어 초안/사고 과정
// 파편("*Draft A:*", "Include industry/profession topic in *one* sentence
// naturally" 등, 실기기 확인)은 전부 한글이 없다 — 이 성질로 걸러낸다.
const HANGUL_RE = /[가-힣]/;

function parseTalkingPoints(raw: string): string[] {
  return raw
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .map((l) => l.replace(/^[\d.\-*•]+\s*/, ""))
    .map((l) => l.replace(/^"|"$/g, ""))
    .filter((l) => HANGUL_RE.test(l))
    .slice(0, 3);
}

interface GeminiUsage {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
  totalTokenCount?: number;
}

/**
 * Gemini에 한 번 요청한다. [withThinkingLevel]이 false면 thinkingLevel을
 * 아예 빼고 보낸다(아래 fallback 용도).
 */
async function requestGemini(
  prompt: string,
  apiKey: string,
  withThinkingLevel: boolean
): Promise<Response> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
  return fetch(url, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      contents: [{parts: [{text: prompt}]}],
      generationConfig: {
        maxOutputTokens: MAX_OUTPUT_TOKENS,
        ...(withThinkingLevel
          ? {thinkingConfig: {thinkingLevel: THINKING_LEVEL}}
          : {}),
      },
    }),
  });
}

async function callGemini(prompt: string, apiKey: string): Promise<string> {
  let usedThinkingLevel = true;
  let response = await requestGemini(prompt, apiKey, true);

  // thinkingLevel이 거부되면 그것 없이 한 번 더 보낸다.
  //
  // 왜 이런 안전장치를 두나: 2026-08-07에 thinking 관련 파라미터(당시엔 잘못된
  // 필드명 thinkingBudget)가 400으로 거부돼 AI 브리핑이 통째로 죽은 전례가
  // 있다. 모델 파라미터 스키마는 우리가 통제하지 못하고 예고 없이 바뀔 수
  // 있는데, 그때 기능이 "비싸지는 것"과 "아예 안 되는 것" 중에는 전자가 낫다.
  // 어느 경로로 응답했는지는 아래 usage 로그에 함께 남긴다.
  if (response.status === 400) {
    const bodyText = await response.text().catch(() => "");
    logger.warn("thinkingLevel이 거부됨 — 이 옵션 없이 재시도", {
      body: bodyText.slice(0, 500),
    });
    usedThinkingLevel = false;
    response = await requestGemini(prompt, apiKey, false);
  }

  if (!response.ok) {
    // 2026-08-07: 상태 코드만 로그에 남겼더니 429가 어느 한도(무료 티어 RPM인지,
    // 결제 연결이 아직 인식 안 된 것인지, 실제 유료 티어 쿼터 초과인지) 때문인지
    // 알 수가 없어 원인 파악이 막혔다. 본문은 Google이 반환하는 에러 사유
    // 텍스트(쿼터 메트릭 이름 등)뿐이라 사용자 프롬프트나 개인정보가 섞이지
    // 않는다 — 진단을 위해 본문도 함께 남긴다.
    const bodyText = await response.text().catch(() => "");
    logger.error("Gemini API error", {status: response.status, body: bodyText});
    throw new HttpsError(
      "unavailable",
      "AI 응답을 받지 못했습니다. 잠시 후 다시 시도해 주세요."
    );
  }

  const json = (await response.json()) as {
    candidates?: {content?: {parts?: {text?: string; thought?: boolean}[]}}[];
    usageMetadata?: GeminiUsage;
  };

  // 토큰 사용량을 남긴다 — **숫자와 설정값뿐이라 개인정보가 섞이지 않는다.**
  //
  // 왜 필요한가: 2026-08-08에 "회당 얼마인가"를 물었을 때 답할 근거가 없어,
  // 지출액 ÷ 추정 호출 수 + 환율 가정으로 역산해야 했다(server-setup-plan.md
  // 14.5절의 설계 추정과 5배 차이). 비용은 손익 모델과 구독 가격 결정에
  // 직접 연결되므로 추정이 아니라 실측으로 다뤄야 한다.
  //
  // thoughtsTokenCount가 핵심이다 — 사고 토큰은 출력과 같은 단가로 과금되므로
  // 이 값이 곧 "눈에 안 보이는 비용"이다.
  const usage = json.usageMetadata ?? {};
  logger.info("Gemini 토큰 사용량", {
    model: GEMINI_MODEL,
    thinkingLevel: usedThinkingLevel ? THINKING_LEVEL : "(미적용)",
    maxOutputTokens: MAX_OUTPUT_TOKENS,
    promptTokenCount: usage.promptTokenCount,
    candidatesTokenCount: usage.candidatesTokenCount,
    thoughtsTokenCount: usage.thoughtsTokenCount,
    totalTokenCount: usage.totalTokenCount,
  });

  const parts = json.candidates?.[0]?.content?.parts ?? [];
  // 사고량을 낮춰도 thought 파트가 섞여 오면 최종 답변이 아니니 걸러낸다.
  return parts
    .filter((p) => !p.thought)
    .map((p) => p.text ?? "")
    .join("\n");
}

/**
 * uid별 일/월 호출량을 Firestore 트랜잭션으로 원자적으로 확인·증가시킨다.
 * 상한 초과 시 HttpsError를 던진다(트랜잭션 안에서 던지면 카운터 증가도
 * 함께 롤백되어 정확하다).
 */
async function incrementAndCheckUsage(uid: string): Promise<void> {
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const now = new Date();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const usage = snap.data()?.aiUsage as
      | {
          dailyCount?: number;
          dailyResetAt?: FirebaseFirestore.Timestamp;
          monthlyCount?: number;
          monthlyResetAt?: FirebaseFirestore.Timestamp;
        }
      | undefined;

    const dailyResetAt = usage?.dailyResetAt?.toDate();
    const monthlyResetAt = usage?.monthlyResetAt?.toDate();

    const dailyExpired = !dailyResetAt || dailyResetAt.getTime() <= now.getTime();
    const monthlyExpired =
      !monthlyResetAt || monthlyResetAt.getTime() <= now.getTime();

    const dailyCount = dailyExpired ? 0 : (usage?.dailyCount ?? 0);
    const monthlyCount = monthlyExpired ? 0 : (usage?.monthlyCount ?? 0);

    if (dailyCount >= DAILY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "오늘 사용 가능한 AI 브리핑 횟수를 모두 사용했어요. 내일 다시 시도해 주세요."
      );
    }
    if (monthlyCount >= MONTHLY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "이번 달 AI 브리핑 사용 한도에 도달했어요. 다음 달 1일에 초기화됩니다."
      );
    }

    const nextMidnight = new Date(now);
    nextMidnight.setHours(24, 0, 0, 0);
    const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);

    tx.set(
      userRef,
      {
        aiUsage: {
          dailyCount: dailyCount + 1,
          dailyResetAt: dailyExpired ? nextMidnight : (usage?.dailyResetAt ?? nextMidnight),
          monthlyCount: monthlyCount + 1,
          monthlyResetAt: monthlyExpired ? nextMonth : (usage?.monthlyResetAt ?? nextMonth),
        },
      },
      {merge: true}
    );
  });
}

// 동시에 뜰 수 있는 인스턴스 상한. 어뷰징이나 버그로 호출이 몰리면 인스턴스가
// 늘어나며 Gemini 호출 요금이 그대로 따라 늘어나므로 낮게 묶어 둔다.
//
// **3인 이유**: 2026-08-08에 배포된 함수 설정을 직접 조회해 보니 코드에
// 아무 지정이 없는데도 이미 `maxInstanceCount: 3`이 잡혀 있었다. 값을
// 명시하지 않으면 이렇게 "어디서 온 건지 모르는 숫자"에 의존하게 되고,
// 다음 배포에서 조용히 바뀌어도 아무도 모른다 — 그래서 지금 걸려 있던 값을
// 그대로 코드에 고정한다. 올릴 이유가 생기면 그때 근거와 함께 올린다.
//
// 인스턴스당 동시 요청이 80이라 3개면 최대 240건을 동시에 처리한다. 실사용은
// 사람이 화면에서 한 번씩 누르는 패턴이라 충분하고, 넘쳐도 사용자에게는
// "잠시 후 다시 시도" 안내로 끝난다 — 요금이 새는 것보다 낫다.
const MAX_INSTANCES = 3;

export const generateBriefing = onCall<GenerateBriefingRequest>(
  {
    secrets: [geminiApiKey],
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
    // 유효한 App Check 토큰이 없는 호출은 거부한다(2026-08-08 전환). 이걸
    // 켜기 전에는 Google 로그인만 통과하면 우리 앱이 아닌 스크립트도 회사
    // 명의 유료 Gemini 키를 쓸 수 있었다(backlog 추가 82 신규-B).
    //
    // ⚠️ 이걸 켠 뒤로는 **토큰을 못 만드는 빌드는 AI 브리핑이 막힌다.**
    // 스토어를 거치지 않는 빌드(테스터 APK, devicectl 직접 설치 iOS)는
    // `tool/build_app.sh <타겟> release appcheck-debug`로 빌드하고 그 기기의
    // 디버그 토큰을 Firebase에 등록해야 한다. 근거는
    // lib/core/services/app_check_service.dart 주석, 절차는
    // docs/planning/admin-manual.md의 App Check 절.
    enforceAppCheck: true,
  },
  async (request): Promise<GenerateBriefingResponse> => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "로그인 후 이용할 수 있어요."
      );
    }

    // 강제 전환 판단에 필요한 유일한 정보는 "유효한 토큰이 왔는가" 하나다.
    // uid나 토큰 원문은 남기지 않는다(Cloud Logging 기본 30일 보관).
    logger.info("generateBriefing 호출", {appCheckVerified: !!request.app});

    const {
      contactSummary,
      myProfileSummary,
      communicationLogs,
      weatherSummary,
      interests,
      extraNote,
    } = request.data;
    if (!contactSummary || !myProfileSummary) {
      throw new HttpsError(
        "invalid-argument",
        "필수 정보가 누락됐어요."
      );
    }

    await incrementAndCheckUsage(request.auth.uid);

    const prompt = buildPrompt({
      contactSummary,
      myProfileSummary,
      communicationLogs: communicationLogs ?? [],
      weatherSummary,
      interests,
      extraNote,
    });
    const rawText = await callGemini(prompt, geminiApiKey.value());
    const talkingPoints = parseTalkingPoints(rawText);

    if (talkingPoints.length === 0) {
      throw new HttpsError("internal", "AI가 빈 응답을 반환했습니다.");
    }

    return {talkingPoints};
  }
);
