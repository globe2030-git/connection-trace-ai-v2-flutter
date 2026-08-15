/**
 * 탈퇴 사용자의 **명함 사진(암호문) 서버 사본**을 지운다.
 *
 * ## 왜 서버(Admin SDK)에서 지우나
 *
 * 앱은 계정 삭제 흐름에서 스스로 Storage를 지우려고 한다
 * (`settings_view.dart` → `ContactImageService.deleteAllCardImages`). 그런데
 * 그 호출은 **Firebase 계정을 먼저 지운 뒤에** 일어난다. 그 시점에는
 * `request.auth`가 null이라 `storage.rules`의 `isOwner(uid)`가 거짓이 되고,
 * **삭제도 `listAll`도 거부된다.** 즉 클라이언트 경로만으로는 사진이 남는다.
 *
 * Admin SDK는 보안 규칙을 우회하므로 계정이 사라진 뒤에도 지울 수 있다.
 * 게다가 트리거는 **앱이 중간에 죽어도** 돈다 — 클라이언트 순서를 바꾸는
 * 방법으로는 그 경우를 막지 못한다.
 *
 * ⚠️ 이 정리는 개인정보처리방침이 약속한 "회원 탈퇴 시 파기"의 일부다.
 * 방침과 구현이 어긋나는 것 자체가 법적 리스크라(CLAUDE.md 개인정보 절),
 * 사진 서버 저장(`kCardPhotoBackupEnabled`)을 켜기 전에 반드시 배포돼 있어야
 * 한다.
 *
 * ## 지금은 지울 것이 없다
 *
 * `CardPhotoBackupService.kCardPhotoBackupEnabled`가 `false`라 올라간 사진이
 * 아직 없다. 그래도 미리 넣는 이유는 순서 때문이다 — 플래그를 켜는 순간부터
 * 사진이 쌓이는데, 그때 이 코드가 없으면 **그 사이에 탈퇴한 사람의 사진이
 * 영영 남는다.**
 */

/** 파일 경로 접두사. `CardPhotoBackupService._ref`와 같아야 한다. */
export function cardPhotoPrefixFor(uid: string): string {
  return `users/${uid}/cards/`;
}

/**
 * [deleteUserCardPhotos]가 쓰는 최소 인터페이스.
 *
 * `@google-cloud/storage`의 Bucket을 그대로 받지 않고 좁은 모양만 받는 이유:
 * 이 로직을 **에뮬레이터 없이 단위 테스트**하기 위해서다. 이 저장소의
 * functions 테스트는 전부 Node 내장 러너로 도는 순수 단위 테스트다
 * (`chunk.test.ts` 등).
 */
export interface CardPhotoBucket {
  deleteFiles(options: {prefix: string; force?: boolean}): Promise<unknown>;
}

export interface CardPhotoCleanupResult {
  /** 삭제를 시도했는지. 실패해도 true다. */
  attempted: boolean;
  /** 실패 시 오류 종류 이름만. **경로·파일명은 절대 담지 않는다.** */
  errorType?: string;
}

/**
 * `users/{uid}/cards/` 아래를 통째로 지운다.
 *
 * - **멱등이다.** 접두사에 아무것도 없으면 조용히 끝난다. 트리거가 중복
 *   발화하거나 재시도돼도 안전하다(같은 함수의 문의 삭제와 같은 성질).
 * - **던지지 않는다.** 이 정리가 실패해도 탈퇴의 나머지 단계(문의·AI 로그·
 *   Apple 토큰)는 계속돼야 한다. 실패는 반환값으로 알린다.
 * - `force: true`는 일부 파일이 실패해도 나머지를 계속 지우게 한다. 한 파일
 *   때문에 나머지가 통째로 남는 것이 더 나쁘다.
 *
 * ⚠️ **로그에 uid 외의 것을 남기지 않는다.** 파일명은 `{contactId}.enc`라
 * 그 자체로는 개인정보가 아니지만, 개수와 경로가 쌓이면 누가 명함을 몇 장
 * 가졌는지가 남는다. 개수만 남기지 않는 이유도 같다.
 */
export async function deleteUserCardPhotos(
  bucket: CardPhotoBucket,
  uid: string,
): Promise<CardPhotoCleanupResult> {
  if (!uid) return {attempted: false};
  try {
    await bucket.deleteFiles({prefix: cardPhotoPrefixFor(uid), force: true});
    return {attempted: true};
  } catch (e) {
    return {attempted: true, errorType: (e as Error)?.name ?? "Unknown"};
  }
}
