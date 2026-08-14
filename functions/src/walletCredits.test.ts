/**
 * walletCredits.ts 단위 테스트. usageReset.test.ts와 같은 스타일(Node 내장
 * 테스트 러너). 목적은 "reset 모드가 100% 그대로인지"와 "wallet 분기가
 * 스펙(§3-2)대로 동작하는지"를 코드로 증명하는 것 — U1 인수 기준의 핵심.
 * 실행: `npm run build && node --test lib/walletCredits.test.js`
 * (`npm test`가 usageReset과 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  consumeWalletCredit,
  resolveBillingModel,
  WalletExhaustedError,
} from "./walletCredits";

// ---- resolveBillingModel ----

test("resolveBillingModel: 문서 자체가 없으면(undefined) 'reset'으로 폴백", () => {
  assert.equal(resolveBillingModel(undefined), "reset");
});

test("resolveBillingModel: 문서는 있지만 model 필드가 없으면 'reset'으로 폴백", () => {
  assert.equal(resolveBillingModel({freeCredits: 10, tiers: []}), "reset");
});

test("resolveBillingModel: model이 'reset'이면 그대로 'reset'", () => {
  assert.equal(resolveBillingModel({model: "reset"}), "reset");
});

test("resolveBillingModel: model이 'wallet'이면 'wallet'", () => {
  assert.equal(resolveBillingModel({model: "wallet"}), "wallet");
});

test("resolveBillingModel: model이 알 수 없는 값이면 'reset'으로 폴백(안전한 쪽)", () => {
  assert.equal(resolveBillingModel({model: "typo"}), "reset");
  assert.equal(resolveBillingModel({model: null}), "reset");
  assert.equal(resolveBillingModel({model: 123}), "reset");
});

// ---- consumeWalletCredit ----

test("consumeWalletCredit: free>0이면 free만 깎이고 paid는 그대로(무료 우선 소진)", () => {
  const result = consumeWalletCredit({free: 3, paid: 5});
  assert.deepEqual(result, {free: 2, paid: 5});
});

test("consumeWalletCredit: free=1이어도 free부터 깎는다(경계값)", () => {
  const result = consumeWalletCredit({free: 1, paid: 5});
  assert.deepEqual(result, {free: 0, paid: 5});
});

test("consumeWalletCredit: free=0, paid>0이면 paid만 깎임", () => {
  const result = consumeWalletCredit({free: 0, paid: 5});
  assert.deepEqual(result, {free: 0, paid: 4});
});

test("consumeWalletCredit: free=0, paid=0이면 WalletExhaustedError를 던진다", () => {
  assert.throws(() => consumeWalletCredit({free: 0, paid: 0}), WalletExhaustedError);
});

test("consumeWalletCredit: free/paid가 음수여도(방어적으로) 합이 0 이하면 예외", () => {
  assert.throws(() => consumeWalletCredit({free: -1, paid: 1}), WalletExhaustedError);
});

test("consumeWalletCredit: free/paid가 undefined면 0으로 취급", () => {
  assert.throws(
    () => consumeWalletCredit({free: undefined as unknown as number, paid: undefined as unknown as number}),
    WalletExhaustedError
  );
});
