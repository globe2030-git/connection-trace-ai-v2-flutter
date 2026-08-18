/**
 * purchases.ts 단위 테스트. deviceLedger.test.ts/walletCredits.test.ts와
 * 같은 스타일(Node 내장 테스트 러너). 실제 영수증 검증은 이 파일에 없으므로
 * (U7 뼈대 라운드 범위 밖) 검증 대상은 오직 "상품ID→크레딧 매핑 조회"와
 * 요청 형태 검증 순수 함수뿐이다.
 * 실행: `npm run build && node --test lib/purchases.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  BillingTierRaw,
  isNonEmptyString,
  isValidIapPlatform,
  isValidTransactionId,
  resolveTierByProductId,
} from "./purchases";

// ---- isValidIapPlatform ----

test("isValidIapPlatform: 'ios'/'android'만 true", () => {
  assert.equal(isValidIapPlatform("ios"), true);
  assert.equal(isValidIapPlatform("android"), true);
});

test("isValidIapPlatform: 그 외 값은 false", () => {
  assert.equal(isValidIapPlatform("web"), false);
  assert.equal(isValidIapPlatform(""), false);
  assert.equal(isValidIapPlatform(undefined), false);
  assert.equal(isValidIapPlatform(123), false);
});

// ---- isValidTransactionId ----

test("isValidTransactionId: 일반 문자열은 통과", () => {
  assert.equal(isValidTransactionId("2000000123456789"), true);
});

test("isValidTransactionId: 빈 문자열/공백만 있는 문자열은 거부", () => {
  assert.equal(isValidTransactionId(""), false);
  assert.equal(isValidTransactionId("   "), false);
});

test("isValidTransactionId: 300자 초과는 거부", () => {
  assert.equal(isValidTransactionId("a".repeat(301)), false);
});

test("isValidTransactionId: '/'가 들어가면 거부(문서 하위경로 오인 방지)", () => {
  assert.equal(isValidTransactionId("abc/def"), false);
});

test("isValidTransactionId: 문자열이 아니면 거부", () => {
  assert.equal(isValidTransactionId(12345), false);
  assert.equal(isValidTransactionId(null), false);
  assert.equal(isValidTransactionId(undefined), false);
});

// ---- isNonEmptyString ----

test("isNonEmptyString: 공백 아닌 문자열만 true", () => {
  assert.equal(isNonEmptyString("credit_1000_placeholder"), true);
  assert.equal(isNonEmptyString(""), false);
  assert.equal(isNonEmptyString("   "), false);
  assert.equal(isNonEmptyString(undefined), false);
});

// ---- resolveTierByProductId ----

const TIERS: BillingTierRaw[] = [
  {priceKrw: 1000, credits: 10, active: true, productId: "credit_1000_placeholder"},
  {priceKrw: 3000, credits: 33, active: true, productId: "credit_3000_placeholder"},
  {priceKrw: 5000, credits: 60, active: false, productId: "credit_5000_placeholder"},
  {priceKrw: 10000, credits: 0, active: true, productId: "credit_10000_placeholder"},
  {priceKrw: 30000, active: false},
];

test("resolveTierByProductId: 활성+회수 있는 티어는 매칭 성공", () => {
  const result = resolveTierByProductId(TIERS, "credit_1000_placeholder");
  assert.deepEqual(result, {ok: true, priceKrw: 1000, credits: 10});
});

test("resolveTierByProductId: productId가 없으면 실패", () => {
  const result = resolveTierByProductId(TIERS, "");
  assert.equal(result.ok, false);
});

test("resolveTierByProductId: 매칭되는 productId가 없으면 실패", () => {
  const result = resolveTierByProductId(TIERS, "credit_9999_placeholder");
  assert.equal(result.ok, false);
});

test("resolveTierByProductId: active:false인 티어는 매칭하지 않는다", () => {
  const result = resolveTierByProductId(TIERS, "credit_5000_placeholder");
  assert.equal(result.ok, false);
});

test("resolveTierByProductId: credits가 0이하인 티어는 매칭하지 않는다", () => {
  const result = resolveTierByProductId(TIERS, "credit_10000_placeholder");
  assert.equal(result.ok, false);
});

test("resolveTierByProductId: tiers가 undefined여도 예외 없이 실패로 처리", () => {
  const result = resolveTierByProductId(undefined, "credit_1000_placeholder");
  assert.equal(result.ok, false);
});
