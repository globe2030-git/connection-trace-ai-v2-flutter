/**
 * 탈퇴 사용자의 **번호 확인 기록**을 지운다.
 *
 * ## 이것은 정책 정리가 아니라 결함 수정이다
 *
 * `phoneOtpConfirm`은 번호를 계정에 붙일 때 이렇게 판정한다.
 *
 * ```
 * phoneAccounts/{번호해시} 가 이미 있고, 그 uid 가 지금 uid 와 다르면 → "taken"
 * ```
 *
 * 그런데 **탈퇴해도 이 문서가 남았다.** 남은 문서의 주인은 **이미 지워진
 * uid**다. 같은 번호로 다시 가입하면 새 uid가 발급되고, 죽은 uid와 다르므로
 * **"taken"으로 막힌다 — 본인 번호인데 본인이 영원히 못 쓴다.**
 *
 * ⭐ **아무도 아직 겪지 않았다.** 번호 확인 게이트가 꺼져 있어(`config/
 * phoneVerification` 문서가 없다) 이 경로가 돌지 않기 때문이다. **켜는 순간
 * 드러났을 것**이고, 그때는 *"본인 번호인데 가입이 안 된다"*는 제보로
 * 나타났을 것이다 — 원인을 찾기 어려운 모양이다. **켜기 전에 잡았다.**
 *
 * ## 방침과도 어긋나 있었다
 *
 * 개인정보처리방침 14번은 회원 탈퇴 시 계정 정보가 파기된다고 단언한다.
 * `phoneAccounts`는 **번호해시 → uid 매핑**이라 명백히 계정 정보다. 방침과
 * 구현이 어긋나는 것 자체가 법적 리스크다(CLAUDE.md 개인정보 절) —
 * `cardPhotoCleanup.ts`·`tombstoneCleanup.ts`와 같은 이유로 서버가 지운다.
 *
 * ## 🚨 `phoneSendLedger`는 여기서 지우지 않는다
 *
 * 발송 장부(하루 상한·재발송 간격의 근거)는 **일부러 남긴다.**
 * `firestore.rules`가 그 장부를 왜 서버에 뒀는지 이미 적어 두었다 —
 * *"기기에 두면 앱을 지웠다 깔아서 상한을 초기화할 수 있다"*. **탈퇴 때
 * 지우면 똑같아진다**: 탈퇴 → 재가입으로 하루 5통 상한이 초기화된다.
 *
 * 📌 **[AI 한도 재가입 우회]와 구조가 같은데 결론이 반대다.** 그쪽은
 * 사용자가 A안(수용)으로 정했다. 여기서 다르게 정한 이유는 하나다 —
 * **문자는 건당 실제 비용이 나간다.** AI 무료 회차는 한도를 넘겨도 회사가
 * 더 쓰는 것으로 끝나지만, 발송 상한이 풀리면 **돈이 그대로 새고 발송
 * 사업자에게도 문제가 된다.** 이 문단이 없으면 다음 사람이 *"AI는
 * 수용했는데 왜 이건 막나"*로 되돌리려 든다.
 *
 * 대신 장부는 **보관 기간으로 지운다**(`SEND_LEDGER_RETENTION_MS`) — 탈퇴와
 * 무관하게 오래된 것이 사라지므로 우회로를 열지 않고도 오래 쌓이지 않는다.
 * 그래서 이 장부는 **방침에 「탈퇴 후에도 남는 것」으로 명시**해야 한다.
 */

/**
 * [deletePhoneRecords]가 다루는 문서의 최소 모양.
 *
 * `id`가 곧 **번호해시**다 — 챌린지 문서도 같은 키를 쓰므로 이것으로 찾는다.
 */
export interface PhoneRecordDoc {
  id: string;
  ref: unknown;
}

/**
 * 이미 `uid`로 좁혀진 `phoneAccounts` 질의.
 *
 * `firebase-admin`의 타입을 그대로 받지 않는 이유는 `cardPhotoCleanup.ts`·
 * `tombstoneCleanup.ts`와 같다 — 이 저장소의 functions 테스트는 **에뮬레이터
 * 없는 순수 단위 테스트**라, 좁은 인터페이스로 받아야 가짜 객체로 검사할 수
 * 있다.
 */
export interface PhoneAccountQuery {
  get(): Promise<{docs: PhoneRecordDoc[]}>;
}

export interface PhoneRecordBatch {
  delete(ref: unknown): void;
  commit(): Promise<unknown>;
}

export interface PhoneRecordCleanupResult {
  /** 지운 `phoneAccounts` 문서 수. 실패하면 그때까지 커밋된 수. */
  deleted: number;
  /** 실패 시 오류 종류 이름만. **번호해시는 절대 담지 않는다.** */
  errorType?: string;
}

/**
 * 이 uid에 붙어 있던 번호 기록을 지운다.
 *
 * `phoneAccounts` 문서와, **같은 키의** `phoneOtpChallenges` 문서를 함께
 * 지운다. 챌린지는 보통 이미 없다 — 인증에 성공하면 그 자리에서 지우고,
 * 3분이면 만료된다. 그래도 지우는 이유는 **인증을 마치지 못한 채 탈퇴한
 * 경우**에 찌꺼기가 남기 때문이다.
 *
 * - **멱등이다.** 없으면 조용히 끝난다. 트리거가 중복 발화하거나 재시도돼도
 *   안전하다(같은 함수의 다른 정리들과 같은 성질).
 * - **던지지 않는다.** 이 정리가 실패해도 탈퇴의 나머지 단계는 이미 끝났거나
 *   계속돼야 한다. 실패는 반환값으로 알린다.
 *
 * 🚨 **번호해시를 반환값에도 로그에도 담지 않는다.** 번호는 경우의 수가 좁아
 * 해시가 새면 전수 대입이 현실적이다(`firestore.rules` 주석). 개수만 남긴다.
 *
 * ⚠️ 한 uid에 붙는 번호는 하나라 문서는 사실상 1건이다. 그래도 배열로 도는
 * 것은 **과거에 잘못 쌓인 것이 있어도 함께 지우기 위해서**다.
 */
export async function deletePhoneRecords(
  accounts: PhoneAccountQuery,
  challengeRefFor: (phoneHash: string) => unknown,
  newBatch: () => PhoneRecordBatch,
): Promise<PhoneRecordCleanupResult> {
  try {
    const snap = await accounts.get();
    if (snap.docs.length === 0) return {deleted: 0};

    const batch = newBatch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
      // 같은 키를 쓰는 챌린지도 함께. 없으면 Firestore가 조용히 넘긴다.
      batch.delete(challengeRefFor(doc.id));
    }
    await batch.commit();
    return {deleted: snap.docs.length};
  } catch (e) {
    return {deleted: 0, errorType: (e as Error)?.name ?? "Error"};
  }
}
