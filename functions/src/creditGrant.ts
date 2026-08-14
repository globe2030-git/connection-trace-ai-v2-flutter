/**
 * 무료 크레딧(bonusCredits) 지급 검증 — Firestore와 무관한 순수 함수만 둔다
 * (2026-08-14, ADMIN-VULN-002).
 *
 * 왜 순수 함수로 분리했나: `grantBonusCredits`의 원래 검증은 "0이 아닌 유한
 * 숫자"만 확인했다 — 상한도, 멱등성도, 감사 기록도 없었다. Firestore
 * 트랜잭션 안에 검증 로직을 섞어 두면 `node --test`로 경계값을 확인할 방법이
 * 없어(에뮬레이터 없이는 트랜잭션을 실행할 수 없다) 이 파일로 분리했다.
 */

/** 1회 지급/회수 상한. 관리자 화면 단일 조작 실수/오남용 방지용 기술적
 * 안전장치 — 사업적 무료횟수 정책과 무관하다. */
export const MAX_GRANT_PER_CALL = 100;

/** 결과 잔액 상한. 이 필드(`users/{uid}.aiUsage.bonusCredits`)는 향후 IAP
 * 충전 크레딧과 공유될 총지갑이 될 예정이라(설계 의도,
 * `lib/core/services/ai_usage_service.dart` UI 참고) 정상적인 대량 충전을
 * 막지 않도록 비상식적 값만 거르는 넉넉한 상한이다. 무료횟수 정책(사업적
 * 결정)과 혼동하지 말 것. */
export const MAX_BONUS_BALANCE = 100000;

export type GrantAmountResult =
  | {ok: true; amount: number}
  | {ok: false; error: string};

/**
 * 지급/회수 금액을 검증한다. `currentBalance`는 지급 전 현재 잔액(음수 아님을
 * 전제)이다.
 *
 * 통과 조건:
 * - `Number.isSafeInteger(amount)`이고 `amount !== 0`
 * - `Math.abs(amount) <= MAX_GRANT_PER_CALL`
 * - `currentBalance + amount <= MAX_BONUS_BALANCE`
 *   (음수 지급(회수)은 잔액을 낮추므로 이 조건에 사실상 걸리지 않는다 —
 *   회수 후 0 미만 클램프는 이 함수의 책임이 아니라 호출부의 책임이다.)
 */
export function validateGrantAmount(
  amount: unknown,
  currentBalance: number,
): GrantAmountResult {
  if (!Number.isSafeInteger(amount) || amount === 0) {
    return {ok: false, error: "지급할 회차는 0이 아닌 안전한 정수여야 합니다."};
  }
  const n = amount as number;
  if (Math.abs(n) > MAX_GRANT_PER_CALL) {
    return {
      ok: false,
      error: `1회 지급/회수는 ${MAX_GRANT_PER_CALL}회를 넘을 수 없습니다.`,
    };
  }
  const nextBalance = currentBalance + n;
  if (nextBalance > MAX_BONUS_BALANCE) {
    return {
      ok: false,
      error: `지급 후 잔액이 상한(${MAX_BONUS_BALANCE}회)을 넘습니다.`,
    };
  }
  return {ok: true, amount: n};
}

export type GrantMetadataResult = {ok: true} | {ok: false; error: string};

/**
 * 지급 사유(`reason`)와 멱등성 키(`operationId`)가 비어있지 않은 문자열인지
 * 검사한다. 둘 다 필수 — reason이 없으면 나중에 "왜 줬는지" 감사가 불가능하고,
 * operationId가 없으면 재시도/중복 클릭을 구분할 수 없다.
 */
export function validateGrantMetadata(
  reason: unknown,
  operationId: unknown,
): GrantMetadataResult {
  if (typeof reason !== "string" || reason.trim().length === 0) {
    return {ok: false, error: "지급 사유(reason)를 입력해 주세요."};
  }
  if (typeof operationId !== "string" || operationId.trim().length === 0) {
    return {ok: false, error: "operationId가 필요합니다."};
  }
  return {ok: true};
}
