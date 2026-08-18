/**
 * wallet(지갑형) 과금 모델의 "판정 로직"만 떼어낸 순수 함수 모음.
 *
 * 왜 순수 함수로 분리했나: `incrementAndCheckUsage`(index.ts)는 Firestore
 * 트랜잭션 객체(`tx`)에 강하게 묶여 있어 그 안의 로직만 따로 유닛테스트하기
 * 어렵다. 이 파일은 "입력(현재 잔액/설정 문서) → 출력(다음 잔액) 또는 예외"만
 * 다루고 Firestore를 전혀 모른다 — usageReset.ts/usageReset.test.ts와 같은
 * 스타일이다. 실제 읽기·쓰기(트랜잭션)는 index.ts에 남아 있고 이 파일의
 * 함수만 호출한다.
 *
 * 설계 근거: docs/planning/ai-credit-wallet-spec.md §3-2(소비 알고리즘),
 * §2-4(config/billing.model 필드), §1(reset/wallet 분기가 필드를 공유하지
 * 않아 서로 영향이 없다는 전제).
 */

export type BillingModel = "reset" | "wallet";

/**
 * `config/billing` 문서에서 `model` 필드를 해석한다. 문서가 없거나
 * `model` 필드가 없거나 `'reset'`/`'wallet'` 외의 값이면 **반드시
 * `'reset'`으로 폴백**한다.
 *
 * 이 폴백 방향이 중요하다 — 조회 실패(네트워크 오류, 문서 없음 등) 시
 * `'wallet'`로 폴백하면 장애 상황에서 조용히 "리셋 없는 무제한 과금"
 * 모델로 바뀌는 위험이 생긴다(스펙 §3-2). `'reset'` 폴백은 지금까지
 * 검증된 동작으로 돌아가는 것이라 안전하다.
 */
export function resolveBillingModel(
  billingDoc: Record<string, unknown> | undefined | null
): BillingModel {
  return billingDoc?.model === "wallet" ? "wallet" : "reset";
}

export interface WalletBalances {
  free: number;
  paid: number;
}

/** wallet 모드에서 free/paid 잔액이 모두 소진됐을 때 던지는 에러. */
export class WalletExhaustedError extends Error {
  constructor() {
    super("AI 사용 가능 횟수를 모두 사용했어요. 충전 후 다시 시도해 주세요.");
    this.name = "WalletExhaustedError";
  }
}

/**
 * wallet 모드 1회 소비 — 무료(free) 버킷을 먼저 깎고, 무료가 0이면 충전
 * (paid) 버킷을 깎는다(스펙 §3-2, §2-1 "무료 먼저 소진"). 둘 다 0이면
 * `WalletExhaustedError`를 던진다.
 *
 * `free`/`paid`는 음수/undefined가 들어올 수 있는 Firestore 원시값을
 * 그대로 받되(`?? 0`으로 방어), 반환값은 항상 0 이상이다.
 */
export function consumeWalletCredit(balances: WalletBalances): WalletBalances {
  const free = balances.free ?? 0;
  const paid = balances.paid ?? 0;
  if (free + paid <= 0) {
    throw new WalletExhaustedError();
  }
  if (free > 0) {
    return {free: free - 1, paid};
  }
  return {free, paid: paid - 1};
}
