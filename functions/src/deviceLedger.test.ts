/**
 * deviceLedger.ts 단위 테스트. walletCredits.test.ts/freeGrant.test.ts와
 * 같은 스타일(Node 내장 테스트 러너). 목적은 "해시 계산이 결정론적인지"와
 * "기기당 캡 판정이 정확한지"를 코드로 증명하는 것 — U5 인수 기준의 핵심.
 * 실행: `npm run build && node --test lib/deviceLedger.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  DEVICE_TRIAL_GRANT_CAP,
  canGrantTrialToDevice,
  deviceHash,
  isSelfReferralOnDevice,
  recordDeviceUsage,
} from "./deviceLedger";

// ---- deviceHash ----

test("deviceHash: 같은 입력·salt면 항상 같은 해시(결정론적)", () => {
  const a = deviceHash("raw-device-id-1", "salt-abc");
  const b = deviceHash("raw-device-id-1", "salt-abc");
  assert.equal(a, b);
});

test("deviceHash: salt가 다르면 다른 해시(무지개 테이블 방지)", () => {
  const a = deviceHash("raw-device-id-1", "salt-abc");
  const b = deviceHash("raw-device-id-1", "salt-xyz");
  assert.notEqual(a, b);
});

test("deviceHash: 다른 device id는 다른 해시", () => {
  const a = deviceHash("raw-device-id-1", "salt-abc");
  const b = deviceHash("raw-device-id-2", "salt-abc");
  assert.notEqual(a, b);
});

test("deviceHash: 64자 hex 다이제스트(SHA-256)를 반환한다", () => {
  const h = deviceHash("raw-device-id-1", "salt-abc");
  assert.match(h, /^[0-9a-f]{64}$/);
});

// ---- canGrantTrialToDevice ----

test("canGrantTrialToDevice: 캡은 1이다(설계 확정값)", () => {
  assert.equal(DEVICE_TRIAL_GRANT_CAP, 1);
});

test("canGrantTrialToDevice: 지급 이력이 없으면(0) 지급 가능", () => {
  assert.equal(canGrantTrialToDevice(0), true);
});

test("canGrantTrialToDevice: 캡(1)에 도달했으면 더 지급 불가", () => {
  assert.equal(canGrantTrialToDevice(1), false);
});

test("canGrantTrialToDevice: 캡을 초과했어도(방어적 케이스) 지급 불가", () => {
  assert.equal(canGrantTrialToDevice(5), false);
});

test("canGrantTrialToDevice: 음수·비정상값은 0으로 취급해 지급 가능", () => {
  assert.equal(canGrantTrialToDevice(-3), true);
  assert.equal(canGrantTrialToDevice(NaN), true);
});

// ---- recordDeviceUsage ----

test("recordDeviceUsage: 배열이 없으면 새 배열에 uid 하나만 담는다", () => {
  assert.deepEqual(recordDeviceUsage(undefined, "uid-1"), ["uid-1"]);
});

test("recordDeviceUsage: 기존 배열에 새 uid를 추가한다", () => {
  assert.deepEqual(recordDeviceUsage(["uid-1"], "uid-2"), ["uid-1", "uid-2"]);
});

test("recordDeviceUsage: 이미 있는 uid는 중복 추가하지 않는다", () => {
  assert.deepEqual(recordDeviceUsage(["uid-1", "uid-2"], "uid-1"), [
    "uid-1",
    "uid-2",
  ]);
});

// ---- isSelfReferralOnDevice ----

test("isSelfReferralOnDevice: 초대자 uid가 이 기기 이력에 없으면 false", () => {
  assert.equal(isSelfReferralOnDevice(["uid-1"], "uid-referrer"), false);
});

test("isSelfReferralOnDevice: 초대자 uid가 이 기기 이력에 있으면 true(자기초대)", () => {
  assert.equal(isSelfReferralOnDevice(["uid-1", "uid-referrer"], "uid-referrer"), true);
});

test("isSelfReferralOnDevice: 이력이 없는 기기(undefined)는 false", () => {
  assert.equal(isSelfReferralOnDevice(undefined, "uid-referrer"), false);
});
