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
  DEVICE_LEDGER_RETENTION_MS,
  DEVICE_TRIAL_GRANT_CAP,
  canGrantTrialToDevice,
  deviceHash,
  deviceLedgerExpiresAtMs,
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

// ---- 보관 기간(TTL) — 2026-09-05 ----
//
// 🚨 **여기서 잠그는 것은 「계산」뿐이다.** 실제로 `expiresAt` 을 문서에 심는
// 곳은 `index.ts` 의 `bootstrapAccount` 트랜잭션인데, **`index.ts` 를
// import 하는 테스트가 0건**이라 그 줄은 어떤 검사도 덮지 않는다
// (`grep -l 'from "./index"' functions/src/*.test.ts` → 0).
// 아래 검사를 다 지워도 그 줄은 안 깨지고, 그 줄을 지워도 아래는 안 깨진다.
// **모르는 채로 두지 않으려고 적어 둔다** — 그 자리는 실기기·서버 실물로만
// 확인된다.

test("보관 기간은 30일이다 (2026-09-05 globe2030님 결정)", () => {
  assert.equal(DEVICE_LEDGER_RETENTION_MS, 30 * 24 * 60 * 60 * 1000);
});

test("보관 기간은 phoneSendLedger 와 같은 30일이지만 상수는 따로다", () => {
  // 값이 같은 것은 우연이 아니라 같은 이유(탈퇴로 못 지우니 기간으로 지운다).
  // 다만 한쪽 정책이 바뀔 때 다른 쪽이 조용히 따라가면 안 되므로 상수를
  // 공유하지 않는다 — 이 검사는 "값이 같다"가 아니라 **"30일이다"**를 잠근다.
  assert.equal(DEVICE_LEDGER_RETENTION_MS / (24 * 60 * 60 * 1000), 30);
});

test("expiresAt: 쓰는 시각으로부터 30일 뒤다", () => {
  const now = 1_757_000_000_000;
  assert.equal(deviceLedgerExpiresAtMs(now), now + DEVICE_LEDGER_RETENTION_MS);
});

test("expiresAt: 쓸 때마다 다시 계산된다 — 미끄러지는 창(sliding window)", () => {
  // 🚨 「처음 생길 때만」이면 최초 지급 30일 뒤에 지워져 방어 구간이 실제로는
  //    더 짧아진다. phoneSendLedger 와 같은 쪽(쓸 때마다)으로 맞췄다.
  const first = deviceLedgerExpiresAtMs(1_757_000_000_000);
  const later = deviceLedgerExpiresAtMs(1_757_000_000_000 + 10 * 24 * 60 * 60 * 1000);
  assert.equal(later - first, 10 * 24 * 60 * 60 * 1000);
  assert.ok(later > first, "나중에 쓰면 파기 시각도 그만큼 뒤로 간다");
});

test("expiresAt: 과거를 넣어도 30일을 더한다 — 시계가 틀려도 음수 만료가 안 생긴다", () => {
  assert.equal(deviceLedgerExpiresAtMs(0), DEVICE_LEDGER_RETENTION_MS);
});
