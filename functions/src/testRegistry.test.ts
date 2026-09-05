import {test} from "node:test";
import assert from "node:assert/strict";
import {readdirSync, readFileSync} from "node:fs";

/**
 * `npm test` 의 파일 목록과 실제 테스트 파일이 어긋나지 않는지 본다.
 *
 * ## 🚨 왜 필요한가 — #830 과 같은 뿌리가 한 층 아래에 있다
 *
 * `package.json` 의 `test` 스크립트는 **glob 이 아니라 파일 이름을 손으로
 * 나열한다.**
 *
 * ```
 * "test": "tsc && node --test lib/usageReset.test.js lib/briefingPrompt.test.js …"
 * ```
 *
 * 새 테스트 파일을 만들고 그 줄에 안 적으면 **조용히 영원히 안 돈다.**
 * ⚠️ `#830` 이 고친 것이 *"`npm test` 에 등록됐는데 **CI 가** 한 번도 안
 * 불렀다"* 였는데, 남은 것은 *"파일은 있는데 **`npm test` 가** 안 부른다"* 다.
 * **같은 모양이 한 층 아래에서 살아 있었다.**
 *
 * 📌 **어긋나도 아무 신호가 없다는 것이 핵심이다.** 테스트가 줄어드는 것은
 * 빨간불이 아니라 **조용함**으로 나타난다.
 *
 * ## ⚠️ 이 파일도 목록에 있어야 한다
 *
 * 자기가 지키는 목록 안에 자기가 들어 있어야 돈다. 빠지면 이 검사 자체가
 * 안 돌고, **그러면 아무도 안 지킨다.** 🚨 그러니 이 파일을 목록에서 빼지 말 것.
 */
test("npm test 목록과 실제 테스트 파일이 일치한다", () => {
  const pkg = JSON.parse(readFileSync("package.json", "utf8")) as {
    scripts: {test: string};
  };
  const listed = new Set(
    [...pkg.scripts.test.matchAll(/lib\/(\w+)\.test\.js/g)].map((m) => m[1])
  );
  const onDisk = new Set(
    readdirSync("src")
      .filter((f) => f.endsWith(".test.ts"))
      .map((f) => f.slice(0, -".test.ts".length))
  );

  const notRun = [...onDisk].filter((n) => !listed.has(n)).sort();
  const missing = [...listed].filter((n) => !onDisk.has(n)).sort();

  assert.deepEqual(
    notRun,
    [],
    `🚨 테스트 파일은 있는데 npm test 가 안 부른다: ${notRun.join(", ")}\n` +
      "→ package.json 의 test 스크립트에 lib/<이름>.test.js 를 더할 것"
  );
  assert.deepEqual(
    missing,
    [],
    `⚠️ npm test 가 부르는데 파일이 없다: ${missing.join(", ")}\n` +
      "→ 지운 테스트라면 package.json 에서도 지울 것"
  );
});
