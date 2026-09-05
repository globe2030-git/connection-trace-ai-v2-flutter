/**
 * 재가입(계정 삭제 → 재가입) 반복으로 무료체험을 무한 재지급받는 루프를
 * 막기 위한 "기기 단위 지급 이력" 판정 로직. 순수 함수 위주로 설계했다 —
 * walletCredits.ts/freeGrant.ts와 같은 이유(Firestore 트랜잭션 객체에
 * 묶이지 않은 판정 로직만 따로 유닛테스트하기 위함).
 *
 * 설계 근거: docs/planning/monetization-referral-engineering-spec
 * -2026-08-14.md §4("재가입×리퍼럴 무한 증정 루프 — 설계"), 특히 §4-2
 * ("탈퇴해도 사라지지 않는 것은 개인정보가 아니라 기기 지문 해시 하나뿐").
 *
 * 실제 읽기·쓰기(트랜잭션, `deviceLedger/{deviceHash}` 문서)는
 * functions/src/index.ts `bootstrapAccount`에 남아 있고, 이 파일의 함수만
 * 호출한다.
 */

import {createHmac} from "crypto";

/**
 * 기기당 무료체험 지급 상한. 1이면 "이 기기에 이미 한 번이라도 무료체험을
 * 지급했으면 더 이상 지급하지 않는다"는 뜻 — §4-3의 루프 차단이 여기서
 * 시작된다(피초대자 보너스까지 연쇄적으로 막히는 근거는 스펙 §4-3 참고).
 *
 * 상수로 분리해 나중에 정책이 바뀌어도(예: 가족 공유 기기 배려로 2로 완화)
 * 이 값만 바꾸면 되게 한다.
 */
export const DEVICE_TRIAL_GRANT_CAP = 1;

/**
 * `deviceLedger/{deviceHash}` 문서 보관 기간 — **30일**
 * (2026-09-05 globe2030님 결정).
 *
 * ## 왜 기간이 필요한가
 *
 * 이 장부는 **탈퇴해도 지우지 않는다** — 지우면 재가입으로 무료체험 상한이
 * 초기화돼 장부를 둔 의미가 사라진다(`onUserDeletedCleanup` 이 일부러 안
 * 건드린다, 스펙 §4-2). 그런데 지우는 사유가 하나도 없으면 **사실상
 * 무기한 보관**이 되고, 개인정보 보호법 §21①(목적 달성 시 지체 없이 파기)과
 * 부딪힌다. 그래서 `phoneSendLedger` 와 **같은 방식**으로 보관 기간을 둔다.
 *
 * ## 🚨 대가 — 30일마다 상한이 풀린다
 *
 * [DEVICE_TRIAL_GRANT_CAP] 은 **「이 기기에 영구히 1회」**를 전제로 설계된
 * 값이다. 보관 기간이 생기면 문서가 사라진 뒤 `trialGrantsIssued` 가 0으로
 * 읽혀, **같은 기기에서 30일마다 무료체험을 다시 받을 수 있다**
 * (`DEFAULT_FREE_CREDITS` 만큼 · `freeGrant.ts`).
 *
 * 📌 **globe2030님이 그 대가를 알고 고르셨다.** 근거는 지금 과금이 꺼져
 * 있다는 것이다 — `config/billing.model` 필드가 없어 `reset` 으로 떨어지고
 * (`walletCredits.ts`), `reset` 모드에서는 이 지급 블록 자체를 건너뛴다
 * (`index.ts` `bootstrapAccount` 의 게이트 주석 참고). 즉 **지금은 장부에
 * 문서가 쌓이지도 않는다.**
 *
 * 🚨 **과금을 켤 때 이 자리를 다시 봐야 한다.** 켜는 순간부터 「30일마다
 * 1회」가 실제 비용이 된다. 그때의 선택지는 ① 기간을 늘린다 ② 상한을
 * 「기간당」이 아니라 「누적」으로 바꾼다(해시 대신 카운터를 남긴다)
 * ③ 그대로 둔다(비용을 감수한다) 셋이고, **결정은 globe2030님이다.**
 *
 * ⚠️ 값이 `phoneSendLedger` 와 같은 30일인 것은 **우연이 아니라 같은
 * 이유**다(장부를 탈퇴로 못 지우니 기간으로 지운다). 다만 **상수는 따로
 * 둔다** — 한쪽 정책이 바뀔 때 다른 쪽이 조용히 따라가면 안 된다.
 */
export const DEVICE_LEDGER_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * 이번 쓰기로 문서가 언제 파기돼야 하는지(epoch ms).
 *
 * 🚨 **쓸 때마다 다시 계산한다 — 미끄러지는 창(sliding window)이다.**
 * `phoneSendLedger` 가 그렇게 하고 있어(`index.ts` 의 `phoneOtpRequest`)
 * 같은 쪽으로 맞췄다. 「처음 생길 때만」으로 하면 `firstSeenAt` 기준 고정
 * 창이 되는데, 그러면 **마지막 지급 30일 뒤가 아니라 최초 지급 30일 뒤**에
 * 지워져 방어 구간이 실제로는 더 짧아진다.
 *
 * ⚠️ 순수 함수로 뺀 이유: 실제 쓰기는 `index.ts` 의 트랜잭션 안에 있어
 * 유닛테스트가 닿지 않는다(이 파일 머리말의 설계 취지). 계산만이라도
 * 검사로 잠근다 — `adminAuth.ts` 의 `adminSessionExpiresAt` 과 같은 모양이다.
 */
export function deviceLedgerExpiresAtMs(nowMs: number): number {
  return nowMs + DEVICE_LEDGER_RETENTION_MS;
}

/**
 * raw device id(iOS `identifierForVendor`, Android 기기 식별자 등)를 서버
 * 전용 salt와 함께 HMAC-SHA256 해시한 hex 다이제스트를 반환한다.
 *
 * 왜 서버가 계산하나(클라이언트가 아니라): 클라이언트가 해시를 만들어
 * 보내면 다른 기기인 척 임의의 해시값을 위장해 보낼 수 있다 — raw id만
 * 전송받고 서버가 salt로 해시해야 위장이 의미 없어진다(스펙 §4-2).
 *
 * raw device id 자체는 이 함수 안에서도 로그로 남기지 않는다 — 호출부
 * (index.ts)도 "값이 있는지 없는지"만 로그에 남길 것(CLAUDE.md 4절).
 */
export function deviceHash(rawDeviceId: string, salt: string): string {
  return createHmac("sha256", salt).update(rawDeviceId).digest("hex");
}

/**
 * 이 기기에 무료체험을 더 지급해도 되는지 판정한다.
 *
 * `trialGrantsIssued`는 `deviceLedger/{deviceHash}.trialGrantsIssued`의
 * 현재값(문서가 없으면 0으로 취급해 호출부에서 넘긴다). 음수/비정상값이
 * 들어와도 방어적으로 0 이상으로 취급한다.
 */
export function canGrantTrialToDevice(trialGrantsIssued: number): boolean {
  const issued = Math.max(0, trialGrantsIssued || 0);
  return issued < DEVICE_TRIAL_GRANT_CAP;
}

/**
 * `deviceLedger/{deviceHash}.issuedToUids`에 새 uid를 추가한 배열을
 * 반환한다(중복 방지). 자기초대(같은 기기에서 나온 계정끼리의 리퍼럴)
 * 판별에 쓰기 위한 헬퍼 — 스펙 §4-4가 다루는 리퍼럴 redemption은 이번
 * 라운드(U5)에 아직 없으므로 지금은 어디서도 호출되지 않지만, 나중에
 * `bootstrapAccount`가 리퍼럴 코드 redemption을 처리할 때(U6) 그대로
 * 재사용하기 위해 미리 만들어 둔다.
 */
export function recordDeviceUsage(
  issuedToUids: string[] | undefined,
  uid: string
): string[] {
  const existing = issuedToUids ?? [];
  if (existing.includes(uid)) return existing;
  return [...existing, uid];
}

/**
 * §4-4 "자기초대(같은 기기) 명시적 차단" 판정 — 리퍼럴 코드 소유자(초대자)
 * uid가 이 기기에서 이미 계정을 만든 적이 있으면(=같은 기기에서 나온
 * 계정끼리의 초대) true를 반환한다. 이번 라운드(U5)엔 리퍼럴 redemption이
 * 없어 어디서도 호출되지 않지만, U6에서 그대로 재사용하기 위해 미리
 * 만들어 둔다(스펙 §4-4).
 */
export function isSelfReferralOnDevice(
  issuedToUids: string[] | undefined,
  referrerUid: string
): boolean {
  return (issuedToUids ?? []).includes(referrerUid);
}
