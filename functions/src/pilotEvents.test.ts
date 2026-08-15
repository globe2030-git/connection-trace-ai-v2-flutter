/**
 * pilotEvents.ts 단위 테스트. freeGrant.test.ts/usageReset 스타일(Node
 * 내장 테스트 러너). 목적:
 * - `planActivation`: 멱등 가드와 명함 3장 임계값이 정확히 동작하는지.
 * - `kstIsoWeekCohort`: KST 기준 ISO-8601 주차 계산이 (a) UTC/KST 날짜
 *   경계를 넘나드는 순간에도 맞는지 (b) 연말/연초 ISO 주차 귀속 규칙을
 *   지키는지. 기대값은 Python `datetime.date.isocalendar()`(표준 라이브러리
 *   ISO 8601 구현)로 각 KST 날짜를 독립적으로 계산해 얻었다 — 이 파일의
 *   구현과 같은 코드로 자기 자신을 검증하는 순환 논리를 피하기 위함.
 * 실행: `npm run build && node --test lib/pilotEvents.test.js`
 * (`npm test`가 다른 테스트와 함께 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  ACTIVATION_MIN_CONTACTS,
  kstIsoWeekCohort,
  planActivation,
} from "./pilotEvents";

test("planActivation: 이미 활성화됐으면 명함이 아무리 많아도 다시 기록 안 함(멱등)", () => {
  const plan = planActivation({alreadyActivated: true, contactCount: 100});
  assert.equal(plan.shouldRecord, false);
});

test("planActivation: 명함 3장 미만이면 기록 안 함", () => {
  assert.equal(
    planActivation({alreadyActivated: false, contactCount: 0}).shouldRecord,
    false
  );
  assert.equal(
    planActivation({alreadyActivated: false, contactCount: 2}).shouldRecord,
    false
  );
});

test("planActivation: 명함 정확히 3장(임계값)이면 기록함", () => {
  const plan = planActivation({alreadyActivated: false, contactCount: 3});
  assert.equal(plan.shouldRecord, true);
});

test("planActivation: 명함 3장 초과여도 기록함", () => {
  const plan = planActivation({alreadyActivated: false, contactCount: 50});
  assert.equal(plan.shouldRecord, true);
});

test("ACTIVATION_MIN_CONTACTS는 3(리퍼럴 활성화의 '1장'과 다른 별개 지표)", () => {
  assert.equal(ACTIVATION_MIN_CONTACTS, 3);
});

test("kstIsoWeekCohort: 2026-08-15(오늘, KST 정오) → 2026-W33", () => {
  // KST 2026-08-15T12:00:00+09:00 = UTC 2026-08-15T03:00:00Z
  const week = kstIsoWeekCohort(new Date("2026-08-15T03:00:00.000Z"));
  assert.equal(week, "2026-W33");
});

test("kstIsoWeekCohort: UTC 전날인데 KST로는 이미 다음 날(경계 넘김) — KST 날짜 기준으로 계산", () => {
  // UTC 2026-08-14T20:00:00Z = KST 2026-08-15T05:00:00+09:00.
  // UTC만 보면 8/14이지만 KST로는 8/15이므로 8/15의 주차(2026-W33)여야 한다.
  const week = kstIsoWeekCohort(new Date("2026-08-14T20:00:00.000Z"));
  assert.equal(week, "2026-W33");
});

test("kstIsoWeekCohort: 연말(2025-12-31, KST)이 다음 해 1주차로 귀속(ISO 목요일 규칙)", () => {
  // KST 2025-12-31T02:00:00+09:00 = UTC 2025-12-30T17:00:00Z(UTC로는 12/30,
  // 연도 경계까지 함께 넘는 극단 케이스).
  const week = kstIsoWeekCohort(new Date("2025-12-30T17:00:00.000Z"));
  assert.equal(week, "2026-W01");
});

test("kstIsoWeekCohort: 2026-01-01(신정, KST)도 같은 2026-W01", () => {
  // KST 2026-01-01T02:00:00+09:00 = UTC 2025-12-31T17:00:00Z.
  const week = kstIsoWeekCohort(new Date("2025-12-31T17:00:00.000Z"));
  assert.equal(week, "2026-W01");
});

test("kstIsoWeekCohort: 2026-12-31(KST)은 2026-W53(53주짜리 해)", () => {
  // KST 2026-12-31T10:00:00+09:00 = UTC 2026-12-31T01:00:00Z.
  const week = kstIsoWeekCohort(new Date("2026-12-31T01:00:00.000Z"));
  assert.equal(week, "2026-W53");
});

test("kstIsoWeekCohort: 2027-01-04(KST)는 2027-W01로 귀속(해가 바뀐 뒤 첫 목요일 포함 주)", () => {
  // KST 2027-01-04T01:00:00+09:00 = UTC 2027-01-03T16:00:00Z(경계 넘김).
  const week = kstIsoWeekCohort(new Date("2027-01-03T16:00:00.000Z"));
  assert.equal(week, "2027-W01");
});
