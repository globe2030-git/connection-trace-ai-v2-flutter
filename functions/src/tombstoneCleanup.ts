/**
 * 탈퇴 사용자의 **삭제 기록(묘비, `users/{uid}/deletedContacts/`)** 을 지운다.
 *
 * ## 왜 따로 지워야 하나 — Firestore는 하위 컬렉션을 안 지운다
 *
 * 앱의 `DataBackupService.deleteAllUserData(uid)`는 `contacts` 문서들을 지우고
 * `users/{uid}` 문서를 지운다. 그런데 **Firestore는 문서를 지워도 그 아래
 * 하위 컬렉션을 지우지 않는다.** 그래서 `users/{uid}/deletedContacts/{contactId}`
 * 문서들이 **탈퇴 뒤에도 서버에 남는다.** 지우는 코드가 앱에도 서버에도 없었다.
 *
 * 담긴 값은 `deletedAt` 시각뿐이라 개인정보 원문은 아니다. 다만 **문서 ID가
 * `contactId`이고 경로에 uid가 있다.** 개인정보처리방침 14번은 *"회원 탈퇴 시
 * 서버에 저장된 해당 이용자의 프로필 문서와 명함 데이터 전체, 계정 정보가
 * 삭제됩니다"*라고 단언한다 — **방침과 구현이 어긋난다.** 방침과 구현이
 * 어긋나는 것 자체가 법적 리스크다(CLAUDE.md 개인정보 절).
 *
 * ## 왜 서버(Admin SDK)인가
 *
 * 명함 사진 때와 같은 이유다(`cardPhotoCleanup.ts`). 앱이 지우려 해도 그
 * 시점에는 계정이 이미 삭제돼 `request.auth`가 null이고 규칙이 거부한다.
 * 게다가 트리거는 **앱이 중간에 죽어도** 돈다.
 *
 * ## 묘비가 무엇인가
 *
 * 다기기 동기화(P1-39 A안)에서 "다른 기기에서 지운 명함"을 알리는 표식이다.
 * 서버 문서만 지우면 다른 기기의 로컬 사본이 다시 올라오기 때문에, 삭제
 * 사실을 따로 남긴다(`data_backup_service.dart` `writeTombstone`).
 * 탈퇴하면 되살아날 기기 사본도 함께 사라지므로 **묘비를 남길 이유가 없다.**
 */

/** [deleteTombstones]가 쓰는 최소 인터페이스. */
export interface TombstoneDoc {
  ref: unknown;
}

/**
 * Firestore 컬렉션·배치의 최소 모양.
 *
 * `firebase-admin`의 타입을 그대로 받지 않는 이유는 `cardPhotoCleanup.ts`와
 * 같다 — 이 저장소의 functions 테스트는 **에뮬레이터 없는 순수 단위 테스트**라
 * (`chunk.test.ts` 등), 좁은 인터페이스로 받아야 가짜 객체로 검사할 수 있다.
 */
export interface TombstoneCollection {
  get(): Promise<{docs: TombstoneDoc[]}>;
}

export interface TombstoneBatch {
  delete(ref: unknown): void;
  commit(): Promise<unknown>;
}

export interface TombstoneCleanupResult {
  /** 지운 문서 수. 실패하면 그때까지 커밋된 수. */
  deleted: number;
  /** 실패 시 오류 종류 이름만. **경로·문서 ID는 절대 담지 않는다.** */
  errorType?: string;
}

/**
 * 묘비를 전부 지운다.
 *
 * - **멱등이다.** 비어 있으면 조용히 끝난다. 트리거가 중복 발화하거나
 *   재시도돼도 안전하다(같은 함수의 문의·AI 로그 삭제와 같은 성질).
 * - **던지지 않는다.** 이 정리가 실패해도 탈퇴의 나머지 단계는 이미 끝났거나
 *   계속돼야 한다. 실패는 반환값으로 알린다.
 * - 배치 상한(500) 아래인 400씩 끊어 커밋한다 — 같은 함수의 다른 삭제들과
 *   같은 값이다.
 *
 * ⚠️ **문서 ID(`contactId`)를 반환값에도 로그에도 담지 않는다.** 개수만 남긴다.
 */
export async function deleteTombstones(
  collection: TombstoneCollection,
  newBatch: () => TombstoneBatch,
  chunk: <T>(arr: T[], size: number) => T[][],
): Promise<TombstoneCleanupResult> {
  let deleted = 0;
  try {
    const snap = await collection.get();
    if (snap.docs.length === 0) return {deleted: 0};
    for (const batchDocs of chunk(snap.docs, 400)) {
      const batch = newBatch();
      batchDocs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += batchDocs.length;
    }
    return {deleted};
  } catch (e) {
    return {deleted, errorType: (e as Error)?.name ?? "Unknown"};
  }
}
