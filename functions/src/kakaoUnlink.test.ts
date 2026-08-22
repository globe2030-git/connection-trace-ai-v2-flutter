import assert from "node:assert/strict";
import test from "node:test";

import {
  adminKeyMatches,
  appIdAllowed,
  parseKakaoUnlinkPayload,
} from "./kakaoUnlink";

const KEY = "abcdef0123456789abcdef0123456789";

test("adminKeyMatches: 올바른 헤더는 통과한다", () => {
  assert.equal(adminKeyMatches(`KakaoAK ${KEY}`, KEY), true);
});

test("adminKeyMatches: 앞뒤 공백은 무시한다", () => {
  assert.equal(adminKeyMatches(`  KakaoAK ${KEY}  `, KEY), true);
});

test("adminKeyMatches: 키가 다르면 막는다", () => {
  assert.equal(adminKeyMatches(`KakaoAK ${KEY}x`, KEY), false);
  assert.equal(adminKeyMatches("KakaoAK 다른키", KEY), false);
});

test("adminKeyMatches: 접두사가 없거나 다르면 막는다", () => {
  assert.equal(adminKeyMatches(KEY, KEY), false);
  assert.equal(adminKeyMatches(`Bearer ${KEY}`, KEY), false);
  assert.equal(adminKeyMatches(`kakaoak ${KEY}`, KEY), false);
});

test("adminKeyMatches: 헤더가 없으면 막는다", () => {
  assert.equal(adminKeyMatches(undefined, KEY), false);
  assert.equal(adminKeyMatches(null, KEY), false);
  assert.equal(adminKeyMatches("", KEY), false);
});

test("⚠️ adminKeyMatches: 기대값이 비어 있으면 무엇도 통과시키지 않는다", () => {
  // 시크릿이 안 붙은 채 배포되면 검증이 통째로 무력해진다. 그 상태를
  // "통과"로 두면 누구나 남의 계정을 지울 수 있다.
  assert.equal(adminKeyMatches("KakaoAK ", ""), false);
  assert.equal(adminKeyMatches("KakaoAK 아무거나", ""), false);
  assert.equal(adminKeyMatches("KakaoAK 아무거나", undefined), false);
});

test("parseKakaoUnlinkPayload: POST 본문에서 읽는다", () => {
  const p = parseKakaoUnlinkPayload({
    app_id: "123456",
    user_id: "987654321",
    referrer_type: "UNLINK_FROM_APPS",
  });
  assert.deepEqual(p, {
    userId: "987654321",
    appId: "123456",
    referrerType: "UNLINK_FROM_APPS",
  });
});

test("parseKakaoUnlinkPayload: GET 질의문자열에서도 읽는다", () => {
  const p = parseKakaoUnlinkPayload(undefined, {
    user_id: "987654321",
    referrer_type: "ACCOUNT_DELETE",
  });
  assert.equal(p?.userId, "987654321");
  assert.equal(p?.referrerType, "ACCOUNT_DELETE");
  assert.equal(p?.appId, null);
});

test("parseKakaoUnlinkPayload: 앞선 source가 이긴다", () => {
  const p = parseKakaoUnlinkPayload({user_id: "111"}, {user_id: "222"});
  assert.equal(p?.userId, "111");
});

test("parseKakaoUnlinkPayload: 회원번호가 없으면 null", () => {
  assert.equal(parseKakaoUnlinkPayload({referrer_type: "ACCOUNT_DELETE"}), null);
  assert.equal(parseKakaoUnlinkPayload({user_id: "   "}), null);
  assert.equal(parseKakaoUnlinkPayload(undefined, null), null);
});

test("⚠️ parseKakaoUnlinkPayload: 회원번호를 문자열 그대로 둔다", () => {
  // 숫자로 바꾸면 큰 회원번호가 뭉개져 **다른 사람 계정을 지우게 된다**.
  const big = "9007199254740993"; // 2^53 + 1
  const p = parseKakaoUnlinkPayload({user_id: big});
  assert.equal(p?.userId, big);
});

test("parseKakaoUnlinkPayload: 숫자로 와도 문자열로 만든다", () => {
  const p = parseKakaoUnlinkPayload({user_id: 987654321});
  assert.equal(p?.userId, "987654321");
});

test("appIdAllowed: 같으면 통과", () => {
  assert.equal(appIdAllowed("123456", "123456"), true);
});

test("appIdAllowed: 다르면 막는다", () => {
  assert.equal(appIdAllowed("123456", "999999"), false);
});

test("appIdAllowed: 기대값이 없거나 페이로드에 없으면 막지 않는다", () => {
  // 여기서 막으면 설정이 덜 된 상태에서 파기가 통째로 멈춘다 — 그건
  // "안 지워져 남는" 쪽으로 틀리는 것이다. 인증은 어드민 키가 한다.
  assert.equal(appIdAllowed("123456", ""), true);
  assert.equal(appIdAllowed("123456", undefined), true);
  assert.equal(appIdAllowed(null, "123456"), true);
});
