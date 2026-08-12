/**
 * usageReset.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를 쓴다 —
 * 이 프로젝트(functions/)엔 jest 등 별도 테스트 프레임워크가 없고, 순수 계산
 * 함수 몇 개를 검증하는 데 새 의존성을 들일 필요가 없어 Node 내장 기능만
 * 썼다. 실행: `npm run build && node --test lib/usageReset.test.js`
 * (package.json의 `npm test`가 위 두 단계를 묶어 실행한다).
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {nextKstMidnight, nextKstMonthStart} from "./usageReset";

// KST = UTC+9. "2026-08-11T15:00:00Z" 표기는 UTC 시각이고, 뒤에 KST 환산 시각을
// 주석으로 함께 적는다.

test("KST 자정 직전 — 자정까지 몇 초 안 남았어도 아직 오늘이면 다음 자정은 내일", () => {
  // 2026-08-11 23:59:59.000 KST = 2026-08-11T14:59:59Z
  const now = new Date("2026-08-11T14:59:59.000Z");
  const result = nextKstMidnight(now);
  // 다음 자정은 2026-08-12 00:00:00 KST = 2026-08-11T15:00:00Z
  assert.equal(result.toISOString(), "2026-08-11T15:00:00.000Z");
});

test("KST 자정 직후 — 방금 자정을 넘겼으면 다음 자정은 24시간 뒤(내일 자정)", () => {
  // 2026-08-12 00:00:01 KST = 2026-08-11T15:00:01Z
  const now = new Date("2026-08-11T15:00:01.000Z");
  const result = nextKstMidnight(now);
  // 다음 자정은 2026-08-13 00:00:00 KST = 2026-08-12T15:00:00Z
  assert.equal(result.toISOString(), "2026-08-12T15:00:00.000Z");
});

test("정확히 KST 자정인 순간에도 '다음' 자정은 24시간 뒤여야 한다(원래 setHours(24,..) 의미 보존)", () => {
  // 2026-08-12 00:00:00.000 KST = 2026-08-11T15:00:00.000Z
  const now = new Date("2026-08-11T15:00:00.000Z");
  const result = nextKstMidnight(now);
  assert.equal(result.toISOString(), "2026-08-12T15:00:00.000Z");
});

test("UTC 자정과 KST 자정이 다른 날짜가 되는 시각 — KST 08:00은 전날 UTC 23:00", () => {
  // 2026-08-12 08:00:00 KST = 2026-08-11T23:00:00Z. UTC로는 아직 8/11이지만
  // KST로는 이미 8/12이므로, 다음 KST 자정은 8/13 00:00 KST여야 한다(만약
  // 버그처럼 UTC 자정을 기준으로 계산했다면 8/12 00:00 UTC, 즉 KST로 이미
  // 지나버린 과거 시각을 반환해 버렸을 것이다).
  const now = new Date("2026-08-11T23:00:00.000Z");
  const result = nextKstMidnight(now);
  // 2026-08-13 00:00:00 KST = 2026-08-12T15:00:00Z
  assert.equal(result.toISOString(), "2026-08-12T15:00:00.000Z");
  // 회귀 방지: 이전(버그) 로직이 반환했을 "UTC 자정" 값이 아니어야 한다.
  assert.notEqual(result.toISOString(), "2026-08-12T00:00:00.000Z");
});

test("월말 → 월초 경계 — 8월 31일 KST 밤이면 다음 달 시작은 9월 1일 KST", () => {
  // 2026-08-31 23:30:00 KST = 2026-08-31T14:30:00Z
  const now = new Date("2026-08-31T14:30:00.000Z");
  const result = nextKstMonthStart(now);
  // 2026-09-01 00:00:00 KST = 2026-08-31T15:00:00Z
  assert.equal(result.toISOString(), "2026-08-31T15:00:00.000Z");
});

test("연말 경계 — 12월 31일 KST 밤이면 다음 달 시작은 다음 해 1월 1일 KST", () => {
  // 2026-12-31 23:30:00 KST = 2026-12-31T14:30:00Z
  const now = new Date("2026-12-31T14:30:00.000Z");
  const result = nextKstMonthStart(now);
  // 2027-01-01 00:00:00 KST = 2026-12-31T15:00:00Z
  assert.equal(result.toISOString(), "2026-12-31T15:00:00.000Z");
});

test("연말 경계 — UTC로는 아직 12월 31일이지만 KST로는 이미 1월 1일인 시각", () => {
  // 2027-01-01 07:00:00 KST = 2026-12-31T22:00:00Z. UTC 기준 월 계산이었다면
  // 여전히 "12월"로 취급해 다음 달 시작을 2027-02-01로 잘못 반환했을 것이다.
  const now = new Date("2026-12-31T22:00:00.000Z");
  const result = nextKstMonthStart(now);
  // 2027-02-01 00:00:00 KST = 2027-01-31T15:00:00Z
  assert.equal(result.toISOString(), "2027-01-31T15:00:00.000Z");
});

test("월초 직후(KST) — 이번 달이 막 시작했어도 다음 달 시작을 가리켜야 한다", () => {
  // 2026-03-01 00:00:05 KST = 2026-02-28T15:00:05Z
  const now = new Date("2026-02-28T15:00:05.000Z");
  const result = nextKstMonthStart(now);
  // 2026-04-01 00:00:00 KST = 2026-03-31T15:00:00Z
  assert.equal(result.toISOString(), "2026-03-31T15:00:00.000Z");
});
