/**
 * 관리자 세션 판정 — **살아 있는 세션인가**.
 *
 * ## 왜 이 파일이 따로 있나
 *
 * 관리자 콘솔은 지금 **구글 계정 로그인 + 이메일 화이트리스트** 하나로만
 * 잠겨 있다. 계정 하나가 뚫리면 전부 열리고, 세션이 끊기지도 않는다
 * (`refresh token`이 계속 갱신되므로 브라우저를 닫아도 유지된다).
 *
 * 그래서 2차 인증(휴대폰)과 만료를 붙인다. 이 파일은 그중 **판정만** 한다 —
 * 문자 발송도, Firestore 읽기도 하지 않는다.
 *
 * ⭐ **`phoneOtp.ts`와 같은 모양이다**: 순수 함수만 두고 부수효과는 `index.ts`가
 * 맡는다. 그래야 실제 문자를 보내지 않고도 만료 경계를 테스트할 수 있다.
 *
 * ## 🚨 만료 계산이 **여기 한 곳에만** 있어야 한다
 *
 * 처음에는 클라이언트가 `lastActiveAt`을 직접 쓰게 하려 했다. 그러면
 * `firestore.rules`도 "지금 세션이 살아 있나"를 스스로 판정해야 하고,
 * **만료 계산이 rules와 TypeScript 두 곳에 생긴다** — 관리자 이메일 목록이
 * 두 곳에 있어 사고가 났던 것(ADMIN-VULN-001)과 **정확히 같은 구조**다.
 *
 * 그래서 `adminSessions/{uid}`는 rules에서 **전면 차단**하고 Admin SDK로만
 * 쓴다. 하트비트도 Callable이다. 대가는 활동 중 함수 호출이 하나 느는 것인데,
 * 관리자가 두엇이므로 무시할 수준이다(⚠️ 이건 **계산이다 — 실측이 아니다**).
 *
 * 📌 **덤으로 하나 더 막힌다**: 클라이언트가 못 쓰므로 **죽은 세션을
 * 하트비트로 되살리는 경로**가 원천적으로 없다.
 *
 * 설계 배경: `docs/planning/specs/관리자-인증-강화와-명함-조회-설계-2026-09-05.md`
 */

/**
 * **유휴 만료** — 이만큼 활동이 없으면 세션이 죽는다. (2026-09-05 사용자 확정)
 *
 * 🚨 **이 값이 막는 것과 못 막는 것을 정확히 알아야 한다.**
 *
 * ```
 * 막는 것    자리를 비운 브라우저 · 잠그지 않은 화면 · 공용 PC
 * 못 막는 것 🚨 세션을 쥔 공격자 — 공격자도 하트비트를 보낸다
 * ```
 *
 * ⚠️ **어떤 구현도 후자를 못 막는다.** 후자를 잡는 것은 유휴 만료가 아니라
 * **조회 기록**이다(설계 문서 §3-4).
 */
export const ADMIN_IDLE_TIMEOUT_MS = 20 * 60 * 1000;

/**
 * **절대 상한** — 활동이 계속돼도 이만큼 지나면 다시 인증한다.
 *
 * 🚨 **이것이 없으면 탭 하나를 열어 둔 채 영원히 산다.** 유휴 만료만으로는
 * 「자리를 비운 브라우저」는 막아도 **「계속 열어 둔 브라우저」는 못 막는다.**
 */
export const ADMIN_SESSION_MAX_AGE_MS = 12 * 60 * 60 * 1000;

/** `adminSessions/{uid}` 문서. 시각은 전부 epoch 밀리초다. */
export interface AdminSession {
  /** 휴대폰 2차 인증을 통과한 시각. 절대 상한의 기준점이다. */
  otpVerifiedAt: number;
  /** 마지막 활동 시각. 유휴 만료의 기준점이다. */
  lastActiveAt: number;
}

export type AdminSessionState =
  | {ok: true; idleMsLeft: number; maxAgeMsLeft: number}
  | {ok: false; reason: "no-session" | "idle-expired" | "max-age-exceeded"};

/**
 * 이 세션으로 관리자 작업을 해도 되나.
 *
 * ## 판정 순서 — **유휴를 절대 상한보다 먼저 본다**
 *
 * 둘 다 만료됐을 때 어느 쪽을 말해 줄지의 문제다. `verifyOtp`가
 * *"만료를 틀린 횟수보다 먼저 본다"*고 정한 것과 같은 결로, **방금 실제로
 * 일어난 일**을 말해 주는 쪽을 고른다.
 *
 * ```
 * 11시 59분까지 일하다 자리를 비우고 12시 30분에 돌아왔다
 *   → 유휴(31분)도, 절대 상한(12시간)도 넘었다
 *   → 이용자에게 일어난 일은 **"자리를 비웠다"** 다
 * ```
 *
 * 📌 계속 활동했다면 유휴는 애초에 안 걸리므로, 그때는 절대 상한이 정확히
 * 보고된다. **두 경우 모두 맞는 이유를 말한다.**
 *
 * ⚠️ **`ok`일 때 남은 시간을 함께 돌려준다** — 화면이 *"5분 뒤 만료됩니다"*
 * 를 말할 수 있어야 한다. 아무 말 없이 끊기면 작성 중이던 답변이 날아간다.
 */
export function checkAdminSession(
  session: AdminSession | null,
  now: number,
): AdminSessionState {
  if (session === null) return {ok: false, reason: "no-session"};

  const idleFor = now - session.lastActiveAt;
  if (idleFor >= ADMIN_IDLE_TIMEOUT_MS) {
    return {ok: false, reason: "idle-expired"};
  }

  const age = now - session.otpVerifiedAt;
  if (age >= ADMIN_SESSION_MAX_AGE_MS) {
    return {ok: false, reason: "max-age-exceeded"};
  }

  return {
    ok: true,
    idleMsLeft: ADMIN_IDLE_TIMEOUT_MS - idleFor,
    maxAgeMsLeft: ADMIN_SESSION_MAX_AGE_MS - age,
  };
}

/**
 * 하트비트로 세션을 연장해도 되나.
 *
 * 🚨 **죽은 세션은 하트비트로 되살아나지 않는다.** 이 함수가 그것을 막는
 * 유일한 자리다 — 그래서 [checkAdminSession]을 그대로 다시 쓴다. 조건을
 * 따로 적으면 두 판정이 갈라진다.
 *
 * 📌 **절대 상한이 지난 세션도 연장되지 않는다.** 하트비트가 상한을 밀어낼
 * 수 있으면 상한이 없는 것과 같다.
 */
export function canExtendAdminSession(
  session: AdminSession | null,
  now: number,
): boolean {
  return checkAdminSession(session, now).ok;
}

/**
 * 이용자에게 보여 줄 만료 사유. **다음에 무엇을 하면 되는지까지 말한다.**
 *
 * ⚠️ *"세션이 만료되었습니다"* 만으로는 이용자가 무엇을 해야 할지 모른다.
 * 셋 다 결론은 「다시 인증」이지만, **왜 끊겼는지를 알아야 다음에 안 겪는다.**
 */
export function adminSessionMessage(
  reason: "no-session" | "idle-expired" | "max-age-exceeded",
): string {
  switch (reason) {
  case "no-session":
    return "휴대폰 인증이 필요합니다.";
  case "idle-expired":
    return "20분 동안 사용하지 않아 로그아웃되었습니다. 휴대폰 인증을 다시 해 주세요.";
  case "max-age-exceeded":
    return "인증한 지 12시간이 지났습니다. 휴대폰 인증을 다시 해 주세요.";
  }
}
