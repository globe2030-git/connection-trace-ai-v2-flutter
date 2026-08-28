/**
 * phoneOtp.ts 단위 테스트. deviceLedger.test.ts와 같은 스타일(Node 내장
 * 테스트 러너).
 *
 * 🚨 **여기서 확인하는 것이 「발송사 키가 없어도 만들 수 있는 전부」다.**
 * 3분·상한·판정이 실제로 도는지를 키 없이 여기서 증명한다.
 *
 * ⚠️ 시각은 전부 인자로 넣는다 — 진짜 시계를 기다리면 3분짜리 만료를
 * 확인할 수 없고, 무엇보다 "서버가 판정한다"가 코드로 안 보인다.
 *
 * 실행: `npm run build && node --test lib/phoneOtp.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  Challenge,
  OTP_CODE_LENGTH,
  OTP_DAILY_SEND_CAP,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_INTERVAL_MS,
  OTP_TTL_MS,
  SendLedger,
  TEST_PHONE_FIXED_CODE,
  decideSend,
  generateOtpCode,
  isTestPhone,
  normalizePhoneKr,
  otpCodeHash,
  otpCodeMatches,
  parseTestNumbers,
  phoneHash,
  sendWindowKey,
  verifyOtp,
} from "./phoneOtp";

const SALT = "test-salt-not-a-real-secret";
/** 2026-08-28 12:00:00 UTC — 자정에서 충분히 떨어진 시각. */
const T0 = Date.parse("2026-08-28T12:00:00.000Z");

// ---- normalizePhoneKr ----

test("normalizePhoneKr: 여러 모양을 같은 E.164로 다듬는다", () => {
  for (const raw of [
    "01012345678",
    "010-1234-5678",
    "010 1234 5678",
    "(010) 1234-5678",
    "+821012345678",
    "+82 10 1234 5678",
    "821012345678",
  ]) {
    assert.equal(normalizePhoneKr(raw), "+821012345678", `입력: ${raw}`);
  }
});

test("normalizePhoneKr: 🚨 010이 아닌 것은 받지 않는다", () => {
  // 011~019는 2021년에 서비스가 끝났고, 유선번호는 알림톡·문자를 못 받는다.
  for (const raw of [
    "0212345678", // 서울 유선
    "01112345678", // 011 — 종료된 식별번호
    "1588-1588", // 대표번호
    "+8112345678", // 다른 나라
    "abc",
    "",
    "   ",
  ]) {
    assert.equal(normalizePhoneKr(raw), null, `입력: ${raw}`);
  }
});

test("normalizePhoneKr: 문자열이 아니면 null", () => {
  assert.equal(normalizePhoneKr(null), null);
  assert.equal(normalizePhoneKr(undefined), null);
});

test("normalizePhoneKr: 자릿수가 모자라거나 넘치면 받지 않는다", () => {
  assert.equal(normalizePhoneKr("010123456"), null);
  assert.equal(normalizePhoneKr("0101234567890"), null);
});

// ---- phoneHash ----

test("phoneHash: 같은 번호·같은 salt면 항상 같은 값(결정론적)", () => {
  assert.equal(
    phoneHash("+821012345678", SALT),
    phoneHash("+821012345678", SALT),
  );
});

test("phoneHash: 🚨 salt가 다르면 값이 달라진다 — 바꾸면 매핑이 깨진다", () => {
  assert.notEqual(
    phoneHash("+821012345678", SALT),
    phoneHash("+821012345678", "other-salt"),
  );
});

test("phoneHash: 결과에 번호 원문이 남지 않는다", () => {
  const h = phoneHash("+821012345678", SALT);
  assert.equal(h.includes("1012345678"), false);
  assert.match(h, /^[0-9a-f]{64}$/);
});

// ---- generateOtpCode ----

test("generateOtpCode: 항상 정해진 자릿수의 숫자(앞자리 0 포함)", () => {
  for (let i = 0; i < 200; i++) {
    const code = generateOtpCode();
    assert.equal(code.length, OTP_CODE_LENGTH);
    assert.match(code, /^\d+$/);
  }
});

test("generateOtpCode: 같은 값만 나오지 않는다", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 100; i++) seen.add(generateOtpCode());
  assert.ok(seen.size > 50, `서로 다른 값 ${seen.size}개`);
});

// ---- otpCodeMatches ----

test("otpCodeMatches: 맞는 코드만 통과한다", () => {
  const hash = otpCodeHash("123456", SALT);
  assert.equal(otpCodeMatches("123456", hash, SALT), true);
  assert.equal(otpCodeMatches("123457", hash, SALT), false);
});

test("otpCodeMatches: 숫자가 아니면 통과하지 않는다", () => {
  const hash = otpCodeHash("123456", SALT);
  assert.equal(otpCodeMatches("12345a", hash, SALT), false);
  assert.equal(otpCodeMatches("", hash, SALT), false);
});

// ---- decideSend: 재발송 간격 ----

test("decideSend: 처음이면 보낸다", () => {
  const d = decideSend(null, T0);
  assert.equal(d.allowed, true);
  if (d.allowed) {
    assert.equal(d.nextLedger.sentToday, 1);
    assert.equal(d.nextLedger.lastSentAt, T0);
  }
});

test("decideSend: 3분이 안 지났으면 막고 남은 시간을 알려 준다", () => {
  const ledger: SendLedger = {
    windowKey: sendWindowKey(T0),
    sentToday: 1,
    lastSentAt: T0,
  };
  const d = decideSend(ledger, T0 + 60_000);
  assert.equal(d.allowed, false);
  if (!d.allowed) {
    assert.equal(d.reason, "resend-too-soon");
    // ⚠️ 남은 시간을 서버가 준다 — 기기 시계로 세지 않는다.
    assert.equal(d.retryAfterMs, OTP_RESEND_INTERVAL_MS - 60_000);
  }
});

test("decideSend: ⭐ 코드가 죽는 순간 재발송이 열린다(간격 = 유효시간)", () => {
  const ledger: SendLedger = {
    windowKey: sendWindowKey(T0),
    sentToday: 1,
    lastSentAt: T0,
  };
  // 만료 직전 — 아직 막힌다.
  assert.equal(decideSend(ledger, T0 + OTP_TTL_MS - 1).allowed, false);
  // 만료되는 그 순간 — 열린다. 두 코드가 겹치는 구간이 없다.
  assert.equal(decideSend(ledger, T0 + OTP_TTL_MS).allowed, true);
});

// ---- decideSend: 하루 상한 ----

test("decideSend: 상한까지 보내고 그다음을 막는다", () => {
  let ledger: SendLedger | null = null;
  let now = T0;
  for (let i = 0; i < OTP_DAILY_SEND_CAP; i++) {
    const d = decideSend(ledger, now);
    assert.equal(d.allowed, true, `${i + 1}번째 발송`);
    if (d.allowed) ledger = d.nextLedger;
    now += OTP_RESEND_INTERVAL_MS;
  }
  const blocked = decideSend(ledger, now);
  assert.equal(blocked.allowed, false);
  if (!blocked.allowed) assert.equal(blocked.reason, "daily-cap");
});

test("decideSend: 📌 가까운 벽을 먼저 알려 준다 — 간격이 상한보다 먼저", () => {
  // 상한을 다 쓴 데다 방금 보낸 상태.
  const ledger: SendLedger = {
    windowKey: sendWindowKey(T0),
    sentToday: OTP_DAILY_SEND_CAP,
    lastSentAt: T0,
  };
  const d = decideSend(ledger, T0 + 1000);
  assert.equal(d.allowed, false);
  // "내일 오세요"가 아니라 "3분만 기다리세요"가 먼저다.
  if (!d.allowed) assert.equal(d.reason, "resend-too-soon");
});

test("decideSend: 날이 바뀌면 상한이 새로 열린다", () => {
  const ledger: SendLedger = {
    windowKey: sendWindowKey(T0),
    sentToday: OTP_DAILY_SEND_CAP,
    lastSentAt: T0,
  };
  const d = decideSend(ledger, T0 + 86_400_000);
  assert.equal(d.allowed, true);
  if (d.allowed) assert.equal(d.nextLedger.sentToday, 1);
});

// ---- verifyOtp ----

const makeChallenge = (over: Partial<Challenge> = {}): Challenge => ({
  codeHash: otpCodeHash("123456", SALT),
  createdAt: T0,
  attempts: 0,
  ...over,
});

test("verifyOtp: 맞으면 통과한다", () => {
  assert.deepEqual(verifyOtp(makeChallenge(), "123456", SALT, T0 + 1000), {
    ok: true,
  });
});

test("verifyOtp: 코드가 없으면 no-challenge", () => {
  assert.deepEqual(verifyOtp(null, "123456", SALT, T0), {
    ok: false,
    reason: "no-challenge",
  });
});

test("verifyOtp: 3분 경계를 정확히 본다", () => {
  // 2분 59.999초 — 아직 산다.
  assert.equal(
    verifyOtp(makeChallenge(), "123456", SALT, T0 + OTP_TTL_MS - 1).ok,
    true,
  );
  // 정확히 3분 — 죽는다.
  assert.deepEqual(
    verifyOtp(makeChallenge(), "123456", SALT, T0 + OTP_TTL_MS),
    {ok: false, reason: "expired"},
  );
});

test("verifyOtp: 📌 만료를 틀린 횟수보다 먼저 본다", () => {
  // 만료됐고 시도도 남은 상태 → "남은 횟수"가 아니라 "만료"여야 한다.
  // 그렇지 않으면 이용자가 죽은 코드에 남은 시도를 쓴다.
  assert.deepEqual(
    verifyOtp(makeChallenge({attempts: 2}), "999999", SALT, T0 + OTP_TTL_MS + 1),
    {ok: false, reason: "expired"},
  );
});

test("verifyOtp: 틀리면 남은 횟수를 준다", () => {
  const r = verifyOtp(makeChallenge({attempts: 1}), "999999", SALT, T0 + 1000);
  assert.equal(r.ok, false);
  if (!r.ok && r.reason === "mismatch") {
    assert.equal(r.nextAttempts, 2);
    assert.equal(r.attemptsLeft, OTP_MAX_ATTEMPTS - 2);
  }
});

test("verifyOtp: 5번을 채우면 맞는 코드를 넣어도 안 된다", () => {
  assert.deepEqual(
    verifyOtp(
      makeChallenge({attempts: OTP_MAX_ATTEMPTS}),
      "123456",
      SALT,
      T0 + 1000,
    ),
    {ok: false, reason: "too-many-attempts"},
  );
});

test("verifyOtp: 틀린 횟수가 실제로 5번 만에 닫힌다", () => {
  let challenge = makeChallenge();
  for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
    const r = verifyOtp(challenge, "999999", SALT, T0 + 1000);
    assert.equal(r.ok, false, `${i + 1}번째 시도`);
    if (!r.ok && r.reason === "mismatch") {
      challenge = {...challenge, attempts: r.nextAttempts};
    }
  }
  assert.deepEqual(verifyOtp(challenge, "999999", SALT, T0 + 1000), {
    ok: false,
    reason: "too-many-attempts",
  });
});

// ---- 테스트 번호: 🚨 안전장치가 이 방법의 절반이다 ----

test("isTestPhone: 목록이 비면 아무 번호도 테스트 번호가 아니다", () => {
  // 🚨 기본값이 「닫힘」이다. 설정을 깜빡한 것이 "기능이 열린 채로 나가는
  // 것"이 되면 안 된다.
  assert.equal(isTestPhone("+821012345678", []), false);
  assert.equal(isTestPhone("+821012345678", null), false);
  assert.equal(isTestPhone("+821012345678", undefined), false);
});

test("isTestPhone: 목록에 있으면 잡고 없으면 안 잡는다", () => {
  const list = ["010-1234-5678"];
  assert.equal(isTestPhone("+821012345678", list), true);
  assert.equal(isTestPhone("+821099999999", list), false);
});

test("isTestPhone: 설정에 적힌 모양이 달라도 다듬어서 비교한다", () => {
  for (const raw of ["01012345678", "+82 10 1234 5678", " 010-1234-5678 "]) {
    assert.equal(isTestPhone("+821012345678", [raw]), true, `설정: ${raw}`);
  }
});

test("parseTestNumbers: 쉼표·줄바꿈으로 나누고 빈 값을 버린다", () => {
  assert.deepEqual(parseTestNumbers("010-1111-2222, 010-3333-4444"), [
    "010-1111-2222",
    "010-3333-4444",
  ]);
  assert.deepEqual(parseTestNumbers("010-1111-2222\n\n010-3333-4444\n"), [
    "010-1111-2222",
    "010-3333-4444",
  ]);
  assert.deepEqual(parseTestNumbers(""), []);
  assert.deepEqual(parseTestNumbers(null), []);
  assert.deepEqual(parseTestNumbers("  ,  "), []);
});

test("TEST_PHONE_FIXED_CODE: 자릿수 규칙을 지킨다", () => {
  assert.equal(TEST_PHONE_FIXED_CODE.length, OTP_CODE_LENGTH);
  assert.match(TEST_PHONE_FIXED_CODE, /^\d+$/);
});
