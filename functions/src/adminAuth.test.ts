/**
 * adminAuth.ts 단위 테스트. phoneOtp.test.ts와 같은 스타일(Node 내장 러너).
 *
 * 🚨 **여기서 확인하는 것이 「관리자 문이 언제 닫히는가」의 전부다.**
 * 20분·12시간 경계가 실제로 도는지를 실제 시계 없이 증명한다.
 *
 * ⚠️ 시각은 전부 인자로 넣는다 — 진짜 시계를 기다리면 20분짜리 만료를
 * 확인할 수 없고, 무엇보다 "서버가 판정한다"가 코드로 안 보인다.
 *
 * 실행: `npm run build && node --test lib/adminAuth.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  ADMIN_IDLE_TIMEOUT_MS,
  ADMIN_SESSION_MAX_AGE_MS,
  AdminSession,
  adminSessionMessage,
  canExtendAdminSession,
  checkAdminSession,
} from "./adminAuth";

const NOW = 1_800_000_000_000;

/** 방금 인증하고 방금 활동한, 완전히 건강한 세션. */
function freshSession(at: number = NOW): AdminSession {
  return {otpVerifiedAt: at, lastActiveAt: at};
}

test("방금 인증한 세션은 통과한다", () => {
  const r = checkAdminSession(freshSession(), NOW);
  assert.equal(r.ok, true);
});

test("🚨 세션이 없으면 통과하지 않는다 — 기본값이 「닫힘」이다", () => {
  const r = checkAdminSession(null, NOW);
  assert.deepEqual(r, {ok: false, reason: "no-session"});
});

test("유휴 19분 59초는 아직 살아 있다", () => {
  const s = freshSession(NOW - (ADMIN_IDLE_TIMEOUT_MS - 1000));
  assert.equal(checkAdminSession(s, NOW).ok, true);
});

test("⭐ 유휴 정확히 20분이면 끊긴다 — 경계는 닫는 쪽이다", () => {
  const s = freshSession(NOW - ADMIN_IDLE_TIMEOUT_MS);
  assert.deepEqual(checkAdminSession(s, NOW), {
    ok: false,
    reason: "idle-expired",
  });
});

test("활동을 계속해도 12시간이 지나면 끊긴다 — 절대 상한", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - ADMIN_SESSION_MAX_AGE_MS,
    lastActiveAt: NOW, // 방금까지 일하고 있었다
  };
  assert.deepEqual(checkAdminSession(s, NOW), {
    ok: false,
    reason: "max-age-exceeded",
  });
});

test("11시간 59분은 아직 살아 있다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - (ADMIN_SESSION_MAX_AGE_MS - 60_000),
    lastActiveAt: NOW,
  };
  assert.equal(checkAdminSession(s, NOW).ok, true);
});

test("⭐ 둘 다 만료면 「유휴」로 보고한다 — 방금 실제로 일어난 일이다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - ADMIN_SESSION_MAX_AGE_MS - 60_000,
    lastActiveAt: NOW - ADMIN_IDLE_TIMEOUT_MS - 60_000,
  };
  assert.deepEqual(checkAdminSession(s, NOW), {
    ok: false,
    reason: "idle-expired",
  });
});

test("살아 있으면 남은 시간을 함께 준다 — 화면이 미리 알려 줄 수 있어야 한다", () => {
  const s = freshSession(NOW - 5 * 60 * 1000); // 5분 전
  const r = checkAdminSession(s, NOW);
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.idleMsLeft, 15 * 60 * 1000);
  assert.equal(r.maxAgeMsLeft, ADMIN_SESSION_MAX_AGE_MS - 5 * 60 * 1000);
});

test("🚨 죽은 세션은 하트비트로 되살아나지 않는다", () => {
  const dead = freshSession(NOW - ADMIN_IDLE_TIMEOUT_MS - 1);
  assert.equal(canExtendAdminSession(dead, NOW), false);
});

test("🚨 절대 상한이 지난 세션도 하트비트로 연장되지 않는다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - ADMIN_SESSION_MAX_AGE_MS,
    lastActiveAt: NOW,
  };
  assert.equal(
    canExtendAdminSession(s, NOW),
    false,
    "하트비트가 상한을 밀어낼 수 있으면 상한이 없는 것과 같다",
  );
});

test("🚨 세션이 없으면 연장도 안 된다 — 하트비트로 세션을 만들 수 없다", () => {
  assert.equal(canExtendAdminSession(null, NOW), false);
});

test("살아 있는 세션은 연장된다", () => {
  assert.equal(canExtendAdminSession(freshSession(), NOW), true);
});

test("만료 사유마다 다음에 할 일을 말해 준다", () => {
  for (const reason of
    ["no-session", "idle-expired", "max-age-exceeded"] as const) {
    const msg = adminSessionMessage(reason);
    assert.ok(
      msg.includes("휴대폰 인증"),
      `${reason}: 무엇을 하면 되는지가 문구에 있어야 한다 — "${msg}"`,
    );
  }
});

test("유휴 만료 문구는 20분이라고 말한다 — 상수와 문구가 갈라지면 안 된다", () => {
  const minutes = ADMIN_IDLE_TIMEOUT_MS / 60000;
  assert.ok(adminSessionMessage("idle-expired").includes(`${minutes}분`));
});

test("절대 상한 문구는 12시간이라고 말한다", () => {
  const hours = ADMIN_SESSION_MAX_AGE_MS / 3_600_000;
  assert.ok(adminSessionMessage("max-age-exceeded").includes(`${hours}시간`));
});
