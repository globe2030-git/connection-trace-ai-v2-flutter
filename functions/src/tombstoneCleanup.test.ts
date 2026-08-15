/**
 * tombstoneCleanup.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를
 * 쓴다 — chunk.test.ts/cardPhotoCleanup.test.ts와 같은 패턴.
 *
 * 무엇을 지키려는 검사인가: **Firestore가 하위 컬렉션을 안 지운다**는 사실
 * 때문에 탈퇴 뒤에도 남던 묘비를 확실히 지우고, 그 과정이 **탈퇴의 나머지
 * 단계를 막지 않는지**를 본다. 실기기·실서버로 확인하려면 실제 탈퇴가
 * 필요하므로, 배포 전까지는 이 테스트가 유일한 방어선이다.
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  deleteTombstones,
  type TombstoneBatch,
  type TombstoneCollection,
} from "./tombstoneCleanup";
import {chunkArray} from "./chunk";

/** 문서 n개를 가진 가짜 컬렉션. */
function fakeCollection(count: number, onGet?: () => never): TombstoneCollection {
  return {
    async get() {
      if (onGet) onGet();
      return {
        docs: Array.from({length: count}, (_, i) => ({ref: `doc-${i}`})),
      };
    },
  };
}

/** 커밋 횟수와 삭제된 ref를 기록하는 가짜 배치 팩토리. */
function fakeBatches(onCommit?: () => never): {
  newBatch: () => TombstoneBatch;
  commits: number;
  deletedRefs: unknown[];
} {
  const state = {commits: 0, deletedRefs: [] as unknown[]};
  return {
    get commits() {
      return state.commits;
    },
    get deletedRefs() {
      return state.deletedRefs;
    },
    newBatch: () => ({
      delete(ref: unknown) {
        state.deletedRefs.push(ref);
      },
      async commit() {
        if (onCommit) onCommit();
        state.commits += 1;
        return undefined;
      },
    }),
  };
}

test("묘비가 없으면 배치를 만들지 않고 조용히 끝난다(멱등)", async () => {
  const batches = fakeBatches();
  const result = await deleteTombstones(
    fakeCollection(0),
    batches.newBatch,
    chunkArray,
  );
  assert.equal(result.deleted, 0);
  assert.equal(result.errorType, undefined);
  assert.equal(batches.commits, 0, "빈 컬렉션에 커밋이 일어나면 안 된다");
});

test("묘비를 전부 지운다", async () => {
  const batches = fakeBatches();
  const result = await deleteTombstones(
    fakeCollection(5),
    batches.newBatch,
    chunkArray,
  );
  assert.equal(result.deleted, 5);
  assert.equal(batches.deletedRefs.length, 5);
  assert.equal(batches.commits, 1);
});

test("400개를 넘으면 나눠 커밋한다(배치 상한 500 아래)", async () => {
  const batches = fakeBatches();
  const result = await deleteTombstones(
    fakeCollection(950),
    batches.newBatch,
    chunkArray,
  );
  assert.equal(result.deleted, 950);
  assert.equal(batches.commits, 3, "400+400+150 = 3회");
});

test("조회가 실패해도 던지지 않는다 — 탈퇴의 나머지 단계를 막으면 안 된다", async () => {
  const batches = fakeBatches();
  const result = await deleteTombstones(
    fakeCollection(3, () => {
      throw new TypeError("권한 없음");
    }),
    batches.newBatch,
    chunkArray,
  );
  assert.equal(result.errorType, "TypeError");
  assert.equal(result.deleted, 0);
});

test("커밋이 실패해도 던지지 않고, 그때까지 지운 수를 알린다", async () => {
  const batches = fakeBatches(() => {
    throw new RangeError("중단됨");
  });
  const result = await deleteTombstones(
    fakeCollection(10),
    batches.newBatch,
    chunkArray,
  );
  assert.equal(result.errorType, "RangeError");
  assert.equal(result.deleted, 0, "커밋 전이므로 0이어야 한다");
});

test("반환값에 문서 ID나 경로를 담지 않는다(개인정보 원칙)", async () => {
  const batches = fakeBatches(() => {
    throw new Error("실패");
  });
  const result = await deleteTombstones(
    fakeCollection(2),
    batches.newBatch,
    chunkArray,
  );
  const serialized = JSON.stringify(result);
  assert.ok(
    !serialized.includes("doc-"),
    `반환값에 문서 ID가 새면 안 된다: ${serialized}`,
  );
  assert.ok(
    !serialized.includes("users/"),
    `반환값에 경로가 새면 안 된다: ${serialized}`,
  );
});
