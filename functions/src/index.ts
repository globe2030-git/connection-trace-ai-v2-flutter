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
import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import {sign as cryptoSign} from "crypto";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {nextKstMidnight, nextKstMonthStart} from "./usageReset";
import {ADMIN_EMAILS} from "./adminEmails";
import {validateGrantAmount, validateGrantMetadata} from "./creditGrant";
import {chunkArray} from "./chunk";
import {
  BillingModel,
  WalletExhaustedError,
  consumeWalletCredit,
  resolveBillingModel,
} from "./walletCredits";

initializeApp();

const geminiApiKey = defineSecret("GEMINI_API_KEY");

// Sign in with Apple 토큰 폐기(P1-38)에 쓰는 Apple 개인키(.p8) 원문.
// `firebase functions:secrets:set APPLE_SIGNIN_KEY`로 .p8 파일 내용을 넣는다
// (-----BEGIN PRIVATE KEY----- 부터 END 까지 통째로). 이 비밀이 없으면 아래
// 두 함수는 배포되지 않는다.
const appleSignInKey = defineSecret("APPLE_SIGNIN_KEY");
const APPLE_TEAM_ID = "77L7BH2M2W";
const APPLE_KEY_ID = "UUYAKPD4S7";
// 네이티브 iOS Sign in with Apple의 client_id는 앱 번들 ID다(웹 Services ID 아님).
const APPLE_CLIENT_ID = "com.creamhouse.connectionsense";

// 정상 사용 범위와 명백한 어뷰징 사이의 안전한 상한선(14.4절 근거).
// 실사용 데이터가 쌓이면 재조정 가능 — 사용자 확인 후 조정.
//
// 🚧 **직원 테스트 기간 한정 20. 설계값은 10이고 스토어 제출 전에 반드시
// 되돌린다(P0-11).**
//
// 경위: 2026-08-08 사고 토큰 단가 측정을 위해 10 → 20으로 올렸고, 측정이
// 끝난 2026-08-10에 10으로 되돌렸다가(추가 147), 같은 날 **직원 테스트를
// 시작하며 다시 20으로 올렸다**(추가 148). 테스터가 하루에 여러 번 눌러 봐야
// 하는데 10회에 막히면 "AI가 안 된다"는 제보만 쌓이고 정작 봐야 할 것을 못
// 본다. 테스트 목적이 비용 절감보다 우선이라는 판단이다.
//
// 되돌리지 않고 출시하면 **1인당 비용 상한이 설계의 2배**가 된다.
//
// ⚠️ 이 값을 바꾸면 `lib/core/services/ai_briefing_service.dart`의
// `dailyLimit`도 **같이** 바꿔야 한다. 판정은 서버가 하고 앱은 표시만 하므로,
// 어긋나면 화면엔 "남음"인데 서버가 거절하는 상황이 된다.
const DAILY_LIMIT = 20;
// 월 한도는 올리지 않았다. 하루 20회를 5일 채우면 여기에 먼저 걸리므로,
// 테스트가 길어지면 이쪽이 다음 병목이 된다.
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

// F-07(재생성 다양성): 생성 파라미터. temperature/topP를 명시하지 않으면
// 모델 기본값으로 도는데, 같은 프롬프트를 다시 넣으면 매번 거의 같은 안전한
// 답으로 수렴한다("새로 생성"을 눌러도 비슷하다는 테스터 피드백 F-07의 한 축).
// temperature를 올려 표본을 넓히고 topP로 후보 분포를 유지한다. 값이 너무
// 높으면 문장이 부자연스러워지므로 1.0/0.95로 잡는다(사용자 승인 범위 0.9~1.1).
// 나머지 한 축(직전 포인트 제외)은 buildPrompt의 previousPoints가 담당한다.
const TEMPERATURE = 1.0;
const TOP_P = 0.95;

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
// 단계별 실측(2026-08-08, 서로 다른 명함 2개 × 단계당 2~3회, 캐시 0).
// 상세 표와 경위는 docs/planning/server-setup-plan.md 14.5절 / backlog 추가 100.
//
//   회당 비용        명함 A(입력 379)   명함 B(입력 1,030)
//   MINIMAL          $0.0014            $0.0023      ← 채택
//   LOW              $0.0070            $0.0067
//   MEDIUM           $0.0094            $0.0138
//   HIGH             $0.0103            $0.0124
//
// **MINIMAL을 고른 이유는 싸서가 아니라 예측 가능해서다.** 사고 토큰이 세
// 명함 모두에서 0이었다. 나머지 단계는 같은 값을 줘도 명함에 따라 사고가
// 0~1,566까지 튀어서 원가를 계산할 수 없다 — 특히 LOW는 어떤 명함에선 0,
// 다른 명함에선 823이었다. 구독 원가를 설계하려면 이 예측 가능성이 필요하다.
//
// 주의: 단계 이름과 실제 사고량이 정확히 비례하지 않는다. 명함 B에서는
// MEDIUM(1,472~1,566)이 HIGH(1,339)보다 더 많이 생각했다.
//
// **품질은 결론을 내지 않았다.** 명함 A에서는 단계가 높을수록 좋아 보였는데
// (MINIMAL "괜찮음" → HIGH "좋음") 명함 B에서는 재현되지 않았다(LOW가 가장
// 좋고 MEDIUM·HIGH는 MINIMAL 수준). 단계당 2~3회·판단자 1명으로는 이 정도
// 차이를 가릴 수 없다. "높은 단계 = 좋은 품질"은 **유망한 가설이지 검증된
// 사실이 아니다** — 구독 등급(무료=MINIMAL / 유료=HIGH)의 근거로 쓰려면
// 표본을 늘려 다시 검증해야 한다. HANDOFF "3. 해야 할 일" P1-5 참고.
const THINKING_LEVEL = "MINIMAL";

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
  // F-07(재생성 다양성): "새로 생성"을 누르기 직전 화면에 떠 있던 대화 포인트.
  // 클라이언트가 그대로 넘기면(briefing_overlay_view.dart) 프롬프트가 이
  // 문장들을 피해 새 각도로 만들도록 지시한다. 최초 생성이면 비어 있거나
  // 넘어오지 않는다 — 그때는 제외 지시를 생략한다.
  previousPoints?: string[];
}

interface GenerateBriefingResponse {
  talkingPoints: string[];
}

function buildPrompt(
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
  // 캐시된 입력 토큰. 같은 프롬프트를 반복해서 보내면 Gemini의 암묵적 캐싱이
  // 걸려 입력이 할인될 수 있는데, 단가를 "같은 화면 새로고침"으로 재는 동안은
  // 이게 켜지면 실사용보다 싸게 측정된다. 값이 0인지 확인하려고 남긴다.
  cachedContentTokenCount?: number;
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
        // F-07: 재생성 시 다양성을 위해 명시(위 TEMPERATURE/TOP_P 주석 참고).
        temperature: TEMPERATURE,
        topP: TOP_P,
        ...(withThinkingLevel
          ? {thinkingConfig: {thinkingLevel: THINKING_LEVEL}}
          : {}),
      },
    }),
  });
}

async function callGemini(
  prompt: string,
  apiKey: string,
): Promise<{text: string; usage: GeminiUsage}> {
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
    cachedContentTokenCount: usage.cachedContentTokenCount ?? 0,
    candidatesTokenCount: usage.candidatesTokenCount,
    thoughtsTokenCount: usage.thoughtsTokenCount,
    totalTokenCount: usage.totalTokenCount,
  });

  const parts = json.candidates?.[0]?.content?.parts ?? [];
  // 사고량을 낮춰도 thought 파트가 섞여 오면 최종 답변이 아니니 걸러낸다.
  const text = parts
    .filter((p) => !p.thought)
    .map((p) => p.text ?? "")
    .join("\n");
  return {text, usage};
}

/**
 * uid별 일/월 호출량을 Firestore 트랜잭션으로 원자적으로 확인·증가시킨다.
 * 상한 초과 시 HttpsError를 던진다(트랜잭션 안에서 던지면 카운터 증가도
 * 함께 롤백되어 정확하다).
 *
 * wallet 모드(2026-08-14, U1, ai-credit-wallet-spec.md §3-2): `config/billing
 * .model`이 `'wallet'`이면 아래 트랜잭션 맨 앞에서 무료(free)→충전(paid)
 * 잔액 차감 분기를 타고 `return`한다 — 그 아래 있는 기존 `dailyCount`/
 * `monthlyCount`/`bonusCredits` 기반 판정(=reset 모드)은 **한 글자도 안
 * 바뀐 채** 그대로 남아 있고, `model`이 `'reset'`이거나 미설정이면 지금과
 * 완전히 동일하게 그 경로만 실행된다.
 */
async function incrementAndCheckUsage(uid: string): Promise<void> {
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const now = new Date();

  // config/billing.model은 트랜잭션 밖에서 먼저 읽는다(외부 읽기를 트랜잭션
  // 안에 넣지 않는 게 원칙). 조회 자체가 실패해도(문서 없음 포함)
  // resolveBillingModel이 반드시 'reset'으로 폴백한다 — wallet로 폴백하면
  // 장애 시 조용히 무제한 과금 모델이 되는 위험이 있다(스펙 §3-2).
  let billingModel: BillingModel = "reset";
  try {
    const billingSnap = await db.collection("config").doc("billing").get();
    billingModel = resolveBillingModel(
      billingSnap.exists ? billingSnap.data() : undefined
    );
  } catch (err) {
    logger.warn("config/billing 조회 실패 — reset 모드로 폴백", {
      error: err instanceof Error ? err.message : String(err),
    });
  }

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const usage = snap.data()?.aiUsage as
      | {
          dailyCount?: number;
          dailyResetAt?: FirebaseFirestore.Timestamp;
          monthlyCount?: number;
          monthlyResetAt?: FirebaseFirestore.Timestamp;
          bonusCredits?: number;
          freeBalance?: number;
          paidBalance?: number;
        }
      | undefined;

    const dailyResetAt = usage?.dailyResetAt?.toDate();
    const monthlyResetAt = usage?.monthlyResetAt?.toDate();

    const dailyExpired = !dailyResetAt || dailyResetAt.getTime() <= now.getTime();
    const monthlyExpired =
      !monthlyResetAt || monthlyResetAt.getTime() <= now.getTime();

    const dailyCount = dailyExpired ? 0 : (usage?.dailyCount ?? 0);
    const monthlyCount = monthlyExpired ? 0 : (usage?.monthlyCount ?? 0);

    if (billingModel === "wallet") {
      // wallet 분기 — 무료(free) 먼저, 그다음 충전(paid) 소진(스펙 §3-2).
      // 실제 차감 판정은 순수 함수(walletCredits.ts)에 맡기고 여기서는
      // Firestore 읽기/쓰기만 한다.
      let nextBalances;
      try {
        nextBalances = consumeWalletCredit({
          free: usage?.freeBalance ?? 0,
          paid: usage?.paidBalance ?? 0,
        });
      } catch (err) {
        if (err instanceof WalletExhaustedError) {
          throw new HttpsError("resource-exhausted", err.message);
        }
        throw err;
      }

      // 표시용 카운터(설정 → AI 사용량의 "오늘 사용 N회")는 게이팅에는 안
      // 쓰지만 wallet 모드에서도 계속 갱신한다(스펙 §3-3 — 새 필드 없이
      // 기존 표시 로직을 그대로 재사용하기 위함).
      const nextMidnight = nextKstMidnight(now);
      const nextMonth = nextKstMonthStart(now);
      tx.set(
        userRef,
        {
          aiUsage: {
            freeBalance: nextBalances.free,
            paidBalance: nextBalances.paid,
            dailyCount: dailyCount + 1,
            dailyResetAt: dailyExpired ? nextMidnight : (usage?.dailyResetAt ?? nextMidnight),
            monthlyCount: monthlyCount + 1,
            monthlyResetAt: monthlyExpired ? nextMonth : (usage?.monthlyResetAt ?? nextMonth),
          },
        },
        {merge: true}
      );
      return;
    }

    // 'reset' 모드 — 여기부터 tx.set까지는 원래 코드 그대로다(문자 그대로
    // 동일한지 diff로 확인할 것, wallet-credit-spec.md §3-2 인수 기준).
    // 관리자가 지급한 무료 회차(또는 향후 충전 회차). 일/월 한도를 다 쓴
    // 뒤에도 남아 있으면 이걸 먼저 소진해 계속 쓸 수 있게 한다 — "추가로
    // 준 회차"이므로 일/월 카운트에는 올리지 않고 잔액만 1 줄인다.
    const bonusCredits = usage?.bonusCredits ?? 0;

    if (dailyCount >= DAILY_LIMIT || monthlyCount >= MONTHLY_LIMIT) {
      if (bonusCredits > 0) {
        tx.set(
          userRef,
          {aiUsage: {bonusCredits: bonusCredits - 1}},
          {merge: true}
        );
        return;
      }
      if (dailyCount >= DAILY_LIMIT) {
        throw new HttpsError(
          "resource-exhausted",
          "오늘 사용 가능한 AI 브리핑 횟수를 모두 사용했어요. 내일 다시 시도해 주세요."
        );
      }
      throw new HttpsError(
        "resource-exhausted",
        "이번 달 AI 브리핑 사용 한도에 도달했어요. 다음 달 1일에 초기화됩니다."
      );
    }

    // 반드시 한국시간(KST) 기준 자정/월초여야 한다 — 서버 로컬 시간대에
    // 기대는 `setHours`/`getMonth`를 쓰면 Cloud Functions 런타임 기본 시간대인
    // UTC로 계산돼 리셋이 실제로는 한국시간 오전 9시에 일어난다(usageReset.ts
    // 상단 주석 참고).
    const nextMidnight = nextKstMidnight(now);
    const nextMonth = nextKstMonthStart(now);

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

/**
 * 테스터 허용목록 검사. 스토어를 거치지 않은 빌드는 App Check 토큰을 못 만들어
 * AI 호출이 막힌다. 관리자 콘솔에서 `config/testers.emails`에 등록한 이메일은
 * 테스트 기간 동안 App Check 없이도 허용한다. Admin SDK로 읽어 보안 규칙을
 * 우회한다. 대소문자 차이로 빠지지 않도록 소문자로 비교한다.
 */
async function isAllowlistedTester(
  email: string | undefined | null,
): Promise<boolean> {
  if (!email) return false;
  const db = getFirestore();
  const snap = await db.collection("config").doc("testers").get();
  if (!snap.exists) return false;
  const emails = (snap.data()?.emails ?? []) as string[];
  const target = email.toLowerCase();
  return emails.some((e) => String(e).toLowerCase() === target);
}

function isAdminRequest(auth: {token: {email?: string; email_verified?: boolean}} | undefined): boolean {
  const token = auth?.token;
  return (
    !!token &&
    token.email_verified === true &&
    !!token.email &&
    ADMIN_EMAILS.includes(token.email)
  );
}

/**
 * AI 호출 감사 로그. 불만 처리·비용 추적을 위해 "누가 언제 호출했고 성공했는지,
 * 실패했다면 왜인지, 토큰을 얼마나 썼는지"를 남긴다.
 *
 * ⚠️ 개인정보 원칙: **계정 식별자(uid·로그인 이메일)와 사용량만** 남긴다.
 * 명함(제3자) 정보나 프롬프트 원문·응답 본문은 절대 남기지 않는다.
 * 이 로그를 남기는 것은 개인정보처리방침의 "지원·부정사용/비용 관리 목적
 * 이용 로그"에 근거한다(방침 반영 필요, backlog 추가 112).
 *
 * 절대 throw하지 않는다 — 로깅 실패가 본 기능(AI 응답)을 막으면 안 된다.
 */
async function writeAiAuditLog(record: {
  uid: string;
  email: string | null;
  ok: boolean;
  errorCode: string | null;
  appCheckVerified: boolean;
  viaAllowlist: boolean;
  usage?: GeminiUsage;
  latencyMs: number;
}): Promise<void> {
  try {
    const db = getFirestore();
    const u = record.usage ?? {};
    await db.collection("aiAuditLogs").add({
      at: FieldValue.serverTimestamp(),
      uid: record.uid,
      email: record.email,
      ok: record.ok,
      errorCode: record.errorCode,
      appCheckVerified: record.appCheckVerified,
      viaAllowlist: record.viaAllowlist,
      promptTokenCount: u.promptTokenCount ?? null,
      candidatesTokenCount: u.candidatesTokenCount ?? null,
      thoughtsTokenCount: u.thoughtsTokenCount ?? null,
      totalTokenCount: u.totalTokenCount ?? null,
      latencyMs: record.latencyMs,
    });
  } catch (e) {
    // 로그 자체가 실패해도 본 기능은 계속된다.
    logger.warn("aiAuditLog 기록 실패", {errorType: (e as Error)?.name});
  }
}

export const generateBriefing = onCall<GenerateBriefingRequest>(
  {
    secrets: [geminiApiKey],
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
    // 유효한 App Check 토큰이 없는 호출을 원칙적으로 거부한다(2026-08-08 도입).
    // 이 보호가 없으면 Google 로그인만 통과하면 우리 앱이 아닌 스크립트도 회사
    // 명의 유료 Gemini 키를 쓸 수 있다(backlog 추가 82 신규-B).
    //
    // ⚠️ 2026-08-09: 직원 테스트 기간 동안 App Check "강제"를 끄고 **아래 함수
    // 본문에서 수동으로 검사**한다. 스토어(TestFlight/Play)를 거치지 않은 빌드는
    // App Check 토큰을 못 만들어 AI가 막히는데, 매 기기 디버그 토큰을 등록하는
    // 건 직원 배포에 비현실적이라(로그캣에만 뜸), 대신 관리자 콘솔에 등록한
    // 테스터 이메일(config/testers)을 App Check 없이도 허용하는 방식으로 바꿨다.
    // 정식 앱(유효 토큰)은 그대로 통과하고, 토큰도 없고 허용목록에도 없으면
    // 거부하므로 외부 스크립트 남용 방어는 유지된다. 일일 한도도 그대로 적용.
    // 근거·절차: docs/planning/backlog.md 추가 111, 관리자 콘솔 "테스터 관리" 탭.
    // ⚠️ 테스트 종료 후 config/testers를 비우고 enforceAppCheck: true 복원 검토.
    enforceAppCheck: false,
  },
  async (request): Promise<GenerateBriefingResponse> => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "로그인 후 이용할 수 있어요."
      );
    }

    // enforceAppCheck를 끈 대신 여기서 수동으로 검사한다(위 옵션 주석 참고).
    // 유효한 App Check 토큰이 있거나(정식 스토어 앱), 관리자 콘솔에 등록된
    // 테스터 이메일이면 통과. 둘 다 아니면 거부해 외부 스크립트 남용을 막는다.
    const appCheckVerified = !!request.app;
    if (!appCheckVerified &&
        !(await isAllowlistedTester(request.auth.token.email))) {
      throw new HttpsError(
        "failed-precondition",
        "앱 무결성 확인에 실패했어요. 최신 버전의 정식 앱에서 다시 시도해 주세요.",
      );
    }

    // uid·토큰 원문은 Cloud Logging엔 남기지 않는다(기본 30일 보관). 계정
    // 식별자와 함께 남기는 감사 로그는 아래 writeAiAuditLog가 aiAuditLogs에
    // 따로 기록한다(불만 처리·비용 추적용).
    logger.info("generateBriefing 호출", {appCheckVerified});

    const uid = request.auth.uid;
    const email = request.auth.token.email ?? null;
    // App Check 토큰이 없는데 통과했다면 테스터 허용목록으로 들어온 것이다.
    const viaAllowlist = !appCheckVerified;
    const startedAt = Date.now();

    try {
      const {
        contactSummary,
        myProfileSummary,
        communicationLogs,
        weatherSummary,
        interests,
        extraNote,
        previousPoints,
      } = request.data;
      if (!contactSummary || !myProfileSummary) {
        throw new HttpsError(
          "invalid-argument",
          "필수 정보가 누락됐어요."
        );
      }

      await incrementAndCheckUsage(uid);

      // F-07: 매 호출 고유한 회차 시드. 같은 입력으로 "새로 생성"을 눌러도
      // 프롬프트 문자열이 달라져 응답이 굳어지는 것을 막는다.
      const variationSeed = Math.random().toString(36).slice(2, 8);
      const prompt = buildPrompt({
        contactSummary,
        myProfileSummary,
        communicationLogs: communicationLogs ?? [],
        weatherSummary,
        interests,
        extraNote,
        previousPoints,
      }, variationSeed);
      const {text: rawText, usage} = await callGemini(
        prompt,
        geminiApiKey.value(),
      );
      const talkingPoints = parseTalkingPoints(rawText);

      if (talkingPoints.length === 0) {
        throw new HttpsError("internal", "AI가 빈 응답을 반환했습니다.");
      }

      await writeAiAuditLog({
        uid,
        email,
        ok: true,
        errorCode: null,
        appCheckVerified,
        viaAllowlist,
        usage,
        latencyMs: Date.now() - startedAt,
      });
      return {talkingPoints};
    } catch (e) {
      const errorCode = e instanceof HttpsError ? e.code : "internal";
      await writeAiAuditLog({
        uid,
        email,
        ok: false,
        errorCode,
        appCheckVerified,
        viaAllowlist,
        latencyMs: Date.now() - startedAt,
      });
      throw e;
    }
  }
);

/**
 * 회원 탈퇴(설정 → 계정 삭제) 시 그 사용자의 AI 호출 로그·1:1 문의를 함께
 * 파기한다.
 *
 * 왜 트리거인가: 클라이언트는 users/{uid}·contacts를 직접 지우지만,
 * aiAuditLogs는 보안 규칙상 클라이언트가 못 지운다(관리자 읽기 전용, 서버만
 * 기록). 탈퇴 흐름은 users/{uid} 문서를 삭제하는데, 그때 이 트리거가 그 uid의
 * 감사 로그를 batch로 삭제한다. 개인정보처리방침 "회원 탈퇴 시 파기"와 일치
 * (backlog 추가 112).
 *
 * ⚠️ 2026-08-15(ADMIN-VULN-007): inquiries(1:1 문의, top-level 컬렉션)도
 * userId 필드로 소유되는데 여기서 빠져 있어서, 탈퇴 후에도 문의(이메일·제목·
 * 본문)와 답변이 영구히 남아 관리자에게 계속 노출됐다. inquiries는
 * users/{uid} 하위가 아니라 별도 top-level 컬렉션이라 클라이언트가 계정
 * 삭제 시 직접 못 지우고(보안 규칙상 delete 자체가 항상 false), 여기서 함께
 * 정리한다.
 *
 * v1 auth onDelete는 firebase-functions/v1이 database provider를 끌어와
 * (@firebase/app 미설치) 배포 분석이 깨져서 못 쓴다. 대신 v2 Firestore 트리거를
 * 쓴다 — DB·함수 리전이 모두 asia-northeast3라 리전을 맞춘다.
 */
function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

/**
 * Apple `/auth/token`·`/auth/revoke` 호출에 쓰는 client_secret(ES256 JWT)을
 * .p8(EC P-256 개인키)로 서명해 만든다. JWT 라이브러리 없이 Node crypto로
 * 직접 만든다 — ES256 JWT 서명은 JOSE 형식(R‖S)이라야 하므로 dsaEncoding을
 * ieee-p1363으로 준다(기본 DER은 JWT에서 거부된다).
 */
function makeAppleClientSecret(privateKeyP8: string): string {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({alg: "ES256", kid: APPLE_KEY_ID}));
  const payload = base64url(
    JSON.stringify({
      iss: APPLE_TEAM_ID,
      iat: now,
      exp: now + 300,
      aud: "https://appleid.apple.com",
      sub: APPLE_CLIENT_ID,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signature = cryptoSign("sha256", Buffer.from(signingInput), {
    key: privateKeyP8,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${base64url(signature)}`;
}

/** authorization_code를 refresh_token으로 교환한다. 실패 시 null. */
async function exchangeAppleAuthCode(
  code: string,
  privateKeyP8: string,
): Promise<string | null> {
  const body = new URLSearchParams({
    client_id: APPLE_CLIENT_ID,
    client_secret: makeAppleClientSecret(privateKeyP8),
    code,
    grant_type: "authorization_code",
  });
  const res = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: {"content-type": "application/x-www-form-urlencoded"},
    body: body.toString(),
  });
  if (!res.ok) {
    const t = await res.text().catch(() => "");
    logger.warn("Apple 토큰 교환 실패", {status: res.status, body: t.slice(0, 300)});
    return null;
  }
  const json = (await res.json()) as {refresh_token?: string};
  return json.refresh_token ?? null;
}

/** refresh_token을 Apple에 폐기 요청한다. 실패해도 예외를 던지지 않는다. */
async function revokeAppleRefreshToken(
  refreshToken: string,
  privateKeyP8: string,
): Promise<boolean> {
  const body = new URLSearchParams({
    client_id: APPLE_CLIENT_ID,
    client_secret: makeAppleClientSecret(privateKeyP8),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  const res = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: {"content-type": "application/x-www-form-urlencoded"},
    body: body.toString(),
  });
  if (!res.ok) {
    const t = await res.text().catch(() => "");
    logger.warn("Apple 토큰 폐기 실패", {status: res.status, body: t.slice(0, 300)});
    return false;
  }
  return true;
}

interface StoreAppleRefreshTokenRequest {
  authorizationCode: string;
}

/**
 * Apple 로그인 시 클라이언트가 받은 authorization_code를 보내면, 서버가
 * refresh_token으로 교환해 `appleAuth/{uid}`에 보관한다. 회원 탈퇴 시
 * onUserDeletedCleanup이 이 토큰을 Apple에 폐기 요청한다(App Store 가이드라인
 * 요구, P1-38). refresh_token은 민감하므로 클라이언트가 못 읽는 컬렉션에 둔다
 * (규칙 read/write false, 서버 Admin SDK만 접근).
 *
 * 교환이 실패해도 로그인 자체는 이미 됐으므로 조용히 넘어간다(다음 로그인
 * 재시도). authorization_code는 발급 후 5분 안에 교환해야 하므로 로그인 직후
 * 호출하는 것을 전제로 한다.
 */
export const storeAppleRefreshToken = onCall<StoreAppleRefreshTokenRequest>(
  {
    secrets: [appleSignInKey],
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
  },
  async (request): Promise<{stored: boolean}> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 후 이용할 수 있어요.");
    }
    const code = (request.data?.authorizationCode ?? "").trim();
    if (!code) {
      throw new HttpsError("invalid-argument", "authorization code가 필요해요.");
    }
    const refreshToken = await exchangeAppleAuthCode(
      code,
      appleSignInKey.value(),
    );
    if (!refreshToken) return {stored: false};

    const db = getFirestore();
    await db.collection("appleAuth").doc(request.auth.uid).set({
      refreshToken,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {stored: true};
  },
);

export const onUserDeletedCleanup = onDocumentDeleted(
  {
    document: "users/{uid}",
    region: "asia-northeast3",
    secrets: [appleSignInKey],
  },
  async (event) => {
    const uid = event.params.uid;
    const db = getFirestore();

    // Apple 로그인 사용자라면 보관해 둔 refresh_token을 Apple에 폐기 요청한다
    // (App Store 요구, P1-38). 실패해도 나머지 정리는 계속한다.
    try {
      const appleRef = db.collection("appleAuth").doc(uid);
      const appleSnap = await appleRef.get();
      const refreshToken = appleSnap.data()?.refreshToken as string | undefined;
      if (refreshToken) {
        await revokeAppleRefreshToken(refreshToken, appleSignInKey.value());
      }
      if (appleSnap.exists) await appleRef.delete();
    } catch (e) {
      logger.warn("Apple 토큰 폐기/정리 실패", {errorType: (e as Error)?.name});
    }

    // AI 호출 감사 로그 삭제(추가 112).
    const snap = await db
      .collection("aiAuditLogs")
      .where("uid", "==", uid)
      .get();
    if (!snap.empty) {
      for (const batchDocs of chunkArray(snap.docs, 400)) {
        const batch = db.batch();
        batchDocs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    }

    // 1:1 문의·답변 삭제(ADMIN-VULN-007). 쿼리 기반 삭제라 자연히 멱등이다 —
    // 재실행해도(트리거가 중복 발화하거나 재시도되어도) 이미 지워진 뒤라면
    // 쿼리 결과가 비어 그냥 끝난다. 이메일·제목·본문 등 개인정보 원문은
    // 절대 로그에 남기지 않고 개수만 남긴다(CLAUDE.md 개인정보 원칙).
    const inquiriesSnap = await db
      .collection("inquiries")
      .where("userId", "==", uid)
      .get();
    let replyCount = 0;
    for (const inquiryDoc of inquiriesSnap.docs) {
      const repliesSnap = await inquiryDoc.ref.collection("replies").get();
      replyCount += repliesSnap.docs.length;
      for (const batchDocs of chunkArray(repliesSnap.docs, 400)) {
        const batch = db.batch();
        batchDocs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
    }
    for (const batchDocs of chunkArray(inquiriesSnap.docs, 400)) {
      const batch = db.batch();
      batchDocs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
    if (inquiriesSnap.docs.length > 0) {
      logger.info("탈퇴 사용자 문의 삭제", {
        uid,
        inquiryCount: inquiriesSnap.docs.length,
        replyCount,
      });
    }
  },
);

interface GetUserUsageRequest {
  email: string;
}

interface GetUserUsageResponse {
  uid: string;
  email: string | null;
  dailyCount: number;
  dailyLimit: number;
  monthlyCount: number;
  monthlyLimit: number;
  dailyResetAt: string | null;
  monthlyResetAt: string | null;
  bonusCredits: number;
}

/**
 * 관리자 콘솔용 — 이메일로 사용자의 AI 사용량을 조회한다. 관리자만 호출할 수
 * 있고, 반환하는 것은 사용량 카운터뿐이다(암호화 키·프로필·명함은 절대 반환
 * 안 함). users/{uid} 문서엔 민감정보가 함께 있어 Firestore 규칙으로 관리자에게
 * 통째로 열 수 없으므로, 이 함수가 Admin SDK로 필요한 필드만 뽑아 준다.
 */
export const getUserUsage = onCall<GetUserUsageRequest>(
  {region: "asia-northeast3", maxInstances: MAX_INSTANCES},
  async (request): Promise<GetUserUsageResponse> => {
    if (!isAdminRequest(request.auth)) {
      throw new HttpsError("permission-denied", "관리자만 조회할 수 있어요.");
    }
    const email = (request.data?.email ?? "").trim().toLowerCase();
    if (!email) {
      throw new HttpsError("invalid-argument", "이메일을 입력해 주세요.");
    }

    let userRecord;
    try {
      userRecord = await getAuth().getUserByEmail(email);
    } catch {
      throw new HttpsError("not-found", "그 이메일의 계정을 찾을 수 없어요.");
    }

    const db = getFirestore();
    const snap = await db.collection("users").doc(userRecord.uid).get();
    const usage = (snap.data()?.aiUsage ?? {}) as {
      dailyCount?: number;
      dailyResetAt?: FirebaseFirestore.Timestamp;
      monthlyCount?: number;
      monthlyResetAt?: FirebaseFirestore.Timestamp;
      bonusCredits?: number;
    };

    // 리셋 시각이 지났으면 카운트는 사실상 0이다(다음 호출 때 초기화됨).
    const now = Date.now();
    const dailyReset = usage.dailyResetAt?.toDate() ?? null;
    const monthlyReset = usage.monthlyResetAt?.toDate() ?? null;
    const dailyExpired = !dailyReset || dailyReset.getTime() <= now;
    const monthlyExpired = !monthlyReset || monthlyReset.getTime() <= now;

    return {
      uid: userRecord.uid,
      email: userRecord.email ?? null,
      dailyCount: dailyExpired ? 0 : (usage.dailyCount ?? 0),
      dailyLimit: DAILY_LIMIT,
      monthlyCount: monthlyExpired ? 0 : (usage.monthlyCount ?? 0),
      monthlyLimit: MONTHLY_LIMIT,
      dailyResetAt: dailyReset ? dailyReset.toISOString() : null,
      monthlyResetAt: monthlyReset ? monthlyReset.toISOString() : null,
      bonusCredits: usage.bonusCredits ?? 0,
    };
  }
);

interface GrantBonusCreditsRequest {
  email: string;
  amount: number;
  // 지급 사유 — 나중에 "왜 줬는지" 감사할 수 있어야 한다(ADMIN-VULN-002·010).
  // 사유 원문은 감사 문서(creditGrantAudits)에만 남고 Cloud Logging에는
  // 남기지 않는다(아래 logger.info 참고 — 자유서술 텍스트를 로그에 남기지
  // 않는다는 CLAUDE.md 원칙).
  reason: string;
  // 재시도/중복 클릭을 구분하는 멱등성 키. 클라이언트(admin.js)가 지급
  // 버튼을 누른 그 자리에서 crypto.randomUUID()로 1회 생성해 보낸다.
  operationId: string;
}

/**
 * 관리자 콘솔용 — 특정 사용자에게 무료 회차(bonusCredits)를 추가 지급한다.
 * 관리자만 호출할 수 있고, 회차는 곧 비용이라 **클라이언트가 직접 못 쓰게**
 * 서버(Admin SDK)에서만 올린다(Firestore 규칙은 aiUsage 쓰기를 막고 있다).
 *
 * bonusCredits는 일/월 한도를 다 쓴 뒤 소진되는 오버플로우다(generateBriefing
 * 참고). 지급 즉시 반영되며, 앞으로 충전(IAP) 크레딧도 같은 필드로 얹을 수 있다.
 *
 * 2026-08-14(ADMIN-VULN-002) 안전장치 추가:
 * - 금액 검증(상한·안전정수)은 순수 함수 `validateGrantAmount`로 분리해
 *   Firestore 없이 `node --test`로 경계값을 검증한다(creditGrant.ts).
 * - `operationId`로 멱등성을 보장한다 — 같은 operationId가 이미
 *   `creditGrantAudits/{operationId}`에 기록돼 있으면 재적용하지 않고 그때
 *   결과 잔액을 그대로 반환한다(재시도·중복 클릭 방어).
 * - 모든 지급에 행위자(actorEmail/actorUid)·사유·변경 전후 잔액을
 *   `creditGrantAudits`에 트랜잭션으로 함께 기록한다(클라이언트는 그 컬렉션에
 *   쓸 수 없다 — firestore.rules 참고).
 */
export const grantBonusCredits = onCall<GrantBonusCreditsRequest>(
  {region: "asia-northeast3", maxInstances: MAX_INSTANCES},
  async (request): Promise<{uid: string; bonusCredits: number}> => {
    if (!isAdminRequest(request.auth)) {
      throw new HttpsError("permission-denied", "관리자만 지급할 수 있어요.");
    }
    // isAdminRequest가 true를 반환했다는 것은 request.auth와
    // request.auth.token.email이 이미 검증됐다는 뜻이다(non-null assertion은
    // 그 사실에 근거한다 — TS는 isAdminRequest를 타입가드로 인식하지 못한다).
    const auth = request.auth!;
    const actorUid = auth.uid;
    const actorEmail = auth.token.email as string;

    const email = (request.data?.email ?? "").trim().toLowerCase();
    if (!email) {
      throw new HttpsError("invalid-argument", "이메일을 입력해 주세요.");
    }

    const metaCheck = validateGrantMetadata(
      request.data?.reason,
      request.data?.operationId,
    );
    if (!metaCheck.ok) {
      throw new HttpsError("invalid-argument", metaCheck.error);
    }
    const reason = (request.data.reason as string).trim();
    const operationId = (request.data.operationId as string).trim();
    const rawAmount = request.data?.amount;

    let userRecord;
    try {
      userRecord = await getAuth().getUserByEmail(email);
    } catch {
      throw new HttpsError("not-found", "그 이메일의 계정을 찾을 수 없어요.");
    }

    const db = getFirestore();
    const userRef = db.collection("users").doc(userRecord.uid);
    const auditRef = db.collection("creditGrantAudits").doc(operationId);

    const newBalance = await db.runTransaction(async (tx) => {
      // 멱등성 확인 — Firestore 트랜잭션 규칙상 모든 get()은 write보다
      // 먼저여야 하므로 감사 문서를 가장 먼저 읽는다. 이미 있으면 같은
      // operationId로 재시도/중복 클릭된 것이니 다시 적용하지 않고 그때
      // 기록해 둔 결과 잔액을 그대로 돌려준다.
      const auditSnap = await tx.get(auditRef);
      if (auditSnap.exists) {
        const existing = auditSnap.data() as {after?: number};
        return existing.after ?? 0;
      }

      const userSnap = await tx.get(userRef);
      const current = (userSnap.data()?.aiUsage?.bonusCredits as number | undefined) ?? 0;

      const check = validateGrantAmount(rawAmount, current);
      if (!check.ok) {
        throw new HttpsError("invalid-argument", check.error);
      }

      // 음수 지급(회수)도 허용하되 0 밑으로는 안 내려가게 막는다(기존 동작
      // 유지). validateGrantAmount는 "상한을 넘지 않는지"만 보고, 0 미만
      // 클램프는 이 트랜잭션의 책임이다.
      const next = Math.max(0, current + check.amount);
      tx.set(userRef, {aiUsage: {bonusCredits: next}}, {merge: true});
      tx.set(auditRef, {
        actorUid,
        actorEmail,
        targetUid: userRecord.uid,
        targetEmail: userRecord.email ?? email,
        amount: check.amount,
        reason,
        before: current,
        after: next,
        at: FieldValue.serverTimestamp(),
      });
      return next;
    });

    // ⚠️ reason(자유서술 텍스트) 원문은 Cloud Logging에 남기지 않는다 —
    // 완전한 기록은 creditGrantAudits(Firestore, 관리자만 읽음)에 있다.
    logger.info("무료 회차 지급", {
      actorUid,
      actorEmail,
      targetUid: userRecord.uid,
      amount: rawAmount,
      newBalance,
      operationId,
    });
    return {uid: userRecord.uid, bonusCredits: newBalance};
  }
);
