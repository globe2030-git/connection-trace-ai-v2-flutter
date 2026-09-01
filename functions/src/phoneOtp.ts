/**
 * 휴대전화번호 인증(OTP)의 **순수 로직**.
 *
 * ## 왜 파일을 갈랐나
 *
 * 발송사(알리고) 키가 아직 없다. 그런데 이 기능에서 **키가 필요한 것은
 * 「보내는 곳」 한 조각뿐**이고, 나머지 — 번호를 다듬고, 코드를 만들고,
 * 3분을 재고, 맞는지 보고, 상한을 세는 것 — 은 전부 키와 무관하다.
 *
 * 그래서 그 전부를 여기 순수 함수로 두고 **지금 테스트한다.** 키가 오면
 * `index.ts`의 발송 자리에 한 조각만 끼운다.
 *
 * `socialAuth.ts`가 *"HTTP 호출 없는 순수 함수"*로 갈라져 있는 것과 같은
 * 이유이고, 해시·상한 다루는 방식은 `deviceLedger.ts`를 따랐다.
 *
 * ## 🚨 이 파일이 지키는 것
 *
 * ```
 * 인증번호를 평문으로 저장하지 않는다      해시만 넘긴다
 * 번호를 로그·에러 메시지에 넣지 않는다     이 파일은 로그를 찍지 않는다
 * 만료·상한 판정에 기기 시각을 안 쓴다      호출자가 서버 시각을 넘긴다
 * ```
 *
 * 마지막 것이 이 파일의 서명 규칙이다 — **`now`를 인자로 받는다.**
 * `Date.now()`를 안에서 부르면 테스트가 시계에 묶이고, 무엇보다
 * *"서버가 판정한다"*는 것이 코드로 안 보인다.
 */

import {createHmac, randomInt} from "crypto";

/** 인증번호 자릿수. 알림톡 템플릿 문안(`#{인증번호}`)과 맞춘다. */
export const OTP_CODE_LENGTH = 6;

/**
 * 인증번호 유효시간 = **3분**(2026-08-28 globe2030님 확정, 추가 562).
 *
 * 🚨 **이 값은 알림톡 템플릿 문안에 들어가 있다** — *"3분 안에 앱 화면에
 * 입력해 주세요"*. 바꾸려면 **템플릿을 다시 심사**받아야 하고 영업일 2일이
 * 든다. 나머지 상한값들과 무게가 다르다.
 */
export const OTP_TTL_MS = 3 * 60 * 1000;

/**
 * 재발송 간격 = **3분**(유효시간과 같다).
 *
 * ⭐ 같게 둔 것이 설계다 — **코드가 죽는 순간 재발송이 열린다.** 두 코드가
 * 동시에 살아 있는 구간이 안 생겨서 *"어느 코드가 맞는 건가"*를 다룰 필요가
 * 없다.
 *
 * ⚠️ 대가는 **못 받은 사람이 3분을 기다리는 것**이다. 이 값은 템플릿 문안에
 * 안 들어가므로 **재심사 없이 바꿀 수 있다**(추가 563).
 */
export const OTP_RESEND_INTERVAL_MS = OTP_TTL_MS;

/** 하루 발송 상한 = 5번. **같은 번호 기준**이다(기기 기준이 아니다). */
export const OTP_DAILY_SEND_CAP = 5;

/** 틀린 횟수 상한 = 5번. 넘으면 그 인증번호를 버린다. */
export const OTP_MAX_ATTEMPTS = 5;

/**
 * 발송 장부(`phoneSendLedger`) 보관 기간 = **30일**.
 *
 * 🚨 **탈퇴로는 이 장부를 지우지 않는다.** 지우면 탈퇴 → 재가입으로 하루
 * 상한이 초기화된다 — `firestore.rules`가 이 장부를 기기가 아니라 서버에 둔
 * 이유가 바로 그것이다(*"기기에 두면 앱을 지웠다 깔아서 상한을 초기화할 수
 * 있다"*). 그래서 파기는 **탈퇴가 아니라 시간**으로 한다.
 *
 * 📌 **[AI 한도 재가입 우회]와 구조는 같은데 결론이 반대다.** 그쪽은
 * 사용자가 A안(수용)으로 정했다. 다르게 정한 이유는 하나뿐 — **문자는 건당
 * 실제 비용이 나간다.** 이 문단이 없으면 다음 사람이 *"AI는 수용했는데 왜
 * 이건 막나"*로 되돌리려 든다.
 *
 * ⚠️ **이 상수만으로는 아무것도 안 지워진다.** 실제 삭제는 Firestore의 TTL
 * 정책이 하고, 그것은 저장소가 아니라 **콘솔·gcloud 설정**이다. 켜는 명령은
 * `docs/planning/HANDOFF.md`에 적어 두었다 — **켜기 전까지 장부는 계속
 * 쌓인다.** 코드에 상수가 있다고 파기되는 것으로 읽으면 안 된다.
 */
export const SEND_LEDGER_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * 번호를 E.164(`+8210…`)로 다듬는다. **국내 번호만 받는다.**
 *
 * 받아들이는 모양: `01012345678` · `010-1234-5678` · `+821012345678` ·
 * `82 10 1234 5678`. 공백·하이픈·괄호·점은 버린다.
 *
 * ⚠️ **다듬지 못하면 `null`을 준다.** 예외를 던지지 않는 것은 호출자가
 * *"왜 실패했는지"*를 이용자 문구로 바꿔야 하기 때문이고, 무엇보다
 * **예외 메시지에 번호가 실려 로그로 새는 것**을 막기 위해서다.
 */
export function normalizePhoneKr(raw: string | null | undefined): string | null {
  if (typeof raw !== "string") return null;
  const digitsOnly = raw.replace(/[\s\-().]/g, "");
  if (digitsOnly.length === 0) return null;

  let body: string;
  if (digitsOnly.startsWith("+82")) {
    body = digitsOnly.slice(3);
  } else if (digitsOnly.startsWith("82") && !digitsOnly.startsWith("820")) {
    // "8210…" — 국가번호가 + 없이 붙은 흔한 모양.
    // ⚠️ "820…"은 제외한다. `0212345678`(서울 국번)이 82로 시작하는 일은
    // 없지만, "82" + "0"으로 시작하면 국가번호가 아니라 그냥 번호일 수 있다.
    body = digitsOnly.slice(2);
  } else if (digitsOnly.startsWith("0")) {
    body = digitsOnly.slice(1);
  } else {
    return null;
  }

  // 남은 몸통은 숫자만이어야 하고, 휴대폰은 `10`으로 시작한다.
  // 🚨 010만 받는다 — 011/016/017/018/019는 2021년에 서비스가 끝났고,
  // 유선번호로는 알림톡·문자를 못 받는다.
  if (!/^10\d{7,8}$/.test(body)) return null;
  return `+82${body}`;
}

/**
 * 번호를 해시한다. **저장·조회 키로 이것만 쓴다.**
 *
 * `deviceLedger.deviceHash`와 같은 방식(HMAC-SHA256 + 시크릿 salt)이다.
 * 🚨 salt는 절대 코드에 두지 않는다 — Secret Manager에서 온다.
 *
 * ⚠️ **salt를 바꾸면 기존 매핑이 전부 안 맞는다.** 한번 정해 데이터가 쌓이면
 * 사실상 못 바꾼다(추가 462가 CI/DI에서 지적한 것과 같은 구조).
 */
export function phoneHash(e164: string, salt: string): string {
  return createHmac("sha256", salt).update(e164).digest("hex");
}

/** 인증번호를 해시한다. 🚨 **평문 코드는 어디에도 저장하지 않는다.** */
export function otpCodeHash(code: string, salt: string): string {
  return createHmac("sha256", salt).update(code).digest("hex");
}

/**
 * 인증번호를 만든다. `randomInt`(CSPRNG)를 쓴다 — `Math.random`은 예측 가능해
 * 인증에 쓰면 안 된다.
 *
 * 앞자리 0을 허용한다(`000123`도 정상). 자릿수를 채워 문자열로 준다.
 */
export function generateOtpCode(): string {
  const max = 10 ** OTP_CODE_LENGTH;
  return String(randomInt(0, max)).padStart(OTP_CODE_LENGTH, "0");
}

/**
 * 두 해시를 **길이·내용이 같은지** 비교한다.
 *
 * 📌 `crypto.timingSafeEqual`을 쓰지 않는다. 비교 대상이 **원문이 아니라
 * 해시**라 타이밍으로 새어도 알아낼 수 있는 것이 없고, 길이가 다르면
 * `timingSafeEqual`이 예외를 던져 오히려 분기가 는다.
 */
export function otpCodeMatches(
  inputCode: string,
  storedCodeHash: string,
  salt: string,
): boolean {
  if (!/^\d+$/.test(inputCode)) return false;
  return otpCodeHash(inputCode, salt) === storedCodeHash;
}

/** 하루 발송 상한을 세는 창의 키. **서버 시각의 UTC 날짜**로 자른다. */
export function sendWindowKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

/** 발송 기록. 하루 상한과 재발송 간격을 이것으로 판정한다. */
export interface SendLedger {
  /** [sendWindowKey]가 가리키는 날. 다르면 [sentToday]는 0으로 본다. */
  windowKey: string;
  /** 그 날 보낸 횟수. */
  sentToday: number;
  /** 마지막으로 보낸 서버 시각(ms). 한 번도 안 보냈으면 `null`. */
  lastSentAt: number | null;
}

/** 발송 요청을 받아 줄지, 안 받으면 왜 안 받는지. */
export type SendDecision =
  | {allowed: true; nextLedger: SendLedger}
  | {allowed: false; reason: "resend-too-soon"; retryAfterMs: number}
  | {allowed: false; reason: "daily-cap"; retryAfterMs: number};

/**
 * **지금 인증번호를 보내도 되는가**를 판정한다.
 *
 * 순서가 있다 — **재발송 간격을 먼저 본다.**
 * 📌 하루 상한을 먼저 보면, 상한에 걸린 사람에게 *"내일 오세요"*라고 하는데
 * 사실은 **3분만 기다리면 되는 경우**가 섞인다. 가까운 벽을 먼저 알려 준다.
 *
 * ⚠️ [retryAfterMs]를 함께 준다. 화면이 *"몇 초 뒤에 다시"*를 **서버가 준
 * 값으로** 보여야 한다 — 기기 시계로 세면 시계를 돌려 뚫는다.
 */
export function decideSend(
  ledger: SendLedger | null,
  now: number,
): SendDecision {
  const windowKey = sendWindowKey(now);
  const sameWindow = ledger !== null && ledger.windowKey === windowKey;
  const sentToday = sameWindow ? ledger.sentToday : 0;

  if (ledger?.lastSentAt != null) {
    const since = now - ledger.lastSentAt;
    if (since < OTP_RESEND_INTERVAL_MS) {
      return {
        allowed: false,
        reason: "resend-too-soon",
        retryAfterMs: OTP_RESEND_INTERVAL_MS - since,
      };
    }
  }

  if (sentToday >= OTP_DAILY_SEND_CAP) {
    // 자정(UTC)까지 남은 시간. ⚠️ 이 값은 "언제 풀리는지"를 알려 주는
    // 용도이고, 화면에 그대로 초 단위로 쓰라는 뜻이 아니다.
    const nextMidnight = Date.parse(`${windowKey}T00:00:00.000Z`) + 86_400_000;
    return {
      allowed: false,
      reason: "daily-cap",
      retryAfterMs: Math.max(0, nextMidnight - now),
    };
  }

  return {
    allowed: true,
    nextLedger: {windowKey, sentToday: sentToday + 1, lastSentAt: now},
  };
}

/** 살아 있는 인증번호 한 건. 🚨 평문 코드는 여기 없다. */
export interface Challenge {
  /** [otpCodeHash]로 만든 값. */
  codeHash: string;
  /** 만든 서버 시각(ms). */
  createdAt: number;
  /** 지금까지 틀린 횟수. */
  attempts: number;
}

/** 인증번호 검증 결과. */
export type VerifyResult =
  | {ok: true}
  | {ok: false; reason: "expired"}
  | {ok: false; reason: "no-challenge"}
  | {ok: false; reason: "too-many-attempts"}
  | {ok: false; reason: "mismatch"; attemptsLeft: number; nextAttempts: number};

/**
 * 입력한 인증번호를 검증한다.
 *
 * 판정 순서가 곧 이용자에게 보이는 문구의 순서다.
 *
 * ```
 * 없다      → 다시 받아야 한다
 * 만료      → "시간이 지났어요, 다시 받기"   (추가 563 확정 문구)
 * 횟수 초과  → 이 코드는 죽었다. 다시 받아야 한다
 * 틀림      → 남은 횟수를 알려 준다
 * ```
 *
 * 📌 **만료를 틀린 횟수보다 먼저 본다.** 3분이 지난 코드에 대고 *"5번 중
 * 2번 틀렸어요"*라고 하면, 이용자는 남은 3번을 더 써 보려다 시간만 쓴다.
 */
export function verifyOtp(
  challenge: Challenge | null,
  inputCode: string,
  salt: string,
  now: number,
): VerifyResult {
  if (challenge === null) return {ok: false, reason: "no-challenge"};

  if (now - challenge.createdAt >= OTP_TTL_MS) {
    return {ok: false, reason: "expired"};
  }

  if (challenge.attempts >= OTP_MAX_ATTEMPTS) {
    return {ok: false, reason: "too-many-attempts"};
  }

  if (otpCodeMatches(inputCode, challenge.codeHash, salt)) {
    return {ok: true};
  }

  const nextAttempts = challenge.attempts + 1;
  return {
    ok: false,
    reason: "mismatch",
    nextAttempts,
    attemptsLeft: Math.max(0, OTP_MAX_ATTEMPTS - nextAttempts),
  };
}

/**
 * 이 번호가 **테스트 번호**인가.
 *
 * ## 🚨 이 함수의 기본값이 안전장치다
 *
 * 목록이 비어 있으면 **항상 `false`** — 즉 **테스트 경로가 죽는다.**
 * *"설정이 없으면 전부 실제 발송"*이 기본이어야, 설정을 깜빡한 것이
 * **기능이 열린 채로 나가는 것**이 되지 않는다.
 *
 * ⚠️ **이 목록이 운영에 남으면 그 번호로 누구나 로그인한다.** 「휴대폰이
 * 사람이다」가 통째로 무너진다. 릴리스 점검표에 확인 줄을 넣어 두었다
 * (`docs/planning/release-checklist.md`).
 *
 * 목록은 **다듬은 뒤(E.164)** 비교한다 — 설정에 `010-1234-5678`로 적혀
 * 있어도 맞아야 한다.
 */
export function isTestPhone(
  e164: string,
  rawTestNumbers: readonly string[] | null | undefined,
): boolean {
  if (!rawTestNumbers || rawTestNumbers.length === 0) return false;
  for (const raw of rawTestNumbers) {
    if (normalizePhoneKr(raw) === e164) return true;
  }
  return false;
}

/**
 * 테스트 번호가 받는 **고정 인증번호**.
 *
 * ⭐ 고정값을 쓰는 것이 핵심이다 — **인증번호를 아예 만들지 않으므로
 * 화면·응답·로그 어디로도 흐를 경로가 없다.** 테스트용으로 코드를 응답에
 * 실어 보내는 방식이었다면, 그 코드가 실수로 운영에 남는 순간 전부 뚫린다.
 */
export const TEST_PHONE_FIXED_CODE = "000000";

/**
 * 설정 문자열을 테스트 번호 목록으로 읽는다. 쉼표·공백·줄바꿈으로 나눈다.
 *
 * 값이 없거나 비면 **빈 배열** — [isTestPhone]의 기본값 규칙과 이어진다.
 */
export function parseTestNumbers(
  raw: string | null | undefined,
): readonly string[] {
  if (typeof raw !== "string") return [];
  return raw
    .split(/[,\n]/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}
