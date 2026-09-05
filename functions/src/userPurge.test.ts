import {test} from "node:test";
import assert from "node:assert/strict";
import {
  purgeUidScopedData,
  UID_SCOPED_TOP_LEVEL_DOCS,
} from "./userPurge";

function fakes(over: Partial<{tomb: () => Promise<{deleted: number; errorType?: string}>}> = {}) {
  const calls: string[] = [];
  return {
    calls,
    deps: {
      deleteTombstones: over.tomb ?? (async (p: string) => {
        calls.push(`tomb:${p}`);
        return {deleted: 3};
      }),
      recursiveDelete: async (p: string) => {
        calls.push(`rec:${p}`);
      },
      deleteTopLevelDoc: async (c: string, uid: string) => {
        calls.push(`doc:${c}/${uid}`);
      },
    },
  };
}

test("🚨 users/{uid} 를 recursiveDelete 한다 — cardSources 가 여기서 지워진다", async () => {
  const f = fakes();
  await purgeUidScopedData("u1", f.deps);
  assert.ok(
    f.calls.includes("rec:users/u1"),
    "users/{uid} 를 통째로 안 지우면 하위 컬렉션(cardSources·contacts·commLogs)이 남는다"
  );
});

test("🚨 ocrStats/{uid} 를 지운다 — 탈퇴 경로에 없던 것", async () => {
  const f = fakes();
  const r = await purgeUidScopedData("u1", f.deps);
  assert.ok(f.calls.includes("doc:ocrStats/u1"));
  assert.deepEqual(r.topLevelDeleted, ["ocrStats"]);
});

test("uid 스코프 최상위 목록을 고정한다 — 늘면 이 테스트를 함께 고칠 것", () => {
  assert.deepEqual([...UID_SCOPED_TOP_LEVEL_DOCS], ["ocrStats"]);
});

test("묘비를 먼저 세면서 지우고 그다음 나머지를 덮는다 (파기 기록이 남아야 한다)", async () => {
  const f = fakes();
  const r = await purgeUidScopedData("u1", f.deps);
  assert.equal(r.tombstonesDeleted, 3);
  assert.ok(
    f.calls.indexOf("tomb:users/u1/deletedContacts") <
      f.calls.indexOf("rec:users/u1"),
    "recursiveDelete 가 먼저 돌면 셀 것이 없어져 파기 기록이 0으로 남는다"
  );
});

test("⚠️ 묘비 정리가 실패해도 나머지는 진행한다", async () => {
  const f = fakes({
    tomb: async () => ({deleted: 0, errorType: "Boom"}),
  });
  const r = await purgeUidScopedData("u1", f.deps);
  assert.equal(r.tombstoneErrorType, "Boom");
  assert.ok(f.calls.includes("rec:users/u1"), "실패했다고 멈추면 개인정보가 남는다");
  assert.ok(f.calls.includes("doc:ocrStats/u1"));
});

test("⚠️ 묘비 정리가 던져도 삼키고 나머지를 진행한다", async () => {
  const f = fakes({
    tomb: async () => {
      throw new TypeError("nope");
    },
  });
  const r = await purgeUidScopedData("u1", f.deps);
  assert.equal(r.tombstoneErrorType, "TypeError");
  assert.ok(f.calls.includes("rec:users/u1"));
});
