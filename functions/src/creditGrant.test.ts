/**
 * creditGrant.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를 쓴다 —
 * usageReset.test.ts와 같은 패턴. 실행:
 * `npm run build && node --test lib/creditGrant.test.js`
 * (package.json의 `npm test`가 이 파일도 포함하도록 갱신돼 있다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  validateGrantAmount,
  validateGrantMetadata,
  MAX_GRANT_PER_CALL,
  MAX_BONUS_BALANCE,
} from "./creditGrant";

// ── validateGrantAmount ──────────────────────────────────────────────

test("0은 거부한다", () => {
  const r = validateGrantAmount(0, 0);
  assert.equal(r.ok, false);
});

test("소수는 거부한다(정수가 아님)", () => {
  const r = validateGrantAmount(1.5, 0);
  assert.equal(r.ok, false);
});

test("NaN은 거부한다", () => {
  const r = validateGrantAmount(NaN, 0);
  assert.equal(r.ok, false);
});

test("Infinity는 거부한다(안전한 정수가 아님)", () => {
  const r = validateGrantAmount(Infinity, 0);
  assert.equal(r.ok, false);
});

test("Number.MAX_SAFE_INTEGER를 넘는 값은 거부한다", () => {
  const r = validateGrantAmount(Number.MAX_SAFE_INTEGER + 10, 0);
  assert.equal(r.ok, false);
});

test("문자열 등 숫자가 아닌 타입은 거부한다", () => {
  const r = validateGrantAmount("5" as unknown, 0);
  assert.equal(r.ok, false);
});

test("1회 지급 상한을 초과하면 거부한다", () => {
  const r = validateGrantAmount(MAX_GRANT_PER_CALL + 1, 0);
  assert.equal(r.ok, false);
});

test("1회 지급 상한에 정확히 걸치면 허용한다(경계값)", () => {
  const r = validateGrantAmount(MAX_GRANT_PER_CALL, 0);
  assert.deepEqual(r, {ok: true, amount: MAX_GRANT_PER_CALL});
});

test("1회 회수(음수) 상한도 절댓값 기준으로 검사한다", () => {
  const overRecall = validateGrantAmount(-(MAX_GRANT_PER_CALL + 1), 1000);
  assert.equal(overRecall.ok, false);
  const okRecall = validateGrantAmount(-MAX_GRANT_PER_CALL, 1000);
  assert.deepEqual(okRecall, {ok: true, amount: -MAX_GRANT_PER_CALL});
});

test("결과 잔액이 상한을 넘으면 거부한다", () => {
  const r = validateGrantAmount(50, MAX_BONUS_BALANCE - 10);
  assert.equal(r.ok, false);
});

test("결과 잔액이 상한에 정확히 걸치면 허용한다(경계값)", () => {
  const r = validateGrantAmount(10, MAX_BONUS_BALANCE - 10);
  assert.deepEqual(r, {ok: true, amount: 10});
});

test("정상 범위의 지급은 허용한다", () => {
  const r = validateGrantAmount(5, 3);
  assert.deepEqual(r, {ok: true, amount: 5});
});

// ── validateGrantMetadata ────────────────────────────────────────────

test("reason이 없으면 거부한다", () => {
  const r = validateGrantMetadata(undefined, "op-1");
  assert.equal(r.ok, false);
});

test("reason이 공백뿐이면 거부한다", () => {
  const r = validateGrantMetadata("   ", "op-1");
  assert.equal(r.ok, false);
});

test("operationId가 없으면 거부한다", () => {
  const r = validateGrantMetadata("테스터 보상", undefined);
  assert.equal(r.ok, false);
});

test("operationId가 빈 문자열이면 거부한다", () => {
  const r = validateGrantMetadata("테스터 보상", "");
  assert.equal(r.ok, false);
});

test("reason·operationId가 모두 있으면 허용한다", () => {
  const r = validateGrantMetadata("테스터 보상", "op-1234");
  assert.deepEqual(r, {ok: true});
});
