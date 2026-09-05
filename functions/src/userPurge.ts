/**
 * **uid 하나에 딸린 서버 자료를 지우는 한 곳.**
 *
 * ## 🚨 왜 만드나 — 파기 경로가 두 벌로 갈라져 있었다
 *
 * 2026-09-05 실측. 같은 "그 사람 것을 다 지운다"를 두 곳이 **다르게** 하고 있었다.
 *
 * ```
 * 연결 해제(onSocialUnlinkRequested)   recursiveDelete(users/{uid}) + ocrStats
 * 탈퇴(onUserDeletedCleanup)           deletedContacts 만 낱개로 + ocrStats 없음
 * ```
 *
 * 🚨 **그래서 `users/{uid}/cardSources` 가 탈퇴 후 서버에 남았다.** 명함 파싱
 * 원문이고 **이름·전화·주소가 통째로** 들어 있으며, 그것도 이용자 본인이 아니라
 * **제3자(명함 주인)의 것**이다(`firestore.rules` 가 *"개인정보 무게는 명함
 * 본문과 똑같다"* 고 적어 두었다). `ocrStats/{uid}` 도 탈퇴 경로에는 없었다.
 *
 * ⚠️ **방침이 파기를 단언한 자리다** — `privacy-policy.html` §14 *"명함 데이터
 * 전체가 삭제되며"* · 594행 *"이 통계는 … 회원 탈퇴 시 함께 파기됩니다."*
 * **방침과 구현이 어긋나는 것 자체가 법적 리스크다**(CLAUDE.md 개인정보 절).
 *
 * ## ⭐ 한 줄 더하지 않고 함수를 하나로 모으는 이유
 *
 * `index.ts:1613` 이 **이미 예고하고 있었다**:
 *
 * > *"앱 안의 탈퇴와 **같은 경로를 그대로 쓴다** — 파기 대상이 두 벌로
 * > 갈라지면 한쪽만 고쳐지는 날이 온다"*
 *
 * 🚨 **그날이 왔다.** 탈퇴 쪽에 `cardSources` 한 줄을 더하면 **다음에 또
 * 갈라진다.** 그래서 **두 경로가 이 함수를 부르게** 한다.
 *
 * ## 🚨 Firestore 는 문서를 지워도 하위 컬렉션을 안 지운다
 *
 * 이 저장소가 **같은 함정에 세 번** 걸렸다 — `deletedContacts`(2026-08-15) ·
 * `cardSources`(오늘) · 프로필 사진. ⭐ **그래서 「무엇을 지울지 나열하는」 대신
 * `recursiveDelete` 로 하위 전체를 덮는다** — 나열은 새 컬렉션이 생길 때마다
 * 낡고, **낡아도 조용하다.**
 *
 * ⚠️ 다만 `recursiveDelete` 는 **몇 건 지웠는지 안 알려 준다.** 파기는 기록이
 * 남아야 하는 일이라, **묘비는 세면서 지우고**(`deleteTombstones`) 나머지를
 * `recursiveDelete` 로 덮는다.
 *
 * ## uid 스코프인데 `users/{uid}` 아래가 아닌 것
 *
 * `recursiveDelete` 가 못 닿으므로 **여기 나열해야 한다.** 🚨 새로 생기면
 * 이 배열에 더할 것 — 그리고 `userPurge.test.ts` 가 그 배열을 고정한다.
 */

/** `users/{uid}` 아래가 아니면서 uid 하나에 딸린 최상위 문서들. */
export const UID_SCOPED_TOP_LEVEL_DOCS = ["ocrStats"] as const;

export interface UserPurgeDeps {
  /** `users/{uid}/deletedContacts` 를 세면서 지운다. */
  deleteTombstones: (
    path: string
  ) => Promise<{deleted: number; errorType?: string}>;
  /** 문서와 그 아래 하위 컬렉션 전부를 지운다. */
  recursiveDelete: (path: string) => Promise<void>;
  /** 최상위 `<collection>/<uid>` 문서 하나를 지운다. */
  deleteTopLevelDoc: (collection: string, uid: string) => Promise<void>;
}

export interface UserPurgeResult {
  /** 지운 묘비 수. 파기 기록용. */
  tombstonesDeleted: number;
  /** 묘비 정리가 실패했으면 그 종류. 나머지는 그래도 진행한다. */
  tombstoneErrorType?: string;
  /** 실제로 지운 최상위 문서들. 테스트가 이것으로 나열을 고정한다. */
  topLevelDeleted: string[];
}

/**
 * uid 하나에 딸린 서버 자료를 지운다.
 *
 * ⚠️ **묘비 정리가 실패해도 나머지는 진행한다.** 파기는 "가능한 데까지"가
 * "아무것도 안 함"보다 낫고, 실패는 결과에 담아 부르는 쪽이 로그로 남긴다.
 */
export async function purgeUidScopedData(
  uid: string,
  deps: UserPurgeDeps
): Promise<UserPurgeResult> {
  let tombstonesDeleted = 0;
  let tombstoneErrorType: string | undefined;
  try {
    const r = await deps.deleteTombstones(`users/${uid}/deletedContacts`);
    tombstonesDeleted = r.deleted;
    tombstoneErrorType = r.errorType;
  } catch (e) {
    tombstoneErrorType = (e as Error)?.name ?? "Unknown";
  }

  // 🚨 여기가 cardSources·contacts·commLogs 를 덮는 자리다.
  await deps.recursiveDelete(`users/${uid}`);

  const topLevelDeleted: string[] = [];
  for (const collection of UID_SCOPED_TOP_LEVEL_DOCS) {
    await deps.deleteTopLevelDoc(collection, uid);
    topLevelDeleted.push(collection);
  }

  return {tombstonesDeleted, tombstoneErrorType, topLevelDeleted};
}
