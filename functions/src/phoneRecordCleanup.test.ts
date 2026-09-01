/**
 * phoneRecordCleanup.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를
 * 쓴다 — tombstoneCleanup.test.ts/cardPhotoCleanup.test.ts와 같은 패턴.
 *
 * 무엇을 지키려는 검사인가: **탈퇴한 uid의 번호 기록이 남으면 그 번호로
 * 다시 가입할 수 없다**(`phoneOtpConfirm`이 "taken"으로 막는다). 지금은 번호
 * 확인 게이트가 꺼져 있어 실기기로는 재현되지 않으므로, **게이트를 켜기
 * 전까지 이 테스트가 유일한 방어선이다.**
 *
 * 🚨 마지막 검사(`번호해시를 결과에 담지 않는다`)는 성능이 아니라 **개인정보**
 * 검사다. 번호는 경우의 수가 좁아 해시가 새면 전수 대입이 현실적이다.
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  deletePhoneRecords,
  type PhoneAccountQuery,
  type PhoneRecordBatch,
} from "./phoneRecordCleanup";

/** 번호해시 `hashes`를 가진 가짜 질의(이미 uid로 좁혀졌다고 본다). */
function fakeAccounts(hashes: string[], onGet?: () => never): PhoneAccountQuery {
  return {
    async get() {
      if (onGet) onGet();
      return {docs: hashes.map((h) => ({id: h, ref: `account-${h}`}))};
    },
  };
}

/** 커밋 횟수와 삭제된 ref를 기록하는 가짜 배치 팩토리. */
function fakeBatches(onCommit?: () => never): {
  newBatch: () => PhoneRecordBatch;
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

const challengeRefFor = (hash: string) => `challenge-${hash}`;

test("번호 기록과 같은 키의 챌린지를 함께 지운다", async () => {
  const b = fakeBatches();
  const r = await deletePhoneRecords(
    fakeAccounts(["h1"]),
    challengeRefFor,
    b.newBatch,
  );

  assert.equal(r.deleted, 1);
  assert.equal(r.errorType, undefined);
  // 계정 문서 + 같은 키의 챌린지 문서, 둘 다.
  assert.deepEqual(b.deletedRefs, ["account-h1", "challenge-h1"]);
  assert.equal(b.commits, 1);
});

test("기록이 없으면 조용히 끝난다 — 커밋도 하지 않는다", async () => {
  const b = fakeBatches();
  const r = await deletePhoneRecords(
    fakeAccounts([]),
    challengeRefFor,
    b.newBatch,
  );

  assert.deepEqual(r, {deleted: 0});
  // 빈 배치를 커밋하면 쓰기 비용만 나간다.
  assert.equal(b.commits, 0);
});

test("잘못 쌓인 기록이 여럿이어도 전부 지운다", async () => {
  const b = fakeBatches();
  const r = await deletePhoneRecords(
    fakeAccounts(["h1", "h2", "h3"]),
    challengeRefFor,
    b.newBatch,
  );

  assert.equal(r.deleted, 3);
  assert.equal(b.deletedRefs.length, 6);
  // 한 배치로 묶는다 — 중간에 끊기면 계정만 지워지고 챌린지가 남는다.
  assert.equal(b.commits, 1);
});

test("질의가 실패해도 던지지 않는다 — 탈퇴의 나머지 단계를 막지 않는다", async () => {
  const b = fakeBatches();
  const r = await deletePhoneRecords(
    fakeAccounts(["h1"], () => {
      throw new TypeError("boom");
    }),
    challengeRefFor,
    b.newBatch,
  );

  assert.equal(r.deleted, 0);
  assert.equal(r.errorType, "TypeError");
  assert.equal(b.commits, 0);
});

test("커밋이 실패해도 던지지 않는다", async () => {
  const b = fakeBatches(() => {
    throw new RangeError("nope");
  });
  const r = await deletePhoneRecords(
    fakeAccounts(["h1"]),
    challengeRefFor,
    b.newBatch,
  );

  assert.equal(r.deleted, 0);
  assert.equal(r.errorType, "RangeError");
});

test("🚨 번호해시를 결과에 담지 않는다 — 개수만 남긴다", async () => {
  const hash = "0123456789abcdef";
  const b = fakeBatches();
  const r = await deletePhoneRecords(
    fakeAccounts([hash]),
    challengeRefFor,
    b.newBatch,
  );

  // 반환값 전체를 문자열로 펴서 해시 조각이 섞여 나오지 않는지 본다.
  assert.equal(JSON.stringify(r).includes(hash), false);
  assert.equal(JSON.stringify(r).includes(hash.slice(0, 8)), false);
});
