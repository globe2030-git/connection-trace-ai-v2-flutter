/**
 * cardPhotoCleanup.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를
 * 쓴다 — chunk.test.ts/usageReset.test.ts와 같은 패턴. 실행:
 * `npm run build && node --test lib/cardPhotoCleanup.test.js`
 * (package.json의 `npm test`가 이 파일도 포함하도록 갱신돼 있다).
 *
 * 무엇을 지키려는 검사인가: 탈퇴 시 명함 사진 서버 사본이 **반드시 지워지고**,
 * 그 과정이 **탈퇴의 나머지 단계를 막지 않는지**를 본다. 지금은
 * `kCardPhotoBackupEnabled = false`라 올라간 사진이 없어 **실물로는 확인할 수
 * 없다** — 플래그를 켠 뒤 이 동작이 처음 실전에 노출되므로, 그 전까지는 이
 * 테스트가 유일한 방어선이다.
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  cardPhotoPrefixFor,
  deleteUserCardPhotos,
  type CardPhotoBucket,
} from "./cardPhotoCleanup";

/** 호출을 기록하는 가짜 버킷. */
function fakeBucket(onDelete?: () => Promise<void>): {
  bucket: CardPhotoBucket;
  calls: Array<{prefix: string; force?: boolean}>;
} {
  const calls: Array<{prefix: string; force?: boolean}> = [];
  return {
    calls,
    bucket: {
      async deleteFiles(options) {
        calls.push(options);
        if (onDelete) await onDelete();
        return undefined;
      },
    },
  };
}

test("접두사는 CardPhotoBackupService의 저장 경로와 같다", () => {
  // 앱은 users/{uid}/cards/{contactId}.enc 에 올린다. 이게 어긋나면 삭제가
  // 조용히 아무것도 안 지운다 — 실패도 안 나서 아무도 모른다.
  assert.equal(cardPhotoPrefixFor("abc123"), "users/abc123/cards/");
});

test("uid 접두사 아래를 통째로 지운다", async () => {
  const {bucket, calls} = fakeBucket();
  const result = await deleteUserCardPhotos(bucket, "uid-1");

  assert.equal(result.attempted, true);
  assert.equal(result.errorType, undefined);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].prefix, "users/uid-1/cards/");
});

test("일부 파일이 실패해도 나머지를 계속 지운다(force)", async () => {
  // 한 파일 때문에 나머지가 통째로 남는 것이 더 나쁘다.
  const {bucket, calls} = fakeBucket();
  await deleteUserCardPhotos(bucket, "uid-1");
  assert.equal(calls[0].force, true);
});

test("다른 사용자의 경로는 건드리지 않는다", async () => {
  const {bucket, calls} = fakeBucket();
  await deleteUserCardPhotos(bucket, "uid-1");
  assert.ok(!calls[0].prefix.includes("uid-2"));
  assert.ok(calls[0].prefix.startsWith("users/uid-1/"));
});

test("지울 것이 없어도 조용히 끝난다 — 멱등", async () => {
  // 트리거가 중복 발화하거나 재시도돼도 안전해야 한다. 접두사에 아무것도
  // 없으면 deleteFiles는 그냥 성공한다.
  const {bucket} = fakeBucket();
  const first = await deleteUserCardPhotos(bucket, "uid-1");
  const second = await deleteUserCardPhotos(bucket, "uid-1");
  assert.equal(first.errorType, undefined);
  assert.equal(second.errorType, undefined);
});

test("삭제가 실패해도 던지지 않는다 — 탈퇴의 나머지 정리가 계속돼야 한다", async () => {
  const {bucket} = fakeBucket(async () => {
    const e = new Error("permission denied");
    e.name = "StorageError";
    throw e;
  });

  const result = await deleteUserCardPhotos(bucket, "uid-1");
  assert.equal(result.attempted, true);
  assert.equal(result.errorType, "StorageError");
});

test("실패 정보에 경로·파일명을 담지 않는다", async () => {
  // 로그로 흘러가는 값이다. 파일명은 {contactId}.enc라 그 자체로 개인정보는
  // 아니지만, 경로가 쌓이면 누가 명함을 몇 장 가졌는지가 남는다.
  const {bucket} = fakeBucket(async () => {
    const e = new Error("users/uid-1/cards/contact-9.enc 삭제 실패");
    e.name = "StorageError";
    throw e;
  });

  const result = await deleteUserCardPhotos(bucket, "uid-1");
  const serialized = JSON.stringify(result);
  assert.ok(!serialized.includes("cards/"));
  assert.ok(!serialized.includes(".enc"));
  assert.ok(!serialized.includes("contact-9"));
});

test("uid가 비면 아무것도 하지 않는다", async () => {
  const {bucket, calls} = fakeBucket();
  const result = await deleteUserCardPhotos(bucket, "");
  assert.equal(result.attempted, false);
  assert.equal(calls.length, 0);
});
