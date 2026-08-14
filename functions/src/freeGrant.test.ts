/**
 * freeGrant.ts 단위 테스트. walletCredits.test.ts와 같은 스타일(Node 내장
 * 테스트 러너). 목적은 "이미 지급된 계정은 두 번 지급되지 않는다"(멱등)와
 * "레거시 bonusCredits가 정확히 1회만 free로 흡수된다"를 코드로 증명하는
 * 것 — U2 인수 기준의 핵심.
 * 실행: `npm run build && node --test lib/freeGrant.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {DEFAULT_FREE_CREDITS, planFreeGrant} from "./freeGrant";

test("planFreeGrant: 이미 지급됐으면 재호출해도 잔액이 그대로다(멱등)", () => {
  const plan = planFreeGrant({
    alreadyGranted: true,
    currentFreeBalance: 7,
    legacyBonusCredits: 3,
    configFreeCredits: 10,
  });
  assert.equal(plan.shouldGrant, false);
  assert.equal(plan.newFreeBalance, 7);
  assert.equal(plan.grantedAmount, 0);
  assert.equal(plan.carryOver, 0);
});

test("planFreeGrant: 최초 지급 — configFreeCredits만큼 지급, 레거시 없음", () => {
  const plan = planFreeGrant({
    alreadyGranted: false,
    currentFreeBalance: 0,
    legacyBonusCredits: 0,
    configFreeCredits: 10,
  });
  assert.equal(plan.shouldGrant, true);
  assert.equal(plan.newFreeBalance, 10);
  assert.equal(plan.grantedAmount, 10);
  assert.equal(plan.carryOver, 0);
});

test("planFreeGrant: 레거시 bonusCredits가 있으면 free로 함께 이월(1회성)", () => {
  const plan = planFreeGrant({
    alreadyGranted: false,
    currentFreeBalance: 0,
    legacyBonusCredits: 4,
    configFreeCredits: 10,
  });
  assert.equal(plan.shouldGrant, true);
  assert.equal(plan.newFreeBalance, 14);
  assert.equal(plan.grantedAmount, 10);
  assert.equal(plan.carryOver, 4);
});

test("planFreeGrant: currentFreeBalance가 0이 아니어도(방어적 상황) 누적된다", () => {
  const plan = planFreeGrant({
    alreadyGranted: false,
    currentFreeBalance: 2,
    legacyBonusCredits: 0,
    configFreeCredits: 10,
  });
  assert.equal(plan.newFreeBalance, 12);
});

test("planFreeGrant: 음수 입력은 0으로 방어(잔액이 깎이는 사고 방지)", () => {
  const plan = planFreeGrant({
    alreadyGranted: false,
    currentFreeBalance: -5,
    legacyBonusCredits: -3,
    configFreeCredits: -10,
  });
  assert.equal(plan.newFreeBalance, 0);
  assert.equal(plan.grantedAmount, 0);
  assert.equal(plan.carryOver, 0);
});

test("DEFAULT_FREE_CREDITS는 확정값 10(monetization-referral-implementation-spec-2026-08-14.md §1)", () => {
  assert.equal(DEFAULT_FREE_CREDITS, 10);
});
