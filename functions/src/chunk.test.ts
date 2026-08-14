/**
 * chunk.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를 쓴다 —
 * usageReset.test.ts/creditGrant.test.ts와 같은 패턴. 실행:
 * `npm run build && node --test lib/chunk.test.js`
 * (package.json의 `npm test`가 이 파일도 포함하도록 갱신돼 있다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {chunkArray} from "./chunk";

test("빈 배열은 빈 배열을 반환한다", () => {
  assert.deepEqual(chunkArray([], 400), []);
});

test("크기보다 작은 배열은 청크 하나에 다 들어간다", () => {
  assert.deepEqual(chunkArray([1, 2, 3], 400), [[1, 2, 3]]);
});

test("정확히 나눠떨어지는 크기는 균등하게 나눈다", () => {
  assert.deepEqual(chunkArray([1, 2, 3, 4], 2), [[1, 2], [3, 4]]);
});

test("나눠떨어지지 않으면 마지막 청크가 더 작다", () => {
  assert.deepEqual(chunkArray([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
});

test("400건 단위 경계값 — 401건이면 청크 2개(400+1)", () => {
  const arr = Array.from({length: 401}, (_, i) => i);
  const chunks = chunkArray(arr, 400);
  assert.equal(chunks.length, 2);
  assert.equal(chunks[0].length, 400);
  assert.equal(chunks[1].length, 1);
});

test("size가 0 이하이면 에러를 던진다", () => {
  assert.throws(() => chunkArray([1, 2], 0));
  assert.throws(() => chunkArray([1, 2], -1));
});
