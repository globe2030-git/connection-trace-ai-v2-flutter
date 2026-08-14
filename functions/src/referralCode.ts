/**
 * 본인 리퍼럴 코드 생성/형식 검증 — 순수 함수만 떼어낸 모듈(테스트 가능하게,
 * walletCredits.ts/freeGrant.ts와 같은 스타일).
 *
 * 실제 발급(충돌 시 재시도, `referralCodes/{code}` 문서 선점, `users/{uid}
 * .referralCode` 기록)은 index.ts의 `ensureReferralCode`가 Firestore
 * 트랜잭션으로 담당한다 — 이 파일은 "코드 하나를 어떻게 만들고 어떻게
 * 형식을 검증하나"만 안다.
 *
 * ⚠️ 이번 라운드(U2)는 코드 **발급**까지만이다. 다른 사람의 코드를 입력해
 * 보너스를 받는 "redemption" 로직은 다음 라운드(별도 승인 필요, U2 작업
 * 지시서 참고) — 이 파일도 그 로직을 담지 않는다.
 */

// 혼동되기 쉬운 문자(0/O, 1/I/L)를 제외한 대문자+숫자. 사람이 입으로 불러
// 주거나 손으로 옮겨 적을 일이 있는 코드라 오독 가능성을 줄이는 게 우선이다.
export const REFERRAL_CODE_CHARSET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

// 6~8자 권장(작업 지시서) 중 중간값으로 고정. 짧을수록 입력은 편하지만
// 전체 코드 공간(32^6 ≈ 10억)이 이미 충돌 가능성을 무시할 만큼 넉넉하다.
export const REFERRAL_CODE_LENGTH = 6;

/**
 * 난수 코드 하나를 생성한다. `random`은 기본 `Math.random`이지만 테스트에서
 * 결정적 시퀀스를 주입할 수 있도록 매개변수로 열어 둔다.
 */
export function generateReferralCode(
  random: () => number = Math.random
): string {
  let code = "";
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) {
    const idx = Math.floor(random() * REFERRAL_CODE_CHARSET.length);
    code += REFERRAL_CODE_CHARSET[idx];
  }
  return code;
}

/**
 * 코드가 이 생성기가 만들 수 있는 형식(길이 6~8, 허용 문자셋)인지 확인한다.
 * 발급 직후 자체 검증(방어적) 및 향후 redemption 라운드에서 사용자 입력을
 * 1차로 걸러내는 데 재사용할 수 있다.
 */
export function isValidReferralCodeFormat(code: string): boolean {
  if (code.length < 6 || code.length > 8) return false;
  for (const ch of code) {
    if (!REFERRAL_CODE_CHARSET.includes(ch)) return false;
  }
  return true;
}
