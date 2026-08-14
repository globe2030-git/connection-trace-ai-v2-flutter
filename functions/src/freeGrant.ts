/**
 * 무료체험 크레딧 지급(가입 시 1회성) 판정만 떼어낸 순수 함수.
 *
 * 왜 순수 함수로 분리했나: walletCredits.ts/usageReset.ts와 같은 이유 —
 * `bootstrapAccount`(index.ts)는 Firestore 트랜잭션 객체에 강하게 묶여
 * 있어 그 안의 판정 로직만 따로 유닛테스트하기 어렵다. 이 파일은
 * "입력(현재 잔액/설정값) → 출력(다음 잔액 계획)"만 다루고 Firestore를
 * 전혀 모른다. 실제 읽기·쓰기(트랜잭션)는 index.ts에 남아 있고 이 파일의
 * 함수만 호출한다.
 *
 * 설계 근거: docs/planning/ai-credit-wallet-spec.md §3-1(멱등 알고리즘).
 */

/**
 * `config/billing.freeCredits`를 서버가 못 읽었을 때(문서 없음, 필드 없음,
 * 조회 실패)의 안전한 기본값.
 *
 * ⚠️ 반드시 이 값을 써야 한다 —
 * docs/planning/monetization-referral-implementation-spec-2026-08-14.md
 * §1에서 사용자가 2026-08-14에 확정한 "가입 체험 회차" 값이다(출시기념
 * 2배 체험, 안정기엔 5회로 환원 가능하도록 config로 뺀 것 — 그 config가
 * 비어 있을 때의 폴백이 바로 이 상수).
 */
export const DEFAULT_FREE_CREDITS = 10;

export interface FreeGrantInput {
  /** aiUsage.freeGrantedAt이 이미 있으면 true — 지급이 끝났다는 멱등 가드. */
  alreadyGranted: boolean;
  /** aiUsage.freeBalance ?? 0 */
  currentFreeBalance: number;
  /** aiUsage.bonusCredits ?? 0 — 레거시 필드, 1회성으로 free 버킷에 흡수한다. */
  legacyBonusCredits: number;
  /** config/billing.freeCredits(트랜잭션 밖에서 조회, 폴백 처리 완료된 값). */
  configFreeCredits: number;
}

export interface FreeGrantPlan {
  /** false면 이미 지급됨 — 호출부는 아무 것도 쓰지 않아야 한다(멱등). */
  shouldGrant: boolean;
  /** 이 사건 반영 후 freeBalance. shouldGrant가 false면 현재값 그대로. */
  newFreeBalance: number;
  /** 이번에 새로 지급한 순수 무료 회차(레거시 이월 제외). */
  grantedAmount: number;
  /** 레거시 bonusCredits 중 이번에 free로 흡수한 양(0이면 이월 없음). */
  carryOver: number;
}

/**
 * 스펙 §3-1의 멱등 알고리즘 그대로: 이미 지급됐으면 스킵, 아니면
 * `configFreeCredits + legacyBonusCredits`를 `currentFreeBalance`에 더한다.
 *
 * 음수 입력(방어적으로 Firestore 원시값이 손상된 경우)은 0으로 취급한다 —
 * 지급액이 음수가 되어 잔액을 깎아버리는 사고를 막기 위함.
 */
export function planFreeGrant(input: FreeGrantInput): FreeGrantPlan {
  const currentFreeBalance = Math.max(0, input.currentFreeBalance || 0);
  if (input.alreadyGranted) {
    return {
      shouldGrant: false,
      newFreeBalance: currentFreeBalance,
      grantedAmount: 0,
      carryOver: 0,
    };
  }

  const grantedAmount = Math.max(0, input.configFreeCredits || 0);
  const carryOver = Math.max(0, input.legacyBonusCredits || 0);
  const newFreeBalance = currentFreeBalance + grantedAmount + carryOver;

  return {shouldGrant: true, newFreeBalance, grantedAmount, carryOver};
}
