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
  adminSessionExpiresAt,
  canExtendAdminSession,
  checkAdminSession,
  nextAdminSessionAfterHeartbeat,
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

// ─────────────────────────────────────────────────────────────────────────
// 2단계 — rules 에 건네는 만료 시각과 하트비트 (2026-09-05)
// ─────────────────────────────────────────────────────────────────────────

test("⭐ 평소에는 유휴 20분이 먼저 온다 — 그때가 만료다", () => {
  const s = freshSession();

  assert.equal(
    adminSessionExpiresAt(s),
    NOW + ADMIN_IDLE_TIMEOUT_MS,
    "인증 직후에는 12시간보다 20분이 훨씬 가깝다",
  );
});

test("⭐ 11시간 50분째 활동 중이면 절대 상한이 먼저 온다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - (ADMIN_SESSION_MAX_AGE_MS - 10 * 60 * 1000),
    lastActiveAt: NOW, // 방금까지 일하고 있었다
  };

  assert.equal(
    adminSessionExpiresAt(s),
    NOW + 10 * 60 * 1000,
    "남은 10분이 답이다 — 활동해도 상한 너머로는 못 간다",
  );
});

test("🚨 만료 시각은 둘 중 이른 쪽이다 — 늦은 쪽을 고르면 상한이 새어 나간다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - ADMIN_SESSION_MAX_AGE_MS + 1000,
    lastActiveAt: NOW,
  };

  assert.ok(
    adminSessionExpiresAt(s) < NOW + ADMIN_IDLE_TIMEOUT_MS,
    "유휴 쪽(20분)을 골랐다면 상한을 19분 넘겨 살아 있게 된다",
  );
});

test("⭐ 만료 시각과 checkAdminSession 의 판정이 어긋나지 않는다", () => {
  const s = freshSession(NOW - 5 * 60 * 1000);
  const expiresAt = adminSessionExpiresAt(s);

  assert.equal(checkAdminSession(s, expiresAt - 1).ok, true, "1ms 전에는 살아 있다");
  assert.equal(checkAdminSession(s, expiresAt).ok, false, "그 시각에는 죽는다");
});

test("하트비트는 활동 시각만 민다", () => {
  const s = freshSession(NOW - 5 * 60 * 1000);

  const next = nextAdminSessionAfterHeartbeat(s, NOW);

  assert.equal(next?.lastActiveAt, NOW);
  assert.equal(
    next?.otpVerifiedAt,
    s.otpVerifiedAt,
    "🚨 인증 시각을 함께 밀면 절대 상한이 없는 것과 같아진다",
  );
});

test("🚨 죽은 세션에 하트비트를 보내면 null 이다 — 되살아나지 않는다", () => {
  const dead = freshSession(NOW - ADMIN_IDLE_TIMEOUT_MS - 1);

  assert.equal(nextAdminSessionAfterHeartbeat(dead, NOW), null);
});

test("🚨 절대 상한이 지난 세션도 하트비트로 연장되지 않는다", () => {
  const s: AdminSession = {
    otpVerifiedAt: NOW - ADMIN_SESSION_MAX_AGE_MS,
    lastActiveAt: NOW,
  };

  assert.equal(nextAdminSessionAfterHeartbeat(s, NOW), null);
});

test("🚨 세션이 없으면 하트비트로 만들 수 없다", () => {
  assert.equal(nextAdminSessionAfterHeartbeat(null, NOW), null);
});

test("⭐ 하트비트를 반복해도 절대 상한은 그대로다 — 12시간 뒤 반드시 끊긴다", () => {
  let s: AdminSession | null = freshSession(NOW);
  const started = NOW;

  // 10분마다 하트비트를 12시간 넘게 보낸다
  for (let t = NOW; t <= NOW + ADMIN_SESSION_MAX_AGE_MS; t += 10 * 60 * 1000) {
    const next: AdminSession | null = nextAdminSessionAfterHeartbeat(s, t);
    if (next === null) {
      assert.ok(
        t - started >= ADMIN_SESSION_MAX_AGE_MS,
        `12시간 전에 끊겼다 (${(t - started) / 60000}분)`,
      );
      return;
    }
    s = next;
  }

  assert.fail("12시간이 지나도 안 끊겼다 — 상한이 동작하지 않는다");
});
