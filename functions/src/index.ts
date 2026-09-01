/**
 * 커넥션센스 AI 브리핑 서버 프록시.
 *
 * BYOK(사용자가 직접 AI API 키 발급)가 비개발자에게 진입장벽이 너무 높다는
 * 피드백에 따라, 서버(이 함수)가 앱 운영사 소유의 Gemini 호출 권한으로 대신
 * 호출하는 구조로 전환했다. 설계 근거·비용 추정·리스크는
 * docs/planning/server-setup-plan.md 14번 섹션, 실제 적용 결정은
 * docs/planning/backlog.md 추가 68 참고.
 *
 * 배포 전제조건: Firebase 프로젝트가 Blaze(종량제) 요금제여야 한다(Cloud
 * Functions는 Spark 요금제에서 아예 실행되지 않음). 2026-08-07 Blaze 전환 후
 * asia-northeast3에 배포 완료됐다.
 *
 * ⚠️ 2026-08-31: Gemini 호출 경로를 Google AI Studio(Developer API,
 * generativelanguage.googleapis.com, API 키 인증)에서 Vertex AI(서비스 계정
 * 인증, us 관할권 멀티리전)로 옮겼다. 이유·조사 경위는
 * docs/planning/vertex-seoul-region-research-2026-08-24.md 참고 — 서울 리전
 * (asia-northeast3)은 유일하게 쓸 수 있던 최신 모델(gemini-2.5-flash)이
 * 2026-10-20 은퇴 예정이고 후속 3.x 세대 모델이 아예 배치되지 않아 포기했고,
 * 대신 Gemini 3 세대부터 제공되는 us/eu 관할권 멀티리전(서울만큼 좁지는
 * 않지만 지금까지의 "글로벌, 리전 통제 없음"보다는 훨씬 좁혀진 상태)으로
 * 갔다. 모델은 gemini-3.6-flash 그대로 유지한다(아래 GEMINI_MODEL 참고) —
 * 프롬프트·thinkingLevel·생성 파라미터가 전부 이 모델 기준으로 실측·조정된
 * 상태라 모델을 내리면(2.5-flash) 그 튜닝을 다시 검증해야 하고, 게다가
 * 2.5-flash는 곧 은퇴한다.
 *
 * 반드시 지킬 것(카드 등록 후 실제 배포 전 재확인):
 * - Vertex AI 호출은 서비스 계정(ADC, Application Default Credentials)으로만
 *   인증한다 — Cloud Functions 런타임이 자동으로 서비스 계정 자격증명을
 *   주입하므로 별도 키 파일 관리가 필요 없다. API 키(Express mode)로 부르면
 *   글로벌 엔드포인트로 빠져 리전 보장이 사라진다 — 이번 이전의 전제 자체가
 *   깨진다(아래 getVertexAccessToken 참고). 학습 미사용 정책은 Vertex AI
 *   쪽이 유·무료 등급 구분 없이 적용된다(옛 Developer API 무료 등급처럼
 *   입력을 사람이 검수·모델 개선에 활용하는 위험이 없다).
 * - 원문 프롬프트/응답을 로그(console.log)에 남기지 않는다 — Cloud Logging은
 *   기본 30일 보관되므로 그대로 찍으면 의도치 않은 개인정보 장기 보관이 된다.
 * - 대화 내용 자체는 Firestore 등에 영구 저장하지 않는다. 호출량 카운터만
 *   남긴다(아래 incrementAndCheckUsage).
 */

import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";
import {
  onDocumentCreated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import {sign as cryptoSign} from "crypto";
import {defineSecret} from "firebase-functions/params";
import {GoogleAuth} from "google-auth-library";
import * as logger from "firebase-functions/logger";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getStorage} from "firebase-admin/storage";
import {nextKstMidnight, nextKstMonthStart} from "./usageReset";
import {ADMIN_EMAILS} from "./adminEmails";
import {validateGrantAmount, validateGrantMetadata} from "./creditGrant";
import {chunkArray} from "./chunk";
import {
  buildPrompt,
  resolveFieldLabel,
  GenerateBriefingRequest,
} from "./briefingPrompt";
import {
  SOCIAL_UNLINK_REQUESTS,
  adminKeyMatches,
  appIdAllowed,
  parseKakaoUnlinkPayload,
} from "./kakaoUnlink";
import {
  BillingModel,
  WalletExhaustedError,
  consumeWalletCredit,
  resolveBillingModel,
} from "./walletCredits";
import {DEFAULT_FREE_CREDITS, planFreeGrant} from "./freeGrant";
import {
  kstIsoWeekCohort,
  planActivation,
} from "./pilotEvents";
import {generateReferralCode} from "./referralCode";
import {canGrantTrialToDevice, deviceHash} from "./deviceLedger";
import {
  Challenge,
  OTP_MAX_ATTEMPTS,
  SEND_LEDGER_RETENTION_MS,
  SendLedger,
  TEST_PHONE_FIXED_CODE,
  decideSend,
  generateOtpCode,
  isTestPhone,
  normalizePhoneKr,
  otpCodeHash,
  parseTestNumbers,
  phoneHash,
  verifyOtp,
} from "./phoneOtp";
import {
  AligoSender,
  NoKeySender,
  OtpSender,
} from "./phoneOtpSender";
import {
  BillingTierRaw,
  isNonEmptyString,
  isValidIapPlatform,
  isValidTransactionId,
  resolveTierByProductId,
} from "./purchases";
import {deleteUserCardPhotos} from "./cardPhotoCleanup";
import {deleteTombstones} from "./tombstoneCleanup";
import {deletePhoneRecords} from "./phoneRecordCleanup";
import {
  firebaseUserFields,
  isTesterAllowed,
  parseKakaoUser,
  parseNaverUser,
  tokenClaims,
  tokenEndpoint,
  tokenExchangeBody,
  parseTokenResponse,
  socialUid,
  validateRequest,
  type SocialProfile,
} from "./socialAuth";

initializeApp();

// Sign in with Apple 토큰 폐기(P1-38)에 쓰는 Apple 개인키(.p8) 원문.
// `firebase functions:secrets:set APPLE_SIGNIN_KEY`로 .p8 파일 내용을 넣는다
// (-----BEGIN PRIVATE KEY----- 부터 END 까지 통째로). 이 비밀이 없으면 아래
// 두 함수는 배포되지 않는다.
const appleSignInKey = defineSecret("APPLE_SIGNIN_KEY");

// 기기 지문(raw device id) 해시용 salt(U5, 재가입×무료체험 무한 루프 방어).
// `firebase functions:secrets:set DEVICE_HASH_SALT`로 실제 값을 넣는다 —
// 이 값이 없어도(로컬 빌드·아직 시크릿 미설정) `npm run build`(tsc)는
// 통과한다. `deviceHashSalt.value()`를 실제로 호출하는 시점(배포된 함수가
// deviceId를 받은 요청을 처리할 때)에만 시크릿이 필요하다. 설계 근거:
// docs/planning/monetization-referral-engineering-spec-2026-08-14.md §4-2.
const deviceHashSalt = defineSecret("DEVICE_HASH_SALT");

// 휴대전화번호·인증번호 해시용 salt(추가 565).
//
// 🚨 **한번 정해 데이터가 쌓이면 사실상 못 바꾼다** — 바꾸면 phoneAccounts의
// 매핑이 전부 안 맞는다(추가 462가 CI/DI에서 지적한 것과 같은 구조).
// `firebase functions:secrets:set PHONE_HASH_SALT`로 넣는다. deviceHashSalt와
// 같이 선언 시점엔 값이 필요 없고 `.value()` 호출 시점에만 필요하다.
const phoneHashSalt = defineSecret("PHONE_HASH_SALT");

// 알리고(알림톡 발송사) 키 넷. ⚠️ **아직 하나도 없다.**
//
// 📌 값이 없어도 빌드·배포가 되고, 없으면 `NoKeySender`가 골라져 **테스트
// 번호 경로만 동작한다**(`pickSender` 참고). 키가 오면 값만 넣으면 된다.
const aligoApiKey = defineSecret("ALIGO_API_KEY");
const aligoUserId = defineSecret("ALIGO_USER_ID");
const aligoSenderKey = defineSecret("ALIGO_SENDER_KEY");
const aligoTplCode = defineSecret("ALIGO_TPL_CODE");
const aligoSender = defineSecret("ALIGO_SENDER");

// 🚨 **테스트 번호 목록. 기본값은 「없음」이다.**
//
// 이 값이 비면 `isTestPhone`이 항상 false를 주고 테스트 경로가 죽는다 —
// *"설정이 없으면 전부 실제 발송"*이 기본이어야, 설정을 깜빡한 것이
// **기능이 열린 채로 나가는 것**이 되지 않는다.
//
// ⚠️ **이 목록이 운영에 남으면 그 번호로 누구나 로그인한다.** 릴리스
// 점검표에 확인 줄이 있다(docs/planning/release-checklist.md).
const phoneTestNumbers = defineSecret("PHONE_TEST_NUMBERS");

// 알리고 testMode. "Y"면 알리고까지 왕복하되 실제 발송을 안 한다.
const aligoTestMode = defineSecret("ALIGO_TEST_MODE");

// IAP(인앱결제) 영수증 검증용 시크릿 2개(U7, 뼈대만). **값은 아직 설정하지
// 않는다** — 스토어 상품ID가 아직 등록되지 않았고(사용자 게이트, P1-1)
// 실제 검증 로직도 이번 라운드엔 없다(`verifyAndGrantPurchase` 참고). 값이
// 없어도 `npm run build`(tsc)는 통과한다 — `defineSecret`는 선언 시점엔
// 값을 요구하지 않고, `.value()`를 실제로 호출하는 시점(배포된 함수가
// 검증 요청을 처리할 때)에만 필요하다. 설계 근거:
// docs/planning/monetization-referral-engineering-spec-2026-08-14.md §2-1.
//
// - APPLE_IAP_SHARED_SECRET: App Store Connect의 "앱 전용 공유 비밀"
//   (legacy verifyReceipt) 또는 향후 App Store Server API 키로 대체될 수
//   있다 — 실제 검증 로직을 채울 때 어느 쪽을 쓸지 그때 결정한다.
// - GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: Google Play Developer API 호출용
//   서비스 계정 JSON 원문.
const appleIapSharedSecret = defineSecret("APPLE_IAP_SHARED_SECRET");

// 카카오·네이버 로그인용. 인가 코드를 액세스 토큰으로 바꿀 때 쓴다.
//
// ⚠️ **앱에 넣을 수 없는 값이라 서버가 들고 있다.** 특히 네이버
// client_secret은 필수이고, 앱을 뜯으면 나오는 자리에 두면 남의 계정으로
// 토큰을 받아갈 수 있다.
//
// 📌 카카오는 콘솔에서 client_secret을 **끈 상태(기본값)** 를 전제로 한다.
// 켜면 교환 요청에 함께 보내야 하므로 여기에 하나 더 만들어야 한다.
const kakaoRestKey = defineSecret("KAKAO_REST_KEY");

// 카카오 **대표 어드민 키**. 연결 해제 웹훅의 진위를 가리는 데만 쓴다 —
// 카카오가 이 값을 `Authorization: KakaoAK ...`에 담아 보낸다.
//
// ⚠️ 이 시크릿이 **없으면 웹훅은 아무것도 통과시키지 않는다**(adminKeyMatches가
// 빈 기대값을 항상 거짓으로 본다). 검증이 무력해진 채 열려 있는 것보다
// 안 받는 쪽이 안전하기 때문이다.
const kakaoAdminKey = defineSecret("KAKAO_ADMIN_KEY");
const kakaoClientSecret = defineSecret("KAKAO_CLIENT_SECRET");
const naverClientId = defineSecret("NAVER_CLIENT_ID");
const naverClientSecret = defineSecret("NAVER_CLIENT_SECRET");
const googlePlayServiceAccountJson = defineSecret(
  "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"
);
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
// 하므로, 모델이 마음껏 생각하면 이 천장까지 요금이 오를 수 있다 — 2026-08-08
// 실측에서 사고 토큰이 회당 1,275~1,328개로 과금 출력의 91%를 차지했다.
// 그래서 천장을 낮추는 대신 아래 THINKING_LEVEL로 사고량 자체를 줄였고, 그
// 뒤 실측은 사고 0~590 / 출력 97~108이다. 천장을 3000으로 남겨 두는 이유는
// 2026-08-07의 응답 잘림 버그 재발 방지다.
//
// 단가(2026-08-31 ai.google.dev/gemini-api/docs/pricing +
// docs.cloud.google.com/vertex-ai/generative-ai/pricing 양쪽 직접 확인,
// gemini-3.6-flash 입력/출력): **$0.75 / $3.75 (2026-12-31까지 프로모션가)**,
// **$1.50 / $7.50 (2027-01-01부터 정가)**. Vertex AI도 Developer API와 같은
// 값이다 — us 관할권 멀티리전이라고 더 비싼 "리전 프리미엄"은 없다(가격표에
// 리전 구분 열 자체가 없음).
const MAX_OUTPUT_TOKENS = 3000;

const GEMINI_MODEL = "gemini-3.6-flash";

// Vertex AI 관할권 멀티리전. us 또는 eu만 유효하고(LOCATION을 그대로 씀),
// "global"은 절대 쓰면 안 된다 — 글로벌 엔드포인트는 리전 보장이 없어져
// 이번 이전의 전제 자체가 깨진다. 서울(asia-northeast3)을 포기한 이유는 위
// 파일 상단 주석 참고.
//
// ⚠️ 호스트 형식에 주의 — 두 형식이 있고 서로 다른 용도다. 헷갈려서 실제로
// 한 번 틀렸다(2026-08-31, PR #747 이후 발견·후속 수정).
//
//   지역(locational) 엔드포인트:
//     ${LOCATION}-aiplatform.googleapis.com
//     (예: asia-northeast3-aiplatform.googleapis.com,
//          us-central1-aiplatform.googleapis.com)
//   관할권 멀티리전(jurisdictional multi-region) 엔드포인트:
//     aiplatform.${LOCATION}.rep.googleapis.com
//     (us/eu 둘뿐 — 우리가 쓰는 것은 이쪽이다. 아래 requestGemini() 참고.
//      Google 공식 문서가 "Explicitly use the .rep. hostname for
//      multi-region endpoints"라고 명시한다.)
//
// 이 둘을 혼동해 지역 엔드포인트 형식(${LOCATION}-aiplatform.googleapis.com)
// 으로 조립하면 us라는 값 자체는 유효해 보여도 존재하지 않는 호스트
// (us-aiplatform.googleapis.com)로 요청이 나가 AI 브리핑이 통째로 실패한다.
// 원래 서울(asia-northeast3) 리전행을 전제로 지역 엔드포인트 형식을 쓴
// 문서 절(vertex-seoul-region-research-2026-08-24.md 6-2절)이 있었는데,
// 리전 결정이 us 멀티리전으로 바뀐 뒤에도 코드가 그 절을 그대로 참조해
// 생긴 실수다 — 자동 검사(빌드·테스트)는 URL 문자열의 존재 여부를 검증하지
// 않아 전부 통과했고, Google 문서 원문을 사람이 다시 대조해서만 잡혔다.
const VERTEX_LOCATION = "us";

// Firebase 프로젝트 ID. `.firebaserc`의 projects.default와 동일한 값을
// 하드코딩한다(이 파일의 APPLE_TEAM_ID 등과 같은 스타일) — Cloud Functions
// v2가 자동 주입하는 런타임 환경변수(GCLOUD_PROJECT 등)에 기대는 대신,
// URL 조립에 필요한 값을 코드에서 바로 보이게 둔다.
const PROJECT_ID = "connection-sense";

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

interface GenerateBriefingResponse {
  talkingPoints: string[];
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

// Vertex AI 인증 클라이언트. 모듈 스코프에 한 번만 만들어 warm start 사이에
// 재사용한다 — 매 호출 새로 만들면 콜드스타트마다 인증 왕복(discovery +
// 토큰 발급)이 추가된다.
const vertexAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"],
});

/**
 * ADC(Application Default Credentials)로 Vertex AI 액세스 토큰을 가져온다.
 * Cloud Functions 런타임이 자동으로 서비스 계정 자격증명을 주입하므로 키
 * 파일을 따로 관리할 필요가 없다 — 단, 배포 전 그 서비스 계정에
 * `roles/aiplatform.user`(또는 그에 준하는 IAM 역할)가 부여돼 있어야 한다
 * (사용자 콘솔 작업, 이 함수가 대신할 수 없음).
 */
async function getVertexAccessToken(): Promise<string> {
  const client = await vertexAuth.getClient();
  const {token} = await client.getAccessToken();
  if (!token) {
    throw new Error("Vertex AI 액세스 토큰을 가져오지 못했습니다.");
  }
  return token;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// 429(혼잡) 재시도 전 고정 지연. 800~1200ms 범위에서 900ms로 정했다 — 근거는
// 아래 callGemini 주석.
const RETRY_DELAY_MS = 900;

/**
 * Gemini에 한 번 요청한다. [withThinkingLevel]이 false면 thinkingLevel을
 * 아예 빼고 보낸다(아래 fallback 용도).
 */
async function requestGemini(
  prompt: string,
  accessToken: string,
  withThinkingLevel: boolean
): Promise<Response> {
  const url = `https://aiplatform.${VERTEX_LOCATION}.rep.googleapis.com/v1/projects/${PROJECT_ID}/locations/${VERTEX_LOCATION}/publishers/google/models/${GEMINI_MODEL}:generateContent`;
  return fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${accessToken}`,
    },
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
  accessToken: string,
): Promise<{text: string; usage: GeminiUsage}> {
  let usedThinkingLevel = true;
  let response = await requestGemini(prompt, accessToken, true);

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
    response = await requestGemini(prompt, accessToken, false);
  }

  // 429(혼잡) 재시도. 2026-08-31 이전까지는 이 재시도가 아예 없었다 — 400만
  // 재시도하고 그 외 실패(429 포함)는 바로 unavailable로 던졌다. us
  // 멀티리전에서도 순간 혼잡이 없다는 보장은 없어 최소한의 안전장치를 둔다.
  //
  // **왜 지수 백오프나 여러 번이 아니라 "짧은 고정 지연 1회"인가**: 이 호출은
  // 사용자가 화면에서 동기로 기다리는 채팅 UI다. Cloud Functions 타임아웃과
  // 체감 지연을 함께 고려하면, 재시도를 늘릴수록 "느리게 성공"과 "빠르게
  // 실패해 다시 눌러보게" 사이에서 전자 쪽으로 계속 밀리게 된다. 순간
  // 혼잡이면 1회·짧은 지연으로 대부분 풀리고, 지속적인 쿼터 초과라면 여러
  // 번 재시도해도 어차피 실패한다 — 그 경우는 지금처럼 즉시 에러로 알리는
  // 편이 사용자에게 "잠시 후 다시 시도"를 더 빨리 안내한다.
  if (response.status === 429) {
    logger.warn("Gemini 429(혼잡) — 지연 후 1회만 재시도", {
      delayMs: RETRY_DELAY_MS,
    });
    await delay(RETRY_DELAY_MS);
    response = await requestGemini(prompt, accessToken, usedThinkingLevel);
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
 * 소셜 로그인 이용자의 **제공자 이메일**을 서버에만 보관하는 자리.
 *
 * ⚠️ **테스트 기간 한정 임시 조치다.** 아래 [testerEmailFallback] 하나에만
 * 쓰이고, 그 대조 자체가 `config/testers` 와 함께 테스트 종료 시 사라진다.
 */
const SOCIAL_EMAIL_COLLECTION = "socialTesterEmails";

/**
 * 테스터 허용목록 검사. 스토어를 거치지 않은 빌드는 App Check 토큰을 못 만들어
 * AI 호출이 막힌다. 관리자 콘솔에서 `config/testers.emails`에 등록한 이메일은
 * 테스트 기간 동안 App Check 없이도 허용한다. Admin SDK로 읽어 보안 규칙을
 * 우회한다. 대소문자 차이로 빠지지 않도록 소문자로 비교한다.
 *
 * ## ⚠️ 카카오·네이버는 토큰에 이메일이 없을 수 있다 (2026-08-21 실기기에서 확인)
 *
 * 같은 이메일이 이미 다른 계정(구글·애플)에 쓰이고 있으면 Firebase 가 중복을
 * 거부한다. 그래서 `socialSignIn` 은 **이메일만 빼고** 계정을 만든다 — 로그인은
 * 되지만 `request.auth.token.email` 이 비어 버린다.
 *
 * ```
 * 관리자 콘솔에 이메일을 등록해도 통하지 않는다 — 대조할 값 자체가 없다
 * → 카카오·네이버로 가입한 테스터는 AI 를 한 번도 못 쓴다
 * ```
 *
 * 그래서 토큰에 이메일이 없을 때만 **서버에 따로 적어 둔 제공자 이메일**로
 * 한 번 더 본다(사용자 결정, B안).
 *
 * ⚠️ **클라이언트가 읽는 토큰·claims 에는 넣지 않는다.** claims 는 앱이 그대로
 * 디코드해 읽을 수 있어, 거기 넣으면 개인정보를 클라이언트에 흘리는 셈이다.
 */
async function isAllowlistedTester(
  email: string | undefined | null,
  uid?: string,
): Promise<boolean> {
  const db = getFirestore();
  const snap = await db.collection("config").doc("testers").get();
  if (!snap.exists) return false;
  const emails = (snap.data()?.emails ?? []) as string[];
  if (emails.length === 0) return false;

  // 판정 자체는 순수 함수에 있다(socialAuth.ts). 조회가 필요한지도 그쪽
  // 규칙에 맞춘다 — 토큰에 이메일이 있으면 서버 기록을 아예 보지 않는다.
  if (isTesterAllowed({allowlist: emails, tokenEmail: email})) return true;
  if ((email ?? "").trim() || !uid) return false;

  return isTesterAllowed({
    allowlist: emails,
    tokenEmail: null,
    storedEmail: await lookupSocialTesterEmail(uid),
  });
}

/** 서버에만 적어 둔 제공자 이메일을 읽는다. 없으면 `null`. */
async function lookupSocialTesterEmail(uid: string): Promise<string | null> {
  try {
    const doc = await getFirestore()
      .collection(SOCIAL_EMAIL_COLLECTION)
      .doc(uid)
      .get();
    return (doc.data()?.email as string | undefined) ?? null;
  } catch (e) {
    // 못 읽으면 허용하지 않는다(fail-closed). 이 폴백은 **통과시키는**
    // 경로라, 조회 실패를 통과로 바꾸면 가드가 통째로 무의미해진다.
    logger.warn("소셜 테스터 이메일 조회 실패", {
      reason: (e as Error).message,
    });
    return null;
  }
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

/**
 * 파일럿 활성화 이벤트(명함 3장 이상 + AI 브리핑 1회 이상 사용) 판정·기록.
 *
 * `generateBriefing`이 이미 성공한 직후에만 부른다 — "지금 AI 사용이 1회
 * 이상 일어났다"는 사실을 서버가 아는 유일한 지점이 여기이기 때문이다. 남은
 * 조건(명함 3장 이상)은 이 함수가 `users/{uid}/contacts`를 Admin SDK
 * count() 집계로 직접 확인한다. 두 조건이 모두 충족된 시점(둘 중 나중에
 * 벌어진 사건 시점)에 한해 `users/{uid}.pilotActivatedAt`(멱등 가드)과
 * `pilotEvents/{uid}/events/{eventId}` 로그를 함께 남긴다.
 *
 * ⚠️ U2의 리퍼럴 활성화 조건("명함 1장 + AI 1회", 아직 미구현)과는 완전히
 * 별개인 독립 지표다 — 코드도 저장 위치도 공유하지 않는다.
 *
 * writeAiAuditLog와 같은 원칙: 절대 throw하지 않는다. 계측 실패가 AI
 * 응답을 막으면 안 된다.
 */
async function maybeRecordActivationEvent(uid: string): Promise<void> {
  try {
    const db = getFirestore();
    const userRef = db.collection("users").doc(uid);
    await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const alreadyActivated = userSnap.data()?.pilotActivatedAt != null;
      if (alreadyActivated) return; // 멱등 — count() 집계도 아낀다.

      const countSnap = await tx.get(userRef.collection("contacts").count());
      const contactCount = countSnap.data().count;

      const plan = planActivation({alreadyActivated, contactCount});
      if (!plan.shouldRecord) return;

      const at = FieldValue.serverTimestamp();
      tx.set(userRef, {pilotActivatedAt: at}, {merge: true});
      const eventRef = db
        .collection("pilotEvents")
        .doc(uid)
        .collection("events")
        .doc();
      tx.create(eventRef, {type: "activation", uid, at});
    });
  } catch (err) {
    logger.warn("파일럿 활성화 이벤트 기록 실패 — 무시하고 계속", {
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

export const generateBriefing = onCall<GenerateBriefingRequest>(
  {
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
        !(await isAllowlistedTester(
          request.auth.token.email,
          request.auth.uid,
        ))) {
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
        fieldKey,
      } = request.data;
      if (!contactSummary || !myProfileSummary) {
        throw new HttpsError(
          "invalid-argument",
          "필수 정보가 누락됐어요."
        );
      }

      // 분야 키가 왔는데 서버 목록(FIELD_LABELS)에 없으면 분야 없이 생성한다.
      // 통째로 실패시키는 것보다 낫지만 **조용히 넘어가면 안 된다** — 앱과
      // 서버의 목록이 어긋났을 때 아무도 모르고, 사용자에게는 "분야를 골랐는데
      // 안 먹는다"가 아니라 "AI가 원래 그런가 보다"로 읽힌다. 이 저장소는
      // "조용히 좁아지는 것이 상한 없는 것보다 나쁘다"로 같은 판단을 한 적이
      // 있다(추가 480). 키는 고정 목록의 영문 식별자라 개인정보가 아니므로
      // 그대로 남겨도 된다.
      if (fieldKey && !resolveFieldLabel(fieldKey)) {
        logger.warn("알 수 없는 분야 키 — 분야 없이 생성", {fieldKey});
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
        fieldKey,
      }, variationSeed);
      const accessToken = await getVertexAccessToken();
      const {text: rawText, usage} = await callGemini(
        prompt,
        accessToken,
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
      // 파일럿 활성화 판정은 AI 사용이 실제로 성공한 뒤에만 의미가 있다
      // (실패 호출은 "AI 1회 사용"으로 치지 않는다). 실패해도 응답에는
      // 영향 없음(위 함수 자체가 절대 throw하지 않음).
      await maybeRecordActivationEvent(uid);
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

interface BootstrapAccountRequest {
  // ⚠️ 이번 라운드(U2)는 시그니처만 열어 두고 처리하지 않는다 — 다른
  // 사람의 코드를 넣어 보너스를 받는 "redemption"은 다음 라운드(별도 승인
  // 필요) 몫이다. 받아도 무시한다(작업 지시서 명시).
  referralCodeInput?: string;
  // 재가입×무료체험 무한 루프 방어(U5, 스펙 §4)에 쓰는 raw device id.
  // 구버전 클라이언트나 기기 식별자를 못 얻은 경우(플랫폼 미지원 등)엔
  // 아예 안 보낼 수 있다 — 그 경우 기기 가드를 건너뛰고 지금처럼
  // 동작한다(아래 핸들러, 경고 로그만 남기고 절대 요청 자체를 막지 않음).
  deviceId?: string;
}

interface BootstrapAccountResponse {
  referralCode: string;
  /** 이번 호출에서 실제로 무료체험을 새로 지급했는지(디버그·관찰용). */
  freeGranted: boolean;
}

/**
 * 리퍼럴 코드 발급이 최대 재시도 후에도 실패했을 때 던지는 에러.
 * `referralCodes/{code}` 문서 생성 충돌이 5회 연속 나는 것은 현실적으로
 * 거의 발생하지 않는다(코드 공간이 32^6 ≈ 10억).
 */
const REFERRAL_CODE_MAX_ATTEMPTS = 5;

/**
 * 본인 리퍼럴 코드 발급 — 멱등(ai-credit-wallet-spec.md와 별개로,
 * monetization-referral-implementation-spec-2026-08-14.md §3-1 근거).
 *
 * `users/{uid}.referralCode`가 이미 있으면 그대로 반환. 없으면
 * `referralCode.ts`의 순수 생성기로 후보를 만들고, `referralCodes/{code}`
 * 문서를 `tx.create()`로 선점 시도한다 — 이미 다른 사용자가 같은 코드를
 * 선점했다면 Firestore가 그 트랜잭션을 충돌시켜 재시도하게 만든다(check
 * -then-act보다 안전, walletCredits.ts 스타일과 동일한 이유로 create를
 * 씀). 코드가 최대 시도 안에 안 정해지면(사실상 거의 안 일어남) 에러.
 */
async function ensureReferralCode(
  db: FirebaseFirestore.Firestore,
  uid: string
): Promise<string> {
  const userRef = db.collection("users").doc(uid);
  const existing = await userRef.get();
  const already = existing.data()?.referralCode as string | undefined;
  if (already) return already;

  for (let attempt = 0; attempt < REFERRAL_CODE_MAX_ATTEMPTS; attempt++) {
    const candidate = generateReferralCode();
    const codeRef = db.collection("referralCodes").doc(candidate);
    try {
      return await db.runTransaction(async (tx) => {
        // 재확인: 동시 호출(예: 로그인 이벤트가 겹침) 중 다른 트랜잭션이
        // 이 사이 이미 코드를 발급했을 수 있다 — 그러면 그 값을 그대로 쓴다.
        const userSnap = await tx.get(userRef);
        const alreadyRace = userSnap.data()?.referralCode as
          | string
          | undefined;
        if (alreadyRace) return alreadyRace;

        tx.create(codeRef, {uid});
        tx.set(userRef, {referralCode: candidate}, {merge: true});
        return candidate;
      });
    } catch (err) {
      // tx.create가 이미 존재하는 referralCodes 문서와 충돌하면 여기로
      // 온다(다른 uid가 먼저 그 코드를 선점) — 새 후보로 재시도한다.
      logger.warn("리퍼럴 코드 후보 충돌 — 재시도", {
        attempt,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
  throw new HttpsError(
    "internal",
    "리퍼럴 코드를 발급하지 못했어요. 잠시 후 다시 시도해 주세요."
  );
}

/**
 * 로그인 시 앱이 1회 호출하는 신규 콜러블 — (a) 무료체험 크레딧을 uid당
 * 1회만 지급하고(멱등) (b) 본인 리퍼럴 코드를 발급한다(멱등).
 *
 * **매 로그인마다 불려도 무해해야 한다** — 실제 지급/발급은 서버가 각각
 * `aiUsage.freeGrantedAt`/`users/{uid}.referralCode` 존재 여부로 멱등
 * 가드를 걸므로, 두 번째 호출부터는 아무 것도 쓰지 않고 기존 값만 반환한다.
 *
 * ⚠️ `grantSupportCredits`(관리자의 고객응대 무료 지급)와는 완전히 독립된
 * 트랜잭션이다 — 코드도 공유하지 않는다(다른 세션이 그 함수를 하드닝
 * 중이라 이번 작업 지시서가 명시적으로 분리를 요구함).
 *
 * **기기 가드(U5, 재가입×무료체험 무한 루프 방어)**: 클라이언트가
 * `deviceId`(raw device id)를 보내면 서버가 `deviceHash()`로 해시해
 * `deviceLedger/{hash}.trialGrantsIssued`를 확인한다. 이미 이 기기에
 * 무료체험을 지급한 적이 있으면(`canGrantTrialToDevice`가 false) 이번
 * uid의 무료체험은 0으로 지급한다 — 단, uid 스코프 멱등 가드
 * (`freeGrantedAt`)는 그대로 찍어서 재시도가 또 이 분기를 타지 않게 한다.
 * `deviceId`가 없는 요청(구버전 클라이언트, 식별자 못 얻음)은 기기 가드를
 * 완전히 건너뛰고 지금까지의 동작 그대로다 — 경고 로그만 남기고 절대
 * 요청을 실패시키지 않는다(설계 근거:
 * docs/planning/monetization-referral-engineering-spec-2026-08-14.md §4).
 *
 * **⚠️ `config/billing.model` 게이트(2026-08-15 추가)**: 이 함수는
 * `model`이 `'wallet'`일 때만 실제로 잔액을 지급한다(freeBalance·
 * freeGrantedAt·creditGrants·deviceLedger 기록 전부). `'reset'`(기본값,
 * 지금 라이브 상태)이면 이 그랜트 블록을 통째로 건너뛰고 cohortWeek
 * 백필·리퍼럴 코드 발급만 한다 — reset 모드에서 지급해 버리면
 * freeGrantedAt이 먼저 찍혀서 실제로 wallet을 켠 뒤 표준 무료체험을
 * 영영 못 받는 사고가 나고, deviceLedger의 '기기당 1회' 예산도 출시
 * 전에 미리 소모돼 버린다. 즉 이 함수는 배포해도 `model`이 `'reset'`인
 * 동안은 완전히 무해하다("가" 안, wallet-spec §9 Phase 0 취지).
 */
export const bootstrapAccount = onCall<BootstrapAccountRequest>(
  {
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
    secrets: [deviceHashSalt],
  },
  async (request): Promise<BootstrapAccountResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 후 이용할 수 있어요.");
    }
    const uid = request.auth.uid;
    const email = request.auth.token.email ?? null;
    const db = getFirestore();
    const userRef = db.collection("users").doc(uid);

    // config/billing.freeCredits는 트랜잭션 밖에서 먼저 읽는다(외부 읽기를
    // 트랜잭션 안에 넣지 않는 원칙, incrementAndCheckUsage와 동일 패턴).
    // 문서가 없거나 필드가 없거나 숫자가 아니면 확정값(DEFAULT_FREE_CREDITS
    // =10, monetization-referral-implementation-spec-2026-08-14.md §1)으로
    // 폴백한다.
    // ⚠️ 2026-08-15 정정: 이 함수는 원래 config/billing.model을 확인하지
    // 않고 무조건 무료체험을 지급했다 — reset 모드에서도 aiUsage.freeBalance/
    // freeGrantedAt/creditGrants/deviceLedger를 실제로 썼다는 뜻이다.
    // incrementAndCheckUsage(reset 분기)는 그 필드들을 읽지 않으므로
    // 사용자에게 보이는 한도·화면은 안 바뀌지만("잠든 채 배포"의 절반만
    // 지켜짐), deviceLedger의 "기기당 1회" 예산을 wallet 출시 전에 미리
    // 소모하고 creditGrants에 아직 의미 없는 감사 기록을 쌓이게 된다. 아래
    // billingModel 분기로 reset 모드에서는 이 블록 전체(잔액 지급·감사
    // 기록·기기 캡 소비)를 건너뛰어 완전히 무해하게 만든다 — cohortWeek
    // 백필·리퍼럴 코드 발급은 금전 등가가 아니므로(코드 자체는 아직 redemption
    // 로직이 없어 못 씀) 계속 매 로그인 실행해도 안전하다.
    let configFreeCredits = DEFAULT_FREE_CREDITS;
    let billingModel: BillingModel = "reset";
    try {
      const billingSnap = await db.collection("config").doc("billing").get();
      const raw = billingSnap.exists
        ? billingSnap.data()?.freeCredits
        : undefined;
      if (typeof raw === "number" && Number.isFinite(raw) && raw >= 0) {
        configFreeCredits = raw;
      }
      billingModel = resolveBillingModel(
        billingSnap.exists ? billingSnap.data() : undefined
      );
    } catch (err) {
      logger.warn("config/billing 조회 실패 — 기본 무료 회차/reset 모드로 폴백", {
        error: err instanceof Error ? err.message : String(err),
        fallback: DEFAULT_FREE_CREDITS,
      });
    }

    // 기기 해시는 트랜잭션 밖(순수 계산, I/O 없음)에서 미리 구한다. raw
    // device id 자체는 로그에 남기지 않는다 — "값이 있는지 없는지"만
    // 남긴다(CLAUDE.md 4절).
    let deviceHashValue: string | null = null;
    const rawDeviceId = request.data?.deviceId;
    if (typeof rawDeviceId === "string" && rawDeviceId.trim().length > 0) {
      try {
        deviceHashValue = deviceHash(rawDeviceId, deviceHashSalt.value());
      } catch (err) {
        logger.warn("기기 해시 계산 실패 — 기기 가드 건너뜀", {
          hasDeviceId: true,
          error: err instanceof Error ? err.message : String(err),
        });
        deviceHashValue = null;
      }
    } else {
      logger.warn("deviceId 없는 bootstrapAccount 호출 — 기기 가드 건너뜀", {
        hasDeviceId: false,
      });
    }

    let freeGranted = false;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      const usage = snap.data()?.aiUsage as
        | {
            freeGrantedAt?: FirebaseFirestore.Timestamp;
            freeBalance?: number;
            paidBalance?: number;
            bonusCredits?: number;
          }
        | undefined;

      // U6(파일럿 계측 — 주차 코호트 귀속): users/{uid}.cohortWeek가 이미
      // 있으면 손대지 않는다(멱등). 없으면 이번 로그인 시각(KST)의 ISO
      // 주차로 채운다 — 이 계측을 배포하기 전에 가입한 기존 사용자도 다음
      // 로그인 때 자연히 백필된다. 무료체험 지급 멱등 가드(freeGrantedAt)와는
      // 완전히 독립된 별개 가드라 아래 `plan.shouldGrant`가 false여도(이미
      // 지급됨) 코호트만 따로 채워 넣을 수 있어야 한다.
      const existingCohortWeek = snap.data()?.cohortWeek as string | undefined;
      const cohortWeekToSet = existingCohortWeek
        ? null
        : kstIsoWeekCohort(new Date());

      const plan = planFreeGrant({
        alreadyGranted: usage?.freeGrantedAt != null,
        currentFreeBalance: usage?.freeBalance ?? 0,
        legacyBonusCredits: usage?.bonusCredits ?? 0,
        configFreeCredits,
      });

      // billingModel이 'reset'이면 지갑 자체가 아직 라이브가 아니다 — 이
      // 시점에 freeGrantedAt을 찍어버리면 나중에 실제로 'wallet'을 켰을 때
      // "이미 지급됨"으로 오판해 표준 무료체험을 영영 못 받는다. 그래서
      // reset 모드에서는 그랜트 블록 전체를 건너뛰고 코호트만 백필한 뒤
      // 그대로 반환한다 — 이 uid는 wallet 모드가 켜진 뒤 첫 로그인 때
      // 정상적으로 무료체험을 받는다(ai-credit-wallet-spec.md §9 Phase 1
      // 취지와 일치).
      if (billingModel !== "wallet") {
        if (cohortWeekToSet) {
          tx.set(userRef, {cohortWeek: cohortWeekToSet}, {merge: true});
        }
        return;
      }

      if (!plan.shouldGrant) {
        // 이미 지급됨 — 무료체험은 멱등이라 손대지 않는다. 코호트만 아직
        // 없는 기존 사용자(백필 대상)라면 그 필드 하나만 쓴다.
        if (cohortWeekToSet) {
          tx.set(userRef, {cohortWeek: cohortWeekToSet}, {merge: true});
        }
        return;
      }

      // deviceLedger 조회는 이 트랜잭션의 첫 쓰기(tx.set/tx.create)보다
      // 반드시 먼저 와야 한다(Firestore 트랜잭션 규칙: 모든 get은
      // set/create보다 선행). deviceHashValue가 없으면(가드 건너뜀) 아예
      // deviceLedger를 건드리지 않는다.
      let deviceLedgerRef: FirebaseFirestore.DocumentReference | null = null;
      let trialGrantsIssued = 0;
      if (deviceHashValue) {
        deviceLedgerRef = db.collection("deviceLedger").doc(deviceHashValue);
        const ledgerSnap = await tx.get(deviceLedgerRef);
        trialGrantsIssued =
          (ledgerSnap.data()?.trialGrantsIssued as number | undefined) ?? 0;
      }

      const now = FieldValue.serverTimestamp();
      const deviceCapped =
        deviceLedgerRef != null && !canGrantTrialToDevice(trialGrantsIssued);

      if (deviceCapped) {
        // 이 기기엔 이미 무료체험을 지급한 적이 있다 — 이번 uid는 0회로
        // 처리한다(스펙 §4-3, §4-5 "완벽 차단이 아니라 사용자를 막지
        // 않는 것"). uid 스코프 멱등 가드(freeGrantedAt)는 그래도 찍어서
        // 재시도가 다시 여기로 오지 않게 한다. 잔액은 건드리지 않는다.
        freeGranted = false;
        tx.set(
          userRef,
          {
            aiUsage: {freeBalance: usage?.freeBalance ?? 0, freeGrantedAt: now},
            ...(cohortWeekToSet ? {cohortWeek: cohortWeekToSet} : {}),
          },
          {merge: true}
        );

        const cappedGrantRef = db.collection("creditGrants").doc();
        tx.create(cappedGrantRef, {
          type: "signup_free",
          amount: 0,
          bucket: "free",
          uid,
          email,
          grantedAt: now,
          by: null,
          reason: null,
          note: "device_capped",
          balanceAfter: {
            free: usage?.freeBalance ?? 0,
            paid: usage?.paidBalance ?? 0,
          },
        });
        return;
      }

      freeGranted = true;
      tx.set(
        userRef,
        {
          aiUsage: {freeBalance: plan.newFreeBalance, freeGrantedAt: now},
          ...(cohortWeekToSet ? {cohortWeek: cohortWeekToSet} : {}),
        },
        {merge: true}
      );

      const grantRef = db.collection("creditGrants").doc();
      tx.create(grantRef, {
        type: "signup_free",
        amount: plan.grantedAmount,
        bucket: "free",
        uid,
        email,
        grantedAt: now,
        by: null,
        reason: null,
        note: null,
        balanceAfter: {
          free: plan.newFreeBalance,
          paid: usage?.paidBalance ?? 0,
        },
      });

      if (deviceLedgerRef) {
        // 이 기기에서 무료체험을 지급했다는 사실만 남긴다 — 계정 삭제 시
        // users/{uid}는 파기되지만 이 문서는 계정과 무관하게 살아남는다
        // (onUserDeletedCleanup은 deviceLedger를 건드리지 않음, 스펙 §4-2).
        // firstSeenAt은 문서가 처음 생길 때(trialGrantsIssued===0)만
        // 필드를 포함시킨다 — merge:true라 필드를 아예 안 보내면 기존값이
        // 보존된다(재작성해서 최초 시각을 덮어쓰지 않기 위함).
        tx.set(
          deviceLedgerRef,
          {
            deviceHash: deviceHashValue,
            trialGrantsIssued: trialGrantsIssued + 1,
            lastGrantAt: now,
            ...(trialGrantsIssued === 0 ? {firstSeenAt: now} : {}),
          },
          {merge: true}
        );
      }

      if (plan.carryOver > 0) {
        const adjustRef = db.collection("creditGrants").doc();
        tx.create(adjustRef, {
          type: "adjust",
          amount: plan.carryOver,
          bucket: "free",
          uid,
          email,
          grantedAt: now,
          by: null,
          reason: null,
          note: "bonusCredits 레거시 이월",
          balanceAfter: {
            free: plan.newFreeBalance,
            paid: usage?.paidBalance ?? 0,
          },
        });
      }
    });

    const referralCode = await ensureReferralCode(db, uid);

    return {referralCode, freeGranted};
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

/**
 * 카카오 **연결 해제 웹훅** 수신구.
 *
 * 이용자가 카카오계정 설정에서 우리 앱 연결을 끊으면 카카오가 여기로 알린다.
 * 앱 안의 탈퇴와 달리 **클라이언트가 없으므로** 파기를 서버가 전부 해야 한다.
 *
 * ## ⚠️ 여기서 하는 일은 "접수"뿐이다
 *
 * 카카오는 **3초 안에 200**을 요구한다(공식 문서). 파기는 문서 여러 개를
 * 지우는 일이라 3초를 넘길 수 있다.
 *
 * ⚠️ **"200을 보낸 뒤 이어서 지운다"는 안 된다.** Cloud Functions는 응답을
 * 끝내는 순간 인스턴스 CPU를 죄기 때문에, 응답 후 백그라운드 작업은 조용히
 * 죽는다 — **에뮬레이터에서는 되고 실서버에서 안 되는** 유형이다.
 *
 * 그래서 접수 문서만 남기고 끝낸다. 실제 파기는 그 문서가 만들어질 때 도는
 * [onSocialUnlinkRequested]가 한다. 접수 문서는 그대로 **재시도 장부**가 된다
 * — 카카오의 재시도 정책은 문서에 없으므로 우리 쪽에 남겨야 한다.
 *
 * 📌 접수 문서에는 **uid·사유·시각만** 넣는다. 이름·이메일 같은 개인정보 원문은
 * 담지 않는다.
 */
export const kakaoUnlinkWebhook = onRequest(
  {region: "asia-northeast3", secrets: [kakaoAdminKey], cors: false},
  async (req, res) => {
    // ⚠️ **본문을 읽기 전에** 인증한다. 검증이 이 정적 비밀값 대조 하나뿐이라,
    // 빠뜨리면 아무나 호출해 남의 계정을 지울 수 있는 구멍이 된다.
    if (!adminKeyMatches(req.get("authorization"), kakaoAdminKey.value())) {
      // 어느 키가 왔는지는 남기지 않는다 — 로그가 곧 키 유출이 된다.
      logger.warn("카카오 연결 해제 웹훅: 인증 실패", {method: req.method});
      res.status(401).send("unauthorized");
      return;
    }

    const payload = parseKakaoUnlinkPayload(
      req.body as Record<string, unknown> | undefined,
      req.query as unknown as Record<string, unknown> | undefined,
    );
    if (!payload) {
      logger.warn("카카오 연결 해제 웹훅: 회원번호 없음", {method: req.method});
      res.status(400).send("user_id required");
      return;
    }

    // 어드민 키에 더한 이중 확인. 기대값이 없으면 막지 않는다 — 자세한 이유는
    // `kakaoUnlink.ts`의 appIdAllowed 주석 참고.
    if (!appIdAllowed(payload.appId, process.env.KAKAO_APP_ID)) {
      logger.warn("카카오 연결 해제 웹훅: 다른 앱의 알림", {
        referrerType: payload.referrerType,
      });
      res.status(200).send("ok");
      return;
    }

    const uid = socialUid("kakao", payload.userId);
    try {
      await getFirestore()
        .collection(SOCIAL_UNLINK_REQUESTS)
        .doc(uid)
        .set(
          {
            uid,
            provider: "kakao",
            referrerType: payload.referrerType,
            receivedAt: FieldValue.serverTimestamp(),
            status: "received",
          },
          {merge: true},
        );
    } catch (e) {
      // ⚠️ 접수에 실패하면 **200을 주면 안 된다.** 카카오가 성공으로 알고
      // 다시 보내지 않으면 그 사람 데이터는 영영 남는다.
      logger.error("카카오 연결 해제 접수 실패", {
        uid,
        errorType: (e as Error)?.name,
      });
      res.status(500).send("failed to record");
      return;
    }

    logger.info("카카오 연결 해제 접수", {
      uid,
      referrerType: payload.referrerType,
    });
    res.status(200).send("ok");
  },
);

/**
 * 접수된 연결 해제를 실제로 파기한다.
 *
 * [kakaoUnlinkWebhook]이 남긴 문서가 만들어질 때 돈다. 트리거로 분리한 이유는
 * 위 주석 참고 — 3초 제약과 **실행 보장**을 동시에 만족하기 위해서다.
 *
 * ## 무엇을 지우나
 *
 * ```
 * users/{uid} 및 그 아래 전부   contacts·commLogs·deletedContacts
 * ocrStats/{uid}
 * Firebase Auth 사용자
 * ```
 *
 * 📌 `users/{uid}` **문서가 지워지면 [onUserDeletedCleanup]이 깨어나** 나머지
 * (appleAuth·socialTesterEmails·aiAuditLogs·inquiries·pilotEvents·명함 사진
 * 서버 사본)를 이어서 지운다. 앱 안의 탈퇴와 **같은 경로를 그대로 쓴다** —
 * 파기 대상이 두 벌로 갈라지면 한쪽만 고쳐지는 날이 온다.
 *
 * ⚠️ `deviceLedger`는 여기서도 지우지 않는다. 재가입×무료체험 무한 루프
 * 방어가 "계정 삭제와 무관하게 남는 기기 단위 기록"이기 때문이다.
 *
 * ## 멱등하다
 *
 * 이미 지워진 uid로 다시 와도 조용히 끝난다. 하위 문서 삭제는 쿼리 기반이고,
 * Auth 사용자 삭제는 없음(not-found)을 성공으로 본다.
 */
export const onSocialUnlinkRequested = onDocumentCreated(
  {
    document: `${SOCIAL_UNLINK_REQUESTS}/{uid}`,
    region: "asia-northeast3",
  },
  async (event) => {
    const uid = event.params.uid;
    const db = getFirestore();
    const requestRef = db.collection(SOCIAL_UNLINK_REQUESTS).doc(uid);

    try {
      const userRef = db.collection("users").doc(uid);

      // ⚠️ 문서를 지우는 것만으로는 **하위 컬렉션이 안 지워진다.** 명함이
      // users/{uid}/contacts 아래 있으므로 recursiveDelete를 쓴다.
      const userSnap = await userRef.get();
      if (!userSnap.exists) {
        // 문서가 없으면 onUserDeletedCleanup이 깨어나지 않는다. 하위만 남은
        // 상태일 수 있으므로 정리는 하되, 이어지는 정리가 안 돈다는 사실을
        // 남긴다 — 조용히 넘어가면 남은 감사 로그를 아무도 못 찾는다.
        logger.warn("연결 해제 파기: users 문서가 이미 없음", {uid});
      }
      await db.recursiveDelete(userRef);

      // uid 스코프인데 위 정리가 안 건드리는 것.
      await db.collection("ocrStats").doc(uid).delete();

      try {
        await getAuth().deleteUser(uid);
      } catch (e) {
        const code = (e as {code?: string})?.code;
        if (code !== "auth/user-not-found") throw e;
      }

      await requestRef.set(
        {status: "deleted", deletedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      logger.info("연결 해제 파기 완료", {uid});
    } catch (e) {
      // ⚠️ 접수 문서를 **남긴다.** 지우면 무엇이 안 끝났는지 알 길이 없다 —
      // 파기 의무가 걸린 일이라 "실패했다는 사실"이 남아야 한다.
      await requestRef.set(
        {
          status: "failed",
          failedAt: FieldValue.serverTimestamp(),
          errorType: (e as Error)?.name ?? "unknown",
        },
        {merge: true},
      );
      logger.error("연결 해제 파기 실패", {
        uid,
        errorType: (e as Error)?.name,
      });
      throw e; // 트리거 재시도에 맡긴다
    }
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

    // 소셜 테스터 이메일 정리(2026-08-21, B안).
    //
    // ⚠️ 이 값은 **제공자가 준 이메일 원문**이다. 탈퇴하면 반드시 지워야 한다 —
    // 방침 14번이 "명함 데이터 전체가 삭제된다"고 단언하는 것과 같은 무게다.
    //
    // 📌 위 appleAuth 블록과 같은 모양으로 둔다(문서 하나, uid 가 문서 ID).
    // 없으면 그냥 넘어간다 — 이메일이 정상으로 들어간 계정은 애초에 안 적힌다.
    try {
      await db.collection(SOCIAL_EMAIL_COLLECTION).doc(uid).delete();
    } catch (e) {
      // 실패해도 나머지 정리는 계속한다. ⚠️ 여기서 던지면 트리거 전체가
      // 재시도되어 이미 끝난 삭제를 반복한다(위 블록들과 같은 이유).
      logger.warn("소셜 테스터 이메일 정리 실패", {
        uid,
        errorType: (e as Error)?.name,
      });
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

    // 파일럿 계측 이벤트 삭제(pilotEvents/{uid}/events/*, 2026-08-15).
    // "탈퇴 시 파기" 원칙은 aiAuditLogs·inquiries와 동일하게 이 로그에도
    // 적용된다 — uid가 그대로 남는 계측 데이터라 계정 삭제 시 함께 지운다.
    // ⚠️ deviceLedger/{deviceHash}는 의도적으로 여기서 지우지 않는다 —
    // 재가입×무료체험 무한 루프 방어(U5, 설계 §4-2)의 핵심이 "계정 삭제와
    // 무관하게 남는 기기 단위 기록"이므로, uid 스코프 정리 로직에 절대
    // 섞으면 안 된다.
    const pilotEventsSnap = await db
      .collection("pilotEvents")
      .doc(uid)
      .collection("events")
      .get();
    if (!pilotEventsSnap.empty) {
      for (const batchDocs of chunkArray(pilotEventsSnap.docs, 400)) {
        const batch = db.batch();
        batchDocs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
      }
      logger.info("탈퇴 사용자 파일럿 계측 이벤트 삭제", {
        uid,
        eventCount: pilotEventsSnap.docs.length,
      });
    }
    // ────────── [명함 사진 서버 사본 정리] 시작 ──────────
    // 이 블록만 2026-08-15에 추가됐다. 로직 본체는 cardPhotoCleanup.ts에 있다.
    //
    // 왜 여기인가: 앱이 스스로 지우려는 호출은 **계정을 지운 뒤에** 일어나
    // request.auth가 null이고, storage.rules의 isOwner(uid)가 거짓이 되어
    // 삭제도 listAll도 거부된다. Admin SDK는 규칙을 우회하므로 계정이 사라진
    // 뒤에도 지울 수 있고, 앱이 중간에 죽어도 이 트리거는 돈다.
    //
    // ⚠️ 경계 주석을 둔 이유: 이 함수에 갈래가 여럿 몰려 있고
    // feat/ai-credit-wallet 브랜치가 같은 함수를 크게 고쳐 놨다(deviceLedger는
    // 의도적으로 지우지 않는다는 결정 포함). 나중에 그 브랜치를 rebase 하는
    // 사람이 어디까지가 이번 변경인지 한눈에 보게 한다.
    const photoCleanup = await deleteUserCardPhotos(getStorage().bucket(), uid);
    if (photoCleanup.errorType) {
      // 실패해도 던지지 않는다 — 위 정리들은 이미 끝났고, 여기서 던지면
      // 트리거 전체가 재시도되어 같은 삭제를 반복한다.
      logger.warn("탈퇴 사용자 명함 사진 정리 실패", {
        uid,
        errorType: photoCleanup.errorType,
      });
    }
    // ────────── [명함 사진 서버 사본 정리] 끝 ──────────

    // ────────── [삭제 기록(묘비) 정리] 시작 ──────────
    // 이 블록만 2026-08-15에 추가됐다. 로직 본체는 tombstoneCleanup.ts에 있다.
    //
    // 왜 필요한가: **Firestore는 문서를 지워도 하위 컬렉션을 지우지 않는다.**
    // 앱의 deleteAllUserData는 contacts 문서들과 users/{uid} 문서를 지우지만
    // users/{uid}/deletedContacts/ 는 그대로 남는다 — 지우는 코드가 앱에도
    // 서버에도 없었다. 방침 14번은 "명함 데이터 전체가 삭제된다"고 단언한다.
    //
    // 값은 deletedAt 시각뿐이지만 문서 ID가 contactId이고 경로에 uid가 있다.
    // 개수만 로그에 남기고 문서 ID는 남기지 않는다.
    //
    // ⚠️ 위 사진 블록과 같은 이유로 경계 주석을 둔다 —
    // feat/ai-credit-wallet이 이 함수를 크게 고쳐 놔서, rebase 하는 사람이
    // 어디까지가 이번 변경인지 한눈에 보게 한다.
    const tombstoneCleanup = await deleteTombstones(
      db.collection(`users/${uid}/deletedContacts`),
      () => db.batch(),
      chunkArray,
    );
    if (tombstoneCleanup.errorType) {
      logger.warn("탈퇴 사용자 삭제 기록 정리 실패", {
        uid,
        errorType: tombstoneCleanup.errorType,
        deleted: tombstoneCleanup.deleted,
      });
    } else if (tombstoneCleanup.deleted > 0) {
      logger.info("탈퇴 사용자 삭제 기록 정리", {
        uid,
        deleted: tombstoneCleanup.deleted,
      });
    }
    // ────────── [삭제 기록(묘비) 정리] 끝 ──────────

    // ────────── [번호 확인 기록 정리] 시작 ──────────
    // 이 블록만 2026-09-01에 추가됐다. 로직 본체는 phoneRecordCleanup.ts에 있다.
    //
    // 🚨 이것은 정책 정리가 아니라 **결함 수정**이다. phoneOtpConfirm은
    // "phoneAccounts의 uid가 지금 uid와 다르면 taken"으로 막는데, 탈퇴해도 이
    // 문서가 남아 주인이 **이미 지워진 uid**로 남았다. 같은 번호로 다시
    // 가입하면 새 uid와 달라 **본인 번호인데 영원히 막힌다.**
    //
    // ⭐ 아직 아무도 안 겪었다 — 번호 확인 게이트가 꺼져 있어(config/
    // phoneVerification 문서 없음) 이 경로가 안 돈다. **켜기 전에 잡았다.**
    //
    // 🚨 phoneSendLedger는 **일부러 안 지운다.** 지우면 탈퇴→재가입으로 하루
    // 5통 상한이 초기화된다 — firestore.rules가 그 장부를 서버에 둔 이유가
    // 바로 그것이다("기기에 두면 앱을 지웠다 깔아서 상한을 초기화할 수 있다").
    // 대신 보관 기간(SEND_LEDGER_RETENTION_MS)으로 지운다. 그래서 이 장부는
    // 방침에 **"탈퇴 후에도 남는 것"으로 명시**해야 한다.
    //
    // ⚠️ 위 블록들과 같은 이유로 경계 주석을 둔다.
    const phoneCleanup = await deletePhoneRecords(
      db.collection("phoneAccounts").where("uid", "==", uid),
      (phoneHashValue) =>
        db.collection("phoneOtpChallenges").doc(phoneHashValue),
      () => db.batch(),
    );
    if (phoneCleanup.errorType) {
      logger.warn("탈퇴 사용자 번호 확인 기록 정리 실패", {
        uid,
        errorType: phoneCleanup.errorType,
      });
    } else if (phoneCleanup.deleted > 0) {
      // 🚨 개수만 남긴다. 번호해시는 절대 로그에 담지 않는다.
      logger.info("탈퇴 사용자 번호 확인 기록 정리", {
        uid,
        deleted: phoneCleanup.deleted,
      });
    }
    // ────────── [번호 확인 기록 정리] 끝 ──────────
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

interface GrantSupportCreditsRequest {
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
export const grantSupportCredits = onCall<GrantSupportCreditsRequest>(
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

interface VerifyAndGrantPurchaseRequest {
  platform?: "ios" | "android";
  productId?: string;
  transactionId?: string;
  /** iOS는 영수증 base64, Android는 purchaseToken 등 — 플랫폼마다 형태가
   * 달라 문자열로만 받는다. 실제 검증 로직이 채워질 때 플랫폼별로
   * 파싱한다. */
  receiptData?: string;
}

interface VerifyAndGrantPurchaseResponse {
  credits: number;
  newPaidBalance: number;
}

/**
 * IAP(인앱결제) 영수증 검증 → 크레딧 지급 콜러블 — **U7 "뼈대만" 라운드
 * 산출물이다.**
 *
 * ⚠️ 이 함수는 아직 실제로 크레딧을 지급하지 않는다. 인증 확인·요청 형태
 * 검증·`purchases/{transactionId}` 멱등 조회까지만 실제로 동작하고, 그
 * 다음(실제 영수증 검증)은 명시적으로 `unimplemented`를 던져 막는다 —
 * 아래 TODO 블록 참고. 스토어 상품ID 등록(P1-1)과 Apple/Google 검증
 * 자격증명 발급이 모두 사용자 게이트라 이번 라운드에 구현할 수 없다
 * (docs/planning/monetization-referral-engineering-spec-2026-08-14.md §7).
 *
 * 완성될 때(다음 라운드)의 계약은 ai-credit-wallet-spec.md §3-4 그대로다:
 * `purchases` 문서 ID로 `transactionId`를 그대로 쓰고 `tx.create()`로
 * 동시 재시도 경합을 막으며, `paidBalance`(무료 아님)에 가산한다.
 */
export const verifyAndGrantPurchase = onCall<VerifyAndGrantPurchaseRequest>(
  {
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
    secrets: [appleIapSharedSecret, googlePlayServiceAccountJson],
  },
  async (request): Promise<VerifyAndGrantPurchaseResponse> => {
    // 인증 확인 — 이번 라운드에 실제로 구현하는 유일한 보안 검사(작업
    // 지시서 명시). 나머지(영수증 진위 확인)는 아래에서 unimplemented로
    // 막는다.
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인 후 이용할 수 있어요.");
    }
    const uid = request.auth.uid;
    const email = request.auth.token.email ?? null;

    const platform = request.data?.platform;
    const productId = request.data?.productId;
    const transactionId = request.data?.transactionId;
    const receiptData = request.data?.receiptData;

    if (!isValidIapPlatform(platform)) {
      throw new HttpsError(
        "invalid-argument",
        "platform은 'ios' 또는 'android'여야 해요."
      );
    }
    if (!isValidTransactionId(transactionId)) {
      throw new HttpsError("invalid-argument", "transactionId가 올바르지 않아요.");
    }
    if (!isNonEmptyString(productId)) {
      throw new HttpsError("invalid-argument", "productId가 필요해요.");
    }
    if (!isNonEmptyString(receiptData)) {
      throw new HttpsError("invalid-argument", "receiptData가 필요해요.");
    }

    const db = getFirestore();
    const purchaseRef = db.collection("purchases").doc(transactionId);

    // 멱등 조회 — 같은 transactionId로 이미 처리된 적이 있으면(다음 라운드가
    // 실제 지급 로직을 채운 뒤에만 이 문서가 생긴다) 그 결과를 그대로
    // 반환한다. 지금은 어떤 경로로도 이 문서를 생성하지 않으므로(아래에서
    // 항상 unimplemented) 실질적으로 이 분기는 아직 타지 않지만, 재시도
    // 요청이 왔을 때 안전하게 동작하도록 미리 넣어 둔다.
    const existingSnap = await purchaseRef.get();
    if (existingSnap.exists) {
      const data = existingSnap.data() as
        | {credits?: number; paidBalanceAfter?: number}
        | undefined;
      return {
        credits: data?.credits ?? 0,
        newPaidBalance: data?.paidBalanceAfter ?? 0,
      };
    }

    // productId가 판매 중인 티어와 실제로 매칭되는지는 미리 확인해 둔다
    // (이건 "우리 카탈로그 조회"일 뿐 영수증 진위 검증이 아니라 이번
    // 라운드에도 안전하게 넣을 수 있다). 스토어 상품ID가 아직 등록되지
    // 않았으므로(P1-1) 지금은 모든 productId가 매칭 실패할 것이다 — 이건
    // 버그가 아니라 정상 상태다.
    const billingSnap = await db.collection("config").doc("billing").get();
    const tiers = billingSnap.data()?.tiers as BillingTierRaw[] | undefined;
    const tierLookup = resolveTierByProductId(tiers, productId);
    if (!tierLookup.ok) {
      throw new HttpsError("failed-precondition", tierLookup.error);
    }

    logger.warn(
      "verifyAndGrantPurchase 호출됨 — 실제 영수증 검증 미구현(U7 뼈대만)",
      {uid, platform, hasEmail: Boolean(email), hasReceiptData: true}
    );

    // ⚠️⚠️⚠️ TODO(다음 라운드가 채울 자리): 여기서부터 실제 영수증 검증.
    //
    //   - platform === "ios": App Store Server API(JWS 트랜잭션 검증) 또는
    //     레거시 verifyReceipt 호출. `appleIapSharedSecret.value()`로 공유
    //     비밀을 얻어 요청에 싣는다. 응답의 transactionId·productId가 이
    //     요청값과 일치하는지, 환경(sandbox/production)이 기대와 맞는지
    //     확인해야 한다.
    //   - platform === "android": Google Play Developer API
    //     `purchases.products.get` 호출. `googlePlayServiceAccountJson
    //     .value()`를 파싱해 서비스 계정으로 인증하고, `purchaseState`가
    //     결제완료(0)인지, `consumptionState`가 아직 소비 전인지 확인한다.
    //
    //   검증에 성공한 뒤에만 아래 트랜잭션(ai-credit-wallet-spec.md §3-4
    //   그대로)을 실행해 `paidBalance`에 가산해야 한다 — email 등의 개인
    //   식별정보를 purchases 문서에 남기는 것은 관리자 콘솔의 "충전 내역
    //   조회(고객응대)" 기능이 이미 그렇게 하고 있으므로(§2-2 참고) 유지:
    //
    //   await db.runTransaction(async (tx) => {
    //     const again = await tx.get(purchaseRef);
    //     if (again.exists) return again.data();
    //     const userSnap = await tx.get(db.collection("users").doc(uid));
    //     const currentPaid =
    //       (userSnap.data()?.aiUsage?.paidBalance as number | undefined) ?? 0;
    //     const nextPaid = currentPaid + tierLookup.credits;
    //     tx.create(purchaseRef, {
    //       priceKrw: tierLookup.priceKrw, credits: tierLookup.credits,
    //       status: "paid", purchasedAt: FieldValue.serverTimestamp(),
    //       platform, transactionId, uid, email, paidBalanceAfter: nextPaid,
    //     });
    //     tx.set(db.collection("users").doc(uid),
    //       {aiUsage: {paidBalance: nextPaid}}, {merge: true});
    //     const grantRef = db.collection("creditGrants").doc();
    //     tx.create(grantRef, {
    //       type: "purchase", amount: tierLookup.credits, bucket: "paid",
    //       uid, email, grantedAt: FieldValue.serverTimestamp(), by: null,
    //       reason: null, note: transactionId,
    //       balanceAfter: {
    //         free: userSnap.data()?.aiUsage?.freeBalance ?? 0,
    //         paid: nextPaid,
    //       },
    //     });
    //   });
    //
    //   최초 충전 보너스(AC-4, freeBalance += 5, 1회성)도 이 트랜잭션 성공
    //   직후 `aiUsage.firstChargeBonusGrantedAt` 멱등 가드로 판정해 채운다
    //   (그 uid의 purchases 문서가 이번이 처음인지 확인 필요).
    //
    // 검증이 없는 지금은 절대 이 지점을 지나 크레딧을 지급하지 않는다.
    throw new HttpsError(
      "unimplemented",
      "결제 기능은 아직 준비 중이에요."
    );
  }
);

/**
 * 카카오·네이버 로그인 — 액세스 토큰을 Firebase 커스텀 토큰으로 바꿔 준다.
 *
 * ## 왜 이 함수가 있어야 하나
 *
 * Firebase Auth는 Google·Apple만 기본 제공자로 안다. 카카오·네이버를 붙이는
 * 길은 **커스텀 토큰**과 **OIDC(Identity Platform)** 둘인데, 후자는 SAML/OIDC가
 * 무료 50 MAU 이후 $0.015/MAU라 이용자 1만 명이면 월 20만원이 나간다. 그래서
 * 커스텀 토큰을 골랐다(사용자 결정 2026-08-20, backlog 추가 362).
 *
 * ## ⚠️ 앱의 주장을 믿지 않는다
 *
 * 앱이 넘기는 것은 **액세스 토큰뿐**이다. "나 카카오 12345번이야"라는 회원번호를
 * 앱에서 받아 그대로 쓰면 아무나 남의 계정이 된다. 그래서 **서버가 카카오·
 * 네이버에 직접 물어서** 회원번호를 받아 온다.
 *
 * ## 인증이 필요 없는 함수다
 *
 * 로그인하기 위한 함수라 `request.auth`가 없는 것이 정상이다. 대신 위처럼
 * 외부 제공자에게 물어 신원을 확인한다.
 */
/**
 * 실패해도 로그인을 막지 않는 곁다리 작업용. 이유만 남기고 넘어간다.
 *
 * ⚠️ **성공했는지를 돌려준다.** 예전에는 아무것도 돌려주지 않아서, 부르는
 * 쪽이 실패한 뒤에도 성공 로그를 그대로 찍었다 — 로그만 보면 잘된 것처럼
 * 보이는데 실제로는 닉네임·사진이 안 붙어 있는 상태였다.
 *
 * 📌 이 저장소에서 로그가 원인을 가린 전례가 있다(카카오 이메일 충돌:
 * 진짜 이유는 email-already-exists 였는데 두 번째 오류만 남았다).
 */
/**
 * 계정에 이메일을 못 넣었을 때, **서버에만** 제공자 이메일을 적어 둔다.
 *
 * ## ⚠️ 언제만 적나
 *
 * `auth/email-already-exists` 로 이메일을 빼고 계정을 만든 경우뿐이다.
 * 이메일이 정상으로 들어간 계정은 토큰에서 바로 읽히므로 적을 이유가 없다 —
 * **필요 없는 개인정보를 늘리지 않는다.**
 *
 * ## ⚠️ 수명 — 테스터 목록과 같다
 *
 * 이 값은 오직 `isAllowlistedTester` 의 대조에만 쓰인다. 그 목록
 * (`config/testers`)은 테스트가 끝나면 비우는 항목이므로, **이 컬렉션도 그때
 * 함께 비운다.** 탈퇴 시에는 `onUserDeletedCleanup` 이 지운다.
 *
 * 📌 근거: 법무 2차 회신(질문 8)은 **네이버 연락처 이메일을 계정 식별·본인
 * 확인에 영구 불사용**할 것을 권고했다. 여기 쓰임은 식별이 아니라 **테스트
 * 기간 동안 앱 무결성 우회를 허용할지**를 가리는 것뿐이고, 목록과 같은 수명을
 * 갖도록 묶어 그 권고와 어긋나지 않게 했다.
 *
 * ⚠️ 이메일 원문은 로그에 남기지 않는다. 적었는지 여부만 남긴다.
 */
async function recordSocialTesterEmail(
  uid: string,
  email: string | null | undefined,
  provider: string,
): Promise<void> {
  const value = (email ?? "").trim();
  if (!value) return;
  try {
    await getFirestore().collection(SOCIAL_EMAIL_COLLECTION).doc(uid).set({
      email: value.toLowerCase(),
      provider,
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // 실패해도 로그인은 막지 않는다 — 이건 테스트 편의용 곁다리다.
    logger.warn("소셜 테스터 이메일 기록 실패", {
      provider,
      reason: (e as Error).message,
    });
  }
}

async function tryQuiet(fn: () => Promise<unknown>): Promise<boolean> {
  try {
    await fn();
    return true;
  } catch (e) {
    logger.warn("소셜 레코드 보조 작업 실패(로그인은 계속)", {
      reason: (e as Error).message,
    });
    return false;
  }
}

/**
 * 소셜 로그인에 App Check(앱 무결성 확인)를 **강제할지**.
 *
 * ## ⚠️ 이웃 함수처럼 그냥 켤 수 없다
 *
 * `generateBriefing`은 App Check가 없으면 **테스터 이메일 허용목록**으로
 * 통과시킨다(`isAllowlistedTester`). 그런데 여기는 **로그인 자체**라 아직
 * `request.auth`가 없다 — 확인할 이메일이 없으므로 그 우회로를 못 쓴다.
 *
 * ```
 * generateBriefing   App Check 없음 → 로그인된 이메일이 허용목록에 있나? → 통과
 * socialSignIn       App Check 없음 → 볼 이메일이 없다             → 전원 차단
 * ```
 *
 * ⚠️ **그래서 지금 켜면 테스터가 전부 로그인을 못 한다.** 스토어를 거치지
 * 않은 빌드(App Distribution)는 App Check 토큰을 만들 수 없기 때문이다.
 *
 * ## 그래서 스위치를 둔다 — 기본은 꺼짐
 *
 * `config/billing.model`과 같은 방식이다: **필드가 없으면 꺼진 것**이고,
 * 켜는 것은 콘솔에서 필드를 만드는 별도 동작이다(사용자 결정).
 *
 * ```
 * config/socialAuth.requireAppCheck === true 일 때만 강제
 * 필드 없음 · 읽기 실패 · 그 밖의 값 → 강제하지 않는다
 * ```
 *
 * ⚠️ **읽기에 실패하면 통과시킨다(fail-open).** 로그인 앞단이라, 여기서
 * 막으면 설정 조회가 잠깐 흔들리는 것만으로 **전 이용자가 앱에 못 들어온다.**
 * 무결성 확인을 놓치는 것보다 그쪽이 나쁘다.
 *
 * 📌 켜기 전 확인: 스토어 서명 빌드에서 App Check 토큰이 실제로 발급되는지.
 * 확인 전에 켜면 **정식 이용자도 못 들어온다.**
 */
async function requireAppCheckForSocialSignIn(): Promise<boolean> {
  try {
    const snap = await getFirestore().collection("config").doc("socialAuth").get();
    return snap.exists && snap.data()?.requireAppCheck === true;
  } catch (e) {
    logger.warn("App Check 강제 설정을 읽지 못해 강제하지 않는다", {
      reason: (e as Error).message,
    });
    return false;
  }
}

export const socialSignIn = onCall(
  {
    secrets: [
      kakaoRestKey,
      kakaoClientSecret,
      naverClientId,
      naverClientSecret,
    ],
    region: "asia-northeast3",
    maxInstances: MAX_INSTANCES,
  },
  async (request): Promise<{token: string; provider: string}> => {
    // ── 0단계: 앱 무결성(App Check) ──
    //
    // 지금은 기록만 한다. 강제는 config/socialAuth.requireAppCheck 로 켠다
    // (위 함수의 주석 참고 — 켜면 테스터가 못 들어온다).
    //
    // 📌 **기록만 해도 쓸모가 있다.** 정식 앱 밖에서 들어오는 호출이 실제로
    // 있는지, 있다면 얼마나 되는지를 켜기 전에 볼 수 있다. 수치 없이 켜면
    // 무엇이 막히는지 모르는 채로 막게 된다.
    const appCheckVerified = !!request.app;
    if (!appCheckVerified && await requireAppCheckForSocialSignIn()) {
      throw new HttpsError(
        "failed-precondition",
        "앱 무결성 확인에 실패했어요. 최신 버전의 정식 앱에서 다시 시도해 주세요.",
      );
    }

    let provider: "kakao" | "naver";
    let code: string;
    let redirectUri: string;
    let state: string;
    try {
      const v = validateRequest(request.data);
      provider = v.provider;
      code = v.code;
      redirectUri = v.redirectUri;
      state = v.state;
    } catch (e) {
      throw new HttpsError("invalid-argument", (e as Error).message);
    }

    // ── 1단계: 인가 코드를 액세스 토큰으로 바꾼다 ──
    //
    // ⚠️ 여기서 client_secret이 쓰인다. 앱에 넣을 수 없는 값이라 이 교환을
    // 서버가 맡는 것이다. **카카오·네이버 둘 다 필수**다 — 한때 "카카오는
    // 꺼져 있는 것이 기본"이라고 적어 뒀는데 공식 문서와 다르다(REST API
    // 키는 시크릿이 켜진 채로 생성된다). socialAuth.ts 의 주석 참고.
    let accessToken: string;
    try {
      const body = tokenExchangeBody({
        provider,
        code,
        clientId:
          provider === "kakao"
            ? kakaoRestKey.value()
            : naverClientId.value(),
        clientSecret:
          provider === "kakao"
            ? kakaoClientSecret.value()
            : naverClientSecret.value(),
        redirectUri,
        state,
      });
      const res = await fetch(tokenEndpoint(provider), {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        },
        body,
      });
      // ⚠️ 네이버는 실패해도 200으로 답하므로 본문을 봐야 한다.
      accessToken = parseTokenResponse(await res.json());
    } catch (e) {
      // ⚠️ 본문·토큰을 로그에 남기지 않는다.
      logger.warn("소셜 토큰 교환 실패", {
        provider,
        reason: (e as Error).message,
      });
      throw new HttpsError(
        "unauthenticated",
        "로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.",
      );
    }

    // ── 2단계: 제공자에게 직접 물어 신원을 확인한다 ──
    const url =
      provider === "kakao"
        ? "https://kapi.kakao.com/v2/user/me"
        : "https://openapi.naver.com/v1/nid/me";

    let raw: unknown;
    try {
      const res = await fetch(url, {
        headers: {Authorization: `Bearer ${accessToken}`},
      });
      if (!res.ok) {
        // ⚠️ 본문을 로그에 남기지 않는다 — 개인정보가 들어 있다.
        logger.warn("소셜 사용자 조회 실패", {provider, status: res.status});
        throw new HttpsError(
          "unauthenticated",
          "로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.",
        );
      }
      raw = await res.json();
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.warn("소셜 사용자 조회 중 오류", {provider});
      throw new HttpsError(
        "unavailable",
        "로그인 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.",
      );
    }

    let profile: SocialProfile;
    try {
      profile =
        provider === "kakao" ? parseKakaoUser(raw) : parseNaverUser(raw);
    } catch (e) {
      // 파싱 실패 사유에는 개인정보가 없다(회원번호 유무·resultcode뿐).
      logger.warn("소셜 응답 파싱 실패", {
        provider,
        reason: (e as Error).message,
      });
      throw new HttpsError(
        "unauthenticated",
        "로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.",
      );
    }

    // Firebase 사용자 레코드를 맞춰 둔다. 없으면 만들고, 있으면 표시 정보만
    // 갱신한다. ⚠️ 실패해도 로그인은 막지 않는다 — 레코드는 표시용이고,
    // 커스텀 토큰만 있으면 인증은 성립한다.
    const fields = firebaseUserFields(profile);
    // ⚠️ 이 블록은 실패해도 로그인을 막지 않는다. 레코드는 표시·조회용이고,
    // 커스텀 토큰만 있으면 인증은 성립한다.
    //
    // ⚠️ 처음에는 "고쳐 보고 안 되면 만든다"로만 짰다가 고쳤다(2026-08-20).
    // 그러면 **이메일 충돌로 updateUser가 실패한 것**도 createUser로 흘러가
    // "uid가 이미 있다"는 엉뚱한 오류만 로그에 남는다. 진짜 이유가 가려진다.
    const authAdmin = getAuth();
    // ⚠️ 이름을 errCode로 둔다 — 이 함수 안에 이미 `code`(카카오 인가 코드)가
    // 있어서 겹치면 컴파일이 막힌다.
    const errCode = (e: unknown) => (e as {code?: string}).code ?? "";
    try {
      await authAdmin.updateUser(profile.uid, fields);
    } catch (e1) {
      if (errCode(e1) === "auth/user-not-found") {
        try {
          await authAdmin.createUser({uid: profile.uid, ...fields});
        } catch (e2) {
          // 만들 때도 이메일이 걸리면 이메일 없이 만든다 — 계정 자체는 있어야
          // 닉네임·사진이라도 붙는다.
          if (errCode(e2) === "auth/email-already-exists") {
            const made = await tryQuiet(() =>
              authAdmin.createUser({uid: profile.uid, ...fields, email: undefined}),
            );
            if (made) {
              logger.info("이메일이 다른 계정에 있어 이메일 없이 만들었다", {provider});
              // ⚠️ 이 계정은 토큰에 이메일이 없다 — 테스터 허용목록과 대조할
              // 값이 사라진다. 서버에만 적어 둔다(위 함수 주석 참고).
              await recordSocialTesterEmail(profile.uid, profile.email, provider);
            }
          } else {
            logger.warn("소셜 사용자 레코드 생성 실패(로그인은 계속)", {
              provider,
              reason: errCode(e2) || (e2 as Error).message,
            });
          }
        }
      } else if (errCode(e1) === "auth/email-already-exists") {
        // ⭐ 여기가 실제로 자주 걸리는 자리다. 같은 사람이 구글로도 가입해
        // 두면 그 이메일이 이미 쓰이고 있어 Firebase가 거부한다.
        // 이메일만 빼고 나머지(닉네임·사진)는 넣는다.
        const updated = await tryQuiet(() =>
          authAdmin.updateUser(profile.uid, {...fields, email: undefined}),
        );
        if (updated) {
          logger.info("이메일이 다른 계정에 있어 이메일 없이 갱신했다", {provider});
          await recordSocialTesterEmail(profile.uid, profile.email, provider);
        }
      } else {
        logger.warn("소셜 사용자 레코드 갱신 실패(로그인은 계속)", {
          provider,
          reason: errCode(e1) || (e1 as Error).message,
        });
      }
    }

    const token = await getAuth().createCustomToken(
      profile.uid,
      tokenClaims(profile),
    );
    // ⚠️ uid·이메일·닉네임은 남기지 않는다(제3자 개인정보 원칙, CLAUDE.md 4절).
    // 남기는 것은 "어느 제공자로, 앱 무결성 확인을 통과한 호출이었는지"뿐이다.
    // 이 수치가 쌓여야 App Check를 켤 때 무엇이 막히는지 알 수 있다.
    logger.info("소셜 로그인 성공", {provider: profile.provider, appCheckVerified});
    return {token, provider: profile.provider};
  },
);

/**
 * 원격 로그아웃 — **이 계정으로 로그인한 모든 기기의 세션을 끊는다.**
 *
 * ## 왜 필요한가
 *
 * 폰을 잃어버렸을 때 이용자가 할 수 있는 일이 **계정 삭제밖에 없었다.**
 * 그런데 계정 삭제는 명함과 프로필까지 서버에서 지운다 — 되찾으려던 것이
 * 함께 사라진다. 잃어버린 것은 **기기**인데 **데이터**를 버려야 했던 셈이다.
 *
 * ```
 * 지금까지        ① 계정 삭제(명함도 함께 사라짐)   ② 없음
 * 이 함수가 생기면  ③ 세션만 끊는다 — 데이터는 그대로
 * ```
 *
 * ## ⚠️ 자기 자신도 끊긴다
 *
 * `revokeRefreshTokens`는 **그 uid의 모든 세션**을 무효로 만든다. 지금 이
 * 함수를 부르고 있는 기기도 예외가 아니다. 그래서 앱은 **누르기 전에 그
 * 사실을 알려야 한다** — "다른 기기만 끊긴다"고 오해하면, 되찾은 뒤 자기
 * 폰이 로그아웃돼 있는 것을 결함으로 읽는다.
 *
 * ## 이미 있는 감지 로직을 그대로 쓴다
 *
 * 세션이 끊긴 기기는 토큰을 갱신할 때 `user-token-expired`를 받는다. 앱의
 * `AuthRepository.isAccountAlreadyDeleted()`가 **그 코드를 이미 잡고 있다**
 * (계정 삭제를 감지하려고 만든 것인데 상태가 같다). 새 감지 코드를 만들지
 * 않는다.
 *
 * ## 관리자 함수가 아니다
 *
 * `grantSupportCredits`와 달리 **본인이 자기 계정에 대해서만** 부른다.
 * 다른 uid를 받지 않는다 — 받으면 남의 세션을 끊는 통로가 된다.
 */
export const revokeMySessions = onCall(
  {region: "asia-northeast3", maxInstances: MAX_INSTANCES},
  async (request): Promise<{revokedAt: string}> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요해요.");
    }

    try {
      await getAuth().revokeRefreshTokens(uid);
    } catch (e) {
      // 실패를 조용히 넘기지 않는다 — 이용자는 "끊었다"고 믿고 화면을
      // 떠나는데 실제로는 안 끊긴 상태가 가장 나쁘다.
      logger.error("원격 로그아웃 실패", {uid, error: `${e}`});
      throw new HttpsError(
        "internal",
        "세션을 끊지 못했어요. 잠시 후 다시 시도해 주세요.",
      );
    }

    // ⚠️ 개인정보를 남기지 않는다 — uid 말고는 아무것도 찍지 않는다.
    // 이 로그는 "언제 끊었는지"를 나중에 답하기 위한 것이다(분실 신고 대응).
    const revokedAt = new Date().toISOString();
    logger.info("원격 로그아웃", {uid, revokedAt});
    return {revokedAt};
  },
);

// ─────────────────────────────────────────────────────────────────────────
// 휴대전화번호 인증 (추가 565)
//
// 방침·순서·값의 근거: docs/planning/specs/account-device-policy-2026-08-28.md
//
// ## 🚨 판정은 전부 여기서 한다
//
// ```
// ❌ 기기 시계로 만료 판정      시간을 돌리면 뚫린다
// ❌ 기기에 횟수 저장           지웠다 깔면 상한이 초기화된다
// ✅ 이 함수들이 판정한다        앱을 지웠다 깔아도 상한이 유지된다
// ```
//
// ## ⏸️ 1차 범위 밖 — 계정 잇기
//
// 번호가 이미 다른 uid에 있으면 **알리기만 하고 잇지 않는다**(추가 564).
// uid 형식(A안/B안)이 안 정해졌고, 그것은 되돌릴 수 없는 결정이다.
// ─────────────────────────────────────────────────────────────────────────

/** OTP 관련 시크릿을 함수 하나에 묶어 선언한다. */
const OTP_SECRETS = [
  phoneHashSalt,
  aligoApiKey,
  aligoUserId,
  aligoSenderKey,
  aligoTplCode,
  aligoSender,
  aligoTestMode,
  phoneTestNumbers,
];

/**
 * 지금 쓸 발송기를 고른다.
 *
 * 🚨 **키가 하나라도 비면 `NoKeySender`다.** 절반만 설정된 채로 실제 발송을
 * 시도하면 알리고가 왜 거부했는지 알기 어렵고, 무엇보다 **설정이 덜 된 것을
 * 「되는 것」으로 착각**하게 된다.
 */
function pickSender(): OtpSender {
  const apikey = safeSecret(aligoApiKey);
  const userid = safeSecret(aligoUserId);
  const senderkey = safeSecret(aligoSenderKey);
  const tplCode = safeSecret(aligoTplCode);
  const sender = safeSecret(aligoSender);
  if (!apikey || !userid || !senderkey || !tplCode || !sender) {
    return new NoKeySender();
  }
  return new AligoSender({
    apikey,
    userid,
    senderkey,
    tplCode,
    sender,
    // 기본이 testMode다 — 실제 발송은 "N"을 명시적으로 넣어야 열린다.
    testMode: safeSecret(aligoTestMode) !== "N",
  });
}

/** 시크릿이 아직 없을 때 `.value()`가 던지는 것을 빈 문자열로 받는다. */
function safeSecret(s: {value: () => string}): string {
  try {
    return s.value() ?? "";
  } catch {
    return "";
  }
}

/** 로그에 남겨도 되는 만큼만. 🚨 번호·인증번호는 절대 넣지 않는다. */
function otpLogFields(phoneHashValue: string) {
  return {phonePrefix: phoneHashValue.slice(0, 8)};
}

interface OtpRequestData {
  phone?: unknown;
}

/**
 * 인증번호를 요청한다.
 *
 * 📌 **응답에 인증번호를 절대 싣지 않는다.** 테스트 번호도 마찬가지다 —
 * 테스트 번호는 고정 코드(`000000`)라 애초에 알려 줄 필요가 없다.
 */
export const phoneOtpRequest = onCall<OtpRequestData>(
  {region: "asia-northeast3", maxInstances: MAX_INSTANCES, secrets: OTP_SECRETS},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요해요.");
    }

    const e164 = normalizePhoneKr(
      typeof request.data?.phone === "string" ? request.data.phone : null,
    );
    if (e164 === null) {
      throw new HttpsError(
        "invalid-argument",
        "휴대전화번호를 다시 확인해 주세요.",
      );
    }

    const salt = phoneHashSalt.value();
    const key = phoneHash(e164, salt);
    const db = getFirestore();
    const now = Date.now();

    const ledgerRef = db.collection("phoneSendLedger").doc(key);
    const challengeRef = db.collection("phoneOtpChallenges").doc(key);

    const testNumbers = parseTestNumbers(safeSecret(phoneTestNumbers));
    const isTest = isTestPhone(e164, testNumbers);
    // ⭐ 테스트 번호는 코드를 만들지 않는다 — 샐 경로 자체가 없다.
    const code = isTest ? TEST_PHONE_FIXED_CODE : generateOtpCode();

    // 상한 판정과 장부 기록을 한 트랜잭션에 묶는다. 나눠 두면 동시에 두 번
    // 눌렀을 때 상한을 넘겨 보낼 수 있다.
    const decision = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ledgerRef);
      const ledger = snap.exists ? (snap.data() as SendLedger) : null;
      const d = decideSend(ledger, now);
      if (!d.allowed) return d;
      // 🚨 expiresAt은 **Firestore TTL 정책이 읽는 필드**다. 장부는 탈퇴로
      // 지우지 않으므로(지우면 재가입으로 상한이 초기화된다) 파기는 이
      // 시각으로만 일어난다. ⚠️ TTL 정책을 켜기 전까지는 이 필드가 있어도
      // 아무것도 안 지워진다 — 켜는 명령은 HANDOFF에 있다.
      tx.set(ledgerRef, {
        ...d.nextLedger,
        expiresAt: Timestamp.fromMillis(now + SEND_LEDGER_RETENTION_MS),
      });
      tx.set(challengeRef, {
        codeHash: otpCodeHash(code, salt),
        createdAt: now,
        attempts: 0,
      } satisfies Challenge);
      return d;
    });

    if (!decision.allowed) {
      logger.info("인증번호 요청 거부", {
        ...otpLogFields(key),
        reason: decision.reason,
      });
      const message =
        decision.reason === "resend-too-soon" ?
          "조금 뒤에 다시 받을 수 있어요." :
          "오늘 받을 수 있는 횟수를 다 썼어요.";
      throw new HttpsError("resource-exhausted", message, {
        reason: decision.reason,
        retryAfterMs: decision.retryAfterMs,
      });
    }

    if (isTest) {
      // 🚨 테스트 번호라는 사실을 로그에 남긴다. 운영에서 이 줄이 보이면
      // 목록이 안 지워진 것이다.
      logger.warn("테스트 번호로 인증 진행(발송 안 함)", otpLogFields(key));
      return {sent: true, via: "test-number"};
    }

    const outcome = await pickSender().send(e164, code);
    if (!outcome.sent) {
      logger.error("인증번호 발송 실패", {
        ...otpLogFields(key),
        reason: outcome.reason,
      });
      throw new HttpsError(
        "unavailable",
        "인증번호를 보내지 못했어요. 잠시 후 다시 시도해 주세요.",
      );
    }

    logger.info("인증번호 발송", {...otpLogFields(key), via: outcome.via});
    return {sent: true, via: outcome.via};
  },
);

interface OtpConfirmData {
  phone?: unknown;
  code?: unknown;
}

/**
 * 인증번호를 확인하고 번호를 이 계정에 붙인다.
 *
 * ⏸️ **번호가 이미 다른 uid에 있으면 알리기만 한다**(추가 564) — 자동으로
 * 합치지 않는다. 잇기는 uid 형식이 정해진 뒤에 얹는다.
 */
export const phoneOtpConfirm = onCall<OtpConfirmData>(
  {region: "asia-northeast3", maxInstances: MAX_INSTANCES, secrets: OTP_SECRETS},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "로그인이 필요해요.");
    }

    const e164 = normalizePhoneKr(
      typeof request.data?.phone === "string" ? request.data.phone : null,
    );
    const inputCode =
      typeof request.data?.code === "string" ? request.data.code.trim() : "";
    if (e164 === null || inputCode.length === 0) {
      throw new HttpsError("invalid-argument", "입력을 다시 확인해 주세요.");
    }

    const salt = phoneHashSalt.value();
    const key = phoneHash(e164, salt);
    const db = getFirestore();
    const now = Date.now();

    const challengeRef = db.collection("phoneOtpChallenges").doc(key);
    const accountRef = db.collection("phoneAccounts").doc(key);

    const result = await db.runTransaction(async (tx) => {
      const challengeSnap = await tx.get(challengeRef);
      // ⚠️ 트랜잭션 안의 읽기는 모두 첫 쓰기보다 앞에 와야 한다.
      const accountSnap = await tx.get(accountRef);

      const challenge = challengeSnap.exists ?
        (challengeSnap.data() as Challenge) :
        null;
      const v = verifyOtp(challenge, inputCode, salt, now);

      if (!v.ok) {
        if (v.reason === "mismatch") {
          tx.update(challengeRef, {attempts: v.nextAttempts});
        }
        return {kind: "verify-failed" as const, reason: v.reason};
      }

      // 맞았다. 코드는 즉시 버린다 — 재사용을 막는다.
      tx.delete(challengeRef);

      if (accountSnap.exists) {
        const ownerUid = (accountSnap.data() as {uid?: string}).uid;
        if (ownerUid && ownerUid !== uid) {
          // ⏸️ 잇지 않는다. 어긋남을 화면에 드러내는 데까지가 1차 범위다.
          return {kind: "taken" as const};
        }
        return {kind: "ok" as const};
      }

      tx.set(accountRef, {uid, verifiedAt: now});
      return {kind: "ok" as const};
    });

    if (result.kind === "verify-failed") {
      logger.info("인증번호 확인 실패", {
        ...otpLogFields(key),
        reason: result.reason,
      });
      const message =
        result.reason === "expired" ?
          "시간이 지났어요, 다시 받기" :
          result.reason === "too-many-attempts" ?
            "여러 번 틀려서 이 인증번호는 못 써요. 다시 받아 주세요." :
            result.reason === "no-challenge" ?
              "인증번호를 먼저 받아 주세요." :
              "인증번호가 맞지 않아요.";
      throw new HttpsError("permission-denied", message, {
        reason: result.reason,
        maxAttempts: OTP_MAX_ATTEMPTS,
      });
    }

    if (result.kind === "taken") {
      logger.info("이미 다른 계정에 연결된 번호", otpLogFields(key));
      throw new HttpsError(
        "already-exists",
        "이 번호는 이미 다른 계정에 연결되어 있어요.",
        {reason: "phone-taken"},
      );
    }

    // 번호를 계정 문서에도 적어 둔다. 🚨 원문이 아니라 해시만 남긴다 —
    // 이 문서는 클라이언트가 읽는다.
    await db
      .collection("users")
      .doc(uid)
      .set({phoneVerifiedAt: now, phoneHash: key}, {merge: true});

    logger.info("휴대전화번호 인증 완료", otpLogFields(key));
    return {verified: true};
  },
);
