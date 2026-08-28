/**
 * phoneOtpSender.ts 단위 테스트.
 *
 * 🚨 **덮는 것은 순수 함수뿐이다** — 파라미터를 만들고, 문안을 채우고,
 * 응답을 읽는 것. `AligoSender`는 HTTP를 타므로 여기서 안 돌린다.
 *
 * 📌 그런데 **이 파일에서 틀리기 쉬운 것이 정확히 그 순수 부분**이다.
 * 알리고가 못박은 함정이 *"등록한 템플릿이랑 개행문자 포함 동일하게"*라서,
 * 문안이 한 글자라도 어긋나면 발송이 통째로 거부된다.
 *
 * 실행: `npm run build && node --test lib/phoneOtpSender.test.js`
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  AligoConfig,
  OTP_FAILOVER_BODY,
  OTP_TEMPLATE_BODY,
  OTP_TEMPLATE_VARIABLE,
  NoKeySender,
  buildAligoSendPayload,
  e164ToKrLocal,
  readAligoResult,
  renderOtpMessage,
} from "./phoneOtpSender";
import {OTP_TTL_MS} from "./phoneOtp";

const CONFIG: AligoConfig = {
  apikey: "test-apikey",
  userid: "test-userid",
  senderkey: "test-senderkey",
  tplCode: "TPL_TEST",
  sender: "0212345678",
  testMode: true,
};

// ---- 템플릿 문안 ----

test("템플릿 본문에 변수가 정확히 한 번 들어 있다", () => {
  const count = OTP_TEMPLATE_BODY.split(OTP_TEMPLATE_VARIABLE).length - 1;
  assert.equal(count, 1);
});

test("🚨 문안의 「3분」이 OTP_TTL_MS와 맞는다 — 어긋나면 템플릿 재심사다", () => {
  // 이 테스트가 지키는 것: 누가 TTL을 바꾸고 문안을 안 바꾸는 일.
  // 문안은 카카오 심사를 통과한 것이라 바꾸면 영업일 2일이 든다.
  const minutes = OTP_TTL_MS / 60_000;
  assert.ok(
    OTP_TEMPLATE_BODY.includes(`${minutes}분 안에`),
    `문안에 "${minutes}분 안에"가 없다. TTL을 바꿨다면 문안도 바꾸고 재심사를 받아야 한다.`,
  );
  assert.ok(OTP_FAILOVER_BODY.includes(`${minutes}분 안에`));
});

test("renderOtpMessage: 변수만 바뀌고 나머지는 한 글자도 안 바뀐다", () => {
  const out = renderOtpMessage("123456", OTP_TEMPLATE_BODY);
  assert.equal(out.includes(OTP_TEMPLATE_VARIABLE), false);
  assert.ok(out.includes("요청하신 인증번호는 123456 입니다."));
  // 개행 수가 같아야 한다 — 알리고가 개행까지 대조한다.
  const nlBefore = (OTP_TEMPLATE_BODY.match(/\n/g) ?? []).length;
  const nlAfter = (out.match(/\n/g) ?? []).length;
  assert.equal(nlAfter, nlBefore);
  // 길이 차이는 변수 길이 차이뿐이어야 한다.
  assert.equal(
    out.length,
    OTP_TEMPLATE_BODY.length - OTP_TEMPLATE_VARIABLE.length + "123456".length,
  );
});

test("renderOtpMessage: 앞자리 0 코드도 그대로 들어간다", () => {
  const out = renderOtpMessage("000123", OTP_TEMPLATE_BODY);
  assert.ok(out.includes("인증번호는 000123 입니다."));
});

// ---- 번호 모양 ----

test("e164ToKrLocal: 알리고가 받는 국내 모양으로 되돌린다", () => {
  assert.equal(e164ToKrLocal("+821012345678"), "01012345678");
});

test("e164ToKrLocal: +82가 아니면 그대로 둔다", () => {
  assert.equal(e164ToKrLocal("01012345678"), "01012345678");
});

// ---- 발송 파라미터 ----

test("buildAligoSendPayload: 공식 예제의 키 이름을 그대로 쓴다", () => {
  const p = buildAligoSendPayload(CONFIG, "tok", "+821012345678", "123456");
  for (const key of [
    "apikey",
    "userid",
    "token",
    "senderkey",
    "tpl_code",
    "sender",
    "receiver_1",
    "subject_1",
    "message_1",
  ]) {
    assert.ok(key in p, `필수 키 ${key}가 없다`);
  }
});

test("buildAligoSendPayload: 수신번호를 국내 모양으로 넣는다", () => {
  const p = buildAligoSendPayload(CONFIG, "tok", "+821012345678", "123456");
  // 🚨 E.164를 그대로 넣으면 알리고가 못 받는다.
  assert.equal(p.receiver_1, "01012345678");
});

test("buildAligoSendPayload: ⚠️ failover를 항상 Y로 준다", () => {
  // 공식 예제 주석: "템플릿 신청시 대체문자 발송으로 설정하였더라도
  // Y로 입력해야합니다." — 둘 다 해야 한다.
  const p = buildAligoSendPayload(CONFIG, "tok", "+821012345678", "123456");
  assert.equal(p.failover, "Y");
  assert.ok(p.fmessage_1.includes("123456"));
});

test("buildAligoSendPayload: testMode가 설정을 그대로 따른다", () => {
  const on = buildAligoSendPayload(CONFIG, "t", "+821012345678", "1");
  assert.equal(on.testMode, "Y");
  const off = buildAligoSendPayload(
    {...CONFIG, testMode: false},
    "t",
    "+821012345678",
    "1",
  );
  assert.equal(off.testMode, "N");
});

test("buildAligoSendPayload: 본문이 렌더된 템플릿과 정확히 같다", () => {
  const p = buildAligoSendPayload(CONFIG, "tok", "+821012345678", "654321");
  assert.equal(p.message_1, renderOtpMessage("654321", OTP_TEMPLATE_BODY));
});

// ---- 응답 읽기 ----

test("readAligoResult: code 0이 성공이다", () => {
  assert.deepEqual(readAligoResult({code: 0, message: "성공"}), {
    ok: true,
    message: "성공",
  });
});

test("readAligoResult: ⚠️ HTTP 200이어도 code가 0이 아니면 실패다", () => {
  const r = readAligoResult({code: -101, message: "인증오류"});
  assert.equal(r.ok, false);
  assert.equal(r.message, "인증오류");
});

test("readAligoResult: code가 문자열로 와도 읽는다", () => {
  assert.equal(readAligoResult({code: "0"}).ok, true);
});

test("readAligoResult: 응답이 이상하면 실패로 본다", () => {
  assert.equal(readAligoResult(null).ok, false);
  assert.equal(readAligoResult("nope").ok, false);
  assert.equal(readAligoResult({}).ok, false);
});

// ---- 키가 없을 때 ----

test("NoKeySender: 🚨 조용히 성공하지 않는다", () => {
  // 성공을 돌려주면 "문자가 안 오는데 화면은 넘어가는" 상태가 된다.
  // 그건 고장보다 나쁘다 — 이용자가 무엇이 잘못됐는지 알 수 없다.
  return new NoKeySender().send().then((r) => {
    assert.equal(r.sent, false);
  });
});
