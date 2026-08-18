/**
 * `verifyAndGrantPurchase`(index.ts) 뼈대 작업(U7)을 지원하는 순수 함수
 * 모음. 다른 *.ts 파일(walletCredits.ts, freeGrant.ts 등)과 같은 이유로
 * 분리했다 — Firestore 트랜잭션 객체에 묶이지 않은 판정 로직만 따로
 * `node --test`로 검증하기 위함.
 *
 * ⚠️ 이 파일에 Apple App Store Server API·Google Play Developer API 호출은
 * 없다. 실제 영수증/구매 검증은 이번 라운드(U7 "뼈대만") 범위 밖이다 —
 * index.ts의 `verifyAndGrantPurchase`에 TODO로 표시해 둔 자리에서 다음
 * 라운드가 채운다.
 *
 * 설계 근거: docs/planning/ai-credit-wallet-spec.md §3-4(충전 적립 알고리즘),
 * docs/planning/monetization-referral-engineering-spec-2026-08-14.md
 * §2-1(2-1절 "용어 재활용" — tiers/productId 스키마).
 */

export type IapPlatform = "ios" | "android";

/** `request.data.platform`이 iOS/Android 둘 중 하나인지 확인하는 타입가드. */
export function isValidIapPlatform(value: unknown): value is IapPlatform {
  return value === "ios" || value === "android";
}

/**
 * `purchases/{transactionId}` 문서 ID로 그대로 쓰는 멱등 패턴(wallet-spec
 * §3-4)이므로, Firestore 문서 ID로 쓸 수 없는 형태(빈 문자열, 300자 초과,
 * `/` 포함 — 문서 ID에 슬래시가 들어가면 하위 컬렉션 경로로 오인된다)는
 * 미리 걸러낸다. 실제 스토어 트랜잭션 ID 형식 검증(Apple/Google 각각의
 * 실제 포맷)은 하지 않는다 — 그건 영수증 검증 자체와 함께 나중에 채운다.
 */
export function isValidTransactionId(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 300) return false;
  if (trimmed.includes("/")) return false;
  return true;
}

/** 비어있지 않은 문자열인지만 확인하는 범용 가드(productId/receiptData 등,
 * 형식까지는 검증하지 않는다 — 스토어마다 형식이 다르고 실제 검증 시점에
 * 각 스토어 SDK/API가 스스로 거부한다). */
export function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/** `config/billing.tiers` 배열 원소 하나의 최소 형태. 관리자 콘솔
 * (`docs/admin/admin.js`)이 실제로 저장하는 필드 중 이 판정에 필요한 것만
 * 뽑았다 — `productId`는 이번 라운드에서 스키마에 추가하는 신규 선택
 * 필드로, 스토어 상품ID가 아직 등록되지 않은 티어는 비어 있거나
 * placeholder 문자열일 수 있다. */
export interface BillingTierRaw {
  priceKrw?: number;
  credits?: number;
  active?: boolean;
  productId?: string;
}

export type TierLookupResult =
  | {ok: true; priceKrw: number; credits: number}
  | {ok: false; error: string};

/**
 * `config/billing.tiers`에서 `productId`가 일치하고 `active===true`이며
 * `credits`가 양수인 티어를 찾는다. 판매 중이 아니거나(`active:false`)
 * 회수가 미정(`credits`가 없거나 0 이하)인 티어는 매칭하지 않는다 —
 * 관리자 콘솔에서 끈 상품으로 결제가 들어와도 크레딧을 지급하면 안 되기
 * 때문이다.
 *
 * 스토어 상품ID가 아직 등록되지 않은 현재 상태(모든 티어의 `productId`가
 * placeholder이거나 없음)에서는 항상 `{ok:false}`를 반환한다 — 이건 버그가
 * 아니라 "아직 매칭될 실제 상품이 없다"는 정상 상태다.
 */
export function resolveTierByProductId(
  tiers: BillingTierRaw[] | undefined,
  productId: string
): TierLookupResult {
  if (!isNonEmptyString(productId)) {
    return {ok: false, error: "productId가 필요합니다."};
  }
  const found = (tiers ?? []).find(
    (t) =>
      t.productId === productId &&
      t.active === true &&
      typeof t.credits === "number" &&
      t.credits > 0
  );
  if (!found) {
    return {
      ok: false,
      error: `판매 중인 상품에서 productId(${productId})를 찾지 못했습니다.`,
    };
  }
  return {
    ok: true,
    priceKrw: typeof found.priceKrw === "number" ? found.priceKrw : 0,
    credits: found.credits as number,
  };
}
