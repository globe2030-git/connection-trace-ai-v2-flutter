/**
 * referralCode.ts 단위 테스트. walletCredits.test.ts와 같은 스타일(Node
 * 내장 테스트 러너).
 * 실행: `npm run build && node --test lib/referralCode.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  REFERRAL_CODE_CHARSET,
  REFERRAL_CODE_LENGTH,
  generateReferralCode,
  isValidReferralCodeFormat,
} from "./referralCode";

test("generateReferralCode: 기본 길이(REFERRAL_CODE_LENGTH)의 코드를 만든다", () => {
  const code = generateReferralCode();
  assert.equal(code.length, REFERRAL_CODE_LENGTH);
});

test("generateReferralCode: 허용 문자셋 안의 문자만 쓴다(0/O/1/I/L 없음)", () => {
  // 결정적이지 않으므로 여러 번 뽑아 문자셋 밖 문자가 없는지 확인한다.
  for (let i = 0; i < 200; i++) {
    const code = generateReferralCode();
    for (const ch of code) {
      assert.ok(
        REFERRAL_CODE_CHARSET.includes(ch),
        `문자셋 밖 문자 발견: ${ch} (code=${code})`
      );
    }
    assert.ok(!/[0O1IL]/.test(code), `혼동 문자 포함: ${code}`);
  }
});

test("generateReferralCode: random 함수를 주입하면 결정적으로 같은 코드를 만든다", () => {
  const fixed = () => 0; // 항상 0번째 문자를 고른다
  const code = generateReferralCode(fixed);
  assert.equal(code, REFERRAL_CODE_CHARSET[0].repeat(REFERRAL_CODE_LENGTH));
});

test("isValidReferralCodeFormat: 생성기가 만든 코드는 항상 유효하다", () => {
  for (let i = 0; i < 50; i++) {
    assert.equal(isValidReferralCodeFormat(generateReferralCode()), true);
  }
});

test("isValidReferralCodeFormat: 길이 5는 거부(6 미만)", () => {
  assert.equal(isValidReferralCodeFormat("ABCDE"), false);
});

test("isValidReferralCodeFormat: 길이 9는 거부(8 초과)", () => {
  assert.equal(isValidReferralCodeFormat("ABCDEFGHJ"), false);
});

test("isValidReferralCodeFormat: 길이 6~8은 허용 문자셋일 때 통과", () => {
  assert.equal(isValidReferralCodeFormat("ABCDEF"), true);
  assert.equal(isValidReferralCodeFormat("ABCDEFGH"), true);
});

test("isValidReferralCodeFormat: 혼동 문자(0/O/1/I/L)가 섞이면 거부", () => {
  assert.equal(isValidReferralCodeFormat("ABCDE0"), false);
  assert.equal(isValidReferralCodeFormat("ABCDEO"), false);
  assert.equal(isValidReferralCodeFormat("ABCDE1"), false);
  assert.equal(isValidReferralCodeFormat("ABCDEI"), false);
  assert.equal(isValidReferralCodeFormat("ABCDEL"), false);
});

test("isValidReferralCodeFormat: 소문자는 거부(대문자 전용 문자셋)", () => {
  assert.equal(isValidReferralCodeFormat("abcdef"), false);
});
