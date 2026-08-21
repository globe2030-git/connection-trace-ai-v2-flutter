/**
 * socialAuth.ts 단위 테스트. Node 22 내장 테스트 러너(`node:test`)를 쓴다 —
 * creditGrant.test.ts와 같은 패턴. 실행:
 * `npm run build && node --test lib/socialAuth.test.js`
 *
 * ## 이 테스트가 막는 것
 *
 * **① 계정이 섞이는 사고.** 카카오 회원번호와 네이버 회원번호는 서로 다른
 * 체계라 우연히 같은 값이 나올 수 있다. uid에 제공자 접두사가 빠지면 **남의
 * 명함이 통째로 보인다.** 이 앱은 제3자 개인정보를 담으므로 그중 최악이다.
 *
 * **② 최소수집 위반.** 카카오·네이버는 요청하면 휴대전화·생년월일까지 준다.
 * 응답에 섞여 들어와도 **우리 프로필에 실리면 안 된다** — 실리는 순간 방침·
 * 파기·국외이전 서술이 전부 늘어난다.
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {
  socialUid,
  parseKakaoUser,
  parseNaverUser,
  firebaseUserFields,
  tokenClaims,
  validateRequest,
  tokenEndpoint,
  tokenExchangeBody,
  parseTokenResponse,
  isTesterAllowed,
} from "./socialAuth";

test("⭐ uid에 제공자 접두사가 붙는다 — 계정이 섞이면 남의 명함이 보인다", () => {
  assert.equal(socialUid("kakao", "12345"), "kakao:12345");
  assert.equal(socialUid("naver", "12345"), "naver:12345");
  // 회원번호가 같아도 uid는 달라야 한다.
  assert.notEqual(socialUid("kakao", "12345"), socialUid("naver", "12345"));
});

test("uid: 회원번호가 비면 거부한다", () => {
  assert.throws(() => socialUid("kakao", ""));
  assert.throws(() => socialUid("kakao", "   "));
});

test("uid: 앞뒤 공백은 떼고 만든다 — 같은 사람이 두 계정이 되면 안 된다", () => {
  assert.equal(socialUid("kakao", "  12345  "), "kakao:12345");
});

test("카카오: 정상 응답을 프로필로 바꾼다", () => {
  const p = parseKakaoUser({
    id: 1234567890,
    kakao_account: {
      email: "someone@example.com",
      profile: {
        nickname: "홍길동",
        profile_image_url: "https://example.com/a.png",
      },
    },
  });
  assert.equal(p.uid, "kakao:1234567890");
  assert.equal(p.provider, "kakao");
  assert.equal(p.email, "someone@example.com");
  assert.equal(p.displayName, "홍길동");
  assert.equal(p.photoUrl, "https://example.com/a.png");
});

test("⚠️ 카카오: id가 숫자로 와도 문자열로 고정한다", () => {
  // uid는 문자열이어야 한다. 숫자로 들고 다니면 다루는 곳마다 형이 갈린다.
  const p = parseKakaoUser({id: 1234567890, kakao_account: {}});
  assert.equal(typeof p.uid, "string");
  assert.equal(p.uid, "kakao:1234567890");
});

test("⚠️ 카카오: 2^53을 넘는 id의 정밀도는 지켜 주지 못한다(한계를 못박는다)", () => {
  // 이 테스트는 "된다"가 아니라 **"안 된다"** 를 고정한다.
  //
  // 예전 테스트는 9007199254740993 을 넣고 문자열이 됐는지만 봤다. 그런데
  // 그 리터럴은 자바스크립트가 읽는 순간 이미 ...992 로 반올림된다. 즉
  // **반올림된 값이 문자열이 된 것**을 보고 "정밀도를 지켰다"고 읽고 있었다.
  //
  // 실제 응답도 res.json() 이 double 로 바꾼 뒤에 오므로 사정이 같다.
  // 여기서 못박아 두면, 언젠가 진짜로 큰 회원번호가 필요해졌을 때
  // "이미 되는 줄 알았다"로 넘어가지 않는다.
  const p = parseKakaoUser({id: 9007199254740993, kakao_account: {}});
  assert.equal(p.uid, "kakao:9007199254740992"); // ⚠️ ...993 이 아니다
});

test("⚠️ 카카오: 이메일이 없어도 로그인을 막지 않는다", () => {
  // 이메일 제공에 동의하지 않은 계정이 실제로 있다.
  const p = parseKakaoUser({id: 42, kakao_account: {profile: {nickname: "가"}}});
  assert.equal(p.email, null);
  assert.equal(p.uid, "kakao:42");
});

test("카카오: 회원번호가 없으면 거부한다", () => {
  assert.throws(() => parseKakaoUser({kakao_account: {}}));
  assert.throws(() => parseKakaoUser({}));
  assert.throws(() => parseKakaoUser(null));
});

test("⭐ 카카오: 휴대전화·생년월일이 와도 프로필에 안 실린다", () => {
  const p = parseKakaoUser({
    id: 7,
    kakao_account: {
      email: "a@b.com",
      phone_number: "+82 10-0000-0000",
      birthday: "0101",
      birthyear: "1990",
      gender: "male",
      age_range: "30~39",
      profile: {nickname: "닉"},
    },
  });
  // 프로필에 담기는 것은 넷뿐이다.
  assert.deepEqual(Object.keys(p).sort(), [
    "displayName",
    "email",
    "photoUrl",
    "provider",
    "uid",
  ]);
  assert.equal(JSON.stringify(p).includes("0000"), false);
  assert.equal(JSON.stringify(p).includes("1990"), false);
});

test("네이버: 정상 응답을 프로필로 바꾼다", () => {
  const p = parseNaverUser({
    resultcode: "00",
    message: "success",
    response: {
      id: "abcdef",
      email: "someone@example.com",
      nickname: "닉네임",
      profile_image: "https://example.com/b.png",
    },
  });
  assert.equal(p.uid, "naver:abcdef");
  assert.equal(p.provider, "naver");
  assert.equal(p.displayName, "닉네임");
});

test("⚠️ 네이버: resultcode가 00이 아니면 거부한다 — 실패도 HTTP 200으로 온다", () => {
  assert.throws(() =>
    parseNaverUser({resultcode: "024", message: "Authentication failed"})
  );
  assert.throws(() => parseNaverUser({response: {id: "x"}}));
});

test("⭐ 네이버: 실명(name)이 아니라 닉네임을 쓴다", () => {
  const p = parseNaverUser({
    resultcode: "00",
    response: {id: "u1", name: "김실명", nickname: "닉", email: "a@b.com"},
  });
  assert.equal(p.displayName, "닉");
  assert.equal(JSON.stringify(p).includes("김실명"), false);
});

test("⭐ 네이버: 휴대전화·생년월일이 와도 프로필에 안 실린다", () => {
  const p = parseNaverUser({
    resultcode: "00",
    response: {
      id: "u2",
      mobile: "010-0000-0000",
      birthday: "01-01",
      birthyear: "1990",
      gender: "M",
      age: "30-39",
      nickname: "닉",
    },
  });
  assert.equal(JSON.stringify(p).includes("0000"), false);
  assert.equal(JSON.stringify(p).includes("1990"), false);
});

test("Firebase 필드: 값이 없으면 키 자체를 안 넣는다", () => {
  const f = firebaseUserFields({
    uid: "kakao:1",
    provider: "kakao",
    email: null,
    displayName: null,
    photoUrl: null,
  });
  assert.deepEqual(f, {});
});

test("⚠️ Firebase 필드: http 사진 주소는 버린다 — 평문 요청이 나간다", () => {
  const f = firebaseUserFields({
    uid: "kakao:1",
    provider: "kakao",
    email: "a@b.com",
    displayName: "닉",
    photoUrl: "http://example.com/x.png",
  });
  assert.equal(f.photoURL, undefined);
  assert.equal(f.email, "a@b.com");
});

test("⭐ 커스텀 토큰 claims에 개인정보를 넣지 않는다", () => {
  const c = tokenClaims({
    uid: "naver:1",
    provider: "naver",
    email: "a@b.com",
    displayName: "닉",
    photoUrl: "https://x/y.png",
  });
  // 제공자만 들어간다. claims는 클라이언트가 디코드해 읽을 수 있다.
  assert.deepEqual(c, {provider: "naver"});
});

test("요청 검증: provider·code·redirectUri가 있어야 한다", () => {
  const ok = {provider: "kakao", code: "c", redirectUri: "https://x/y"};
  assert.deepEqual(validateRequest(ok), {
    provider: "kakao",
    code: "c",
    redirectUri: "https://x/y",
    state: "",
  });
  assert.throws(() => validateRequest({...ok, provider: "google"}));
  assert.throws(() => validateRequest({...ok, code: "  "}));
  assert.throws(() => validateRequest({...ok, redirectUri: ""}));
  assert.throws(() => validateRequest(null));
});

test("교환 본문의 기본 모양", () => {
  const body = tokenExchangeBody({
    provider: "kakao",
    code: "c",
    clientId: "id",
    clientSecret: "s",
    redirectUri: "https://x/y",
  });
  assert.ok(body.includes("grant_type=authorization_code"));
  assert.ok(body.includes("client_id=id"));
  assert.ok(body.includes("client_secret=s"));
});

test("⭐ 카카오도 client_secret이 없으면 거부한다", () => {
  // 옛 가이드는 "카카오는 끄는 것이 기본"이었지만 지금은 아니다. 카카오 문서:
  // "REST API 키(앱과 함께 자동 생성된 키 포함)는 클라이언트 시크릿 기능이
  //  활성화된 상태로 추가됩니다. 따라서 토큰 발급 요청 시 client_secret를
  //  포함해야 합니다."
  // 없이 보내면 "로그인이 안 됨" 하나로 뭉쳐 나와 원인을 찾기 어렵다.
  assert.throws(
    () =>
      tokenExchangeBody({
        provider: "kakao",
        code: "c",
        clientId: "id",
        clientSecret: null,
        redirectUri: "https://x/y",
      }),
    /kakao/
  );
});

test("⭐ 네이버도 client_secret이 없으면 거부한다", () => {
  assert.throws(
    () =>
      tokenExchangeBody({
        provider: "naver",
        code: "c",
        clientId: "id",
        clientSecret: null,
        redirectUri: "https://x/y",
      }),
    /naver/
  );
});

test("공백만 있는 client_secret도 없는 것으로 본다", () => {
  assert.throws(() =>
    tokenExchangeBody({
      provider: "kakao",
      code: "c",
      clientId: "id",
      clientSecret: "   ",
      redirectUri: "https://x/y",
    })
  );
});

test("교환 본문: redirect_uri가 URL 인코딩돼 들어간다", () => {
  const body = tokenExchangeBody({
    provider: "naver",
    code: "c",
    clientId: "id",
    clientSecret: "s",
    redirectUri: "https://connection-sense.web.app/oauth/naver",
    state: "st",
  });
  assert.ok(body.includes("redirect_uri=https%3A%2F%2Fconnection-sense"));
  assert.ok(body.includes("client_secret=s"));
});

test("토큰 엔드포인트가 제공자별로 다르다", () => {
  assert.ok(tokenEndpoint("kakao").includes("kauth.kakao.com"));
  assert.ok(tokenEndpoint("naver").includes("nid.naver.com"));
});

test("교환 응답에서 액세스 토큰을 꺼낸다", () => {
  assert.equal(parseTokenResponse({access_token: "abc"}), "abc");
});

test("⚠️ 네이버는 실패해도 HTTP 200이다 — 본문의 error를 봐야 한다", () => {
  assert.throws(() =>
    parseTokenResponse({error: "invalid_request", error_description: "…"})
  );
  assert.throws(() => parseTokenResponse({error_code: "024"}));
  assert.throws(() => parseTokenResponse({}));
  assert.throws(() => parseTokenResponse(null));
});

test("⭐ 네이버는 토큰 요청에도 state가 필요하다 — 공식 규격의 요청 변수표", () => {
  // 카카오는 인증 단계에서만 state를 쓰지만, 네이버는 토큰 요청 변수표에도
  // state가 필수로 적혀 있다. 빠지면 교환이 실패하는데 증상은 "로그인 안 됨"
  // 하나로 뭉쳐 나온다.
  const body = tokenExchangeBody({
    provider: "naver",
    code: "c",
    clientId: "id",
    clientSecret: "s",
    redirectUri: "https://x/y",
    state: "st1",
  });
  assert.ok(body.includes("state=st1"));
});

test("네이버 토큰 요청에 state가 없으면 거부한다", () => {
  assert.throws(() =>
    tokenExchangeBody({
      provider: "naver",
      code: "c",
      clientId: "id",
      clientSecret: "s",
      redirectUri: "https://x/y",
      state: null,
    })
  );
});

test("⚠️ 카카오에는 state를 넣지 않는다 — 규격에 없는 값", () => {
  const body = tokenExchangeBody({
    provider: "kakao",
    code: "c",
    clientId: "id",
    clientSecret: "s",
    redirectUri: "https://x/y",
    state: "st1",
  });
  assert.equal(body.includes("state="), false);
});

test("요청 검증: 네이버는 state 없이 들어오면 거부한다", () => {
  assert.throws(() =>
    validateRequest({provider: "naver", code: "c", redirectUri: "https://x/y"})
  );
  assert.deepEqual(
    validateRequest({
      provider: "naver",
      code: "c",
      redirectUri: "https://x/y",
      state: "s1",
    }),
    {provider: "naver", code: "c", redirectUri: "https://x/y", state: "s1"}
  );
});

// ─────────────────────────────────────────────────────────────
// 테스터 허용목록 판정 (2026-08-21, B안)
//
// ⚠️ 계기는 실기기다 — 카카오로 로그인한 테스터가 AI 를 한 번도 못 썼다.
// 같은 이메일이 이미 다른 계정에 있어 **이메일 없이** 계정이 만들어졌고,
// 그래서 목록과 대조할 값 자체가 없었다.
// ─────────────────────────────────────────────────────────────

test("토큰 이메일이 목록에 있으면 통과", () => {
  assert.equal(
    isTesterAllowed({allowlist: ["a@x.com"], tokenEmail: "a@x.com"}),
    true,
  );
});

test("대소문자·앞뒤 공백 때문에 빠지지 않는다", () => {
  assert.equal(
    isTesterAllowed({allowlist: [" A@X.com "], tokenEmail: "a@x.COM"}),
    true,
  );
});

test("⚠️ 토큰에 이메일이 없으면 서버에 적어 둔 값으로 본다 (카카오·네이버)", () => {
  // 이 한 줄이 없으면 카카오·네이버 테스터는 AI 를 못 쓴다.
  assert.equal(
    isTesterAllowed({
      allowlist: ["a@x.com"],
      tokenEmail: null,
      storedEmail: "a@x.com",
    }),
    true,
  );
});

test("⚠️⚠️ 토큰에 이메일이 **있는데** 목록에 없으면 서버 기록을 보지 않는다", () => {
  // 여기가 뒷문이 생기는 자리다. 폴백은 **대조할 값이 아예 없을 때**를
  // 메우는 것이지, 목록에 없는 사람을 통과시키는 경로가 아니다.
  assert.equal(
    isTesterAllowed({
      allowlist: ["a@x.com"],
      tokenEmail: "other@x.com",
      storedEmail: "a@x.com", // 통과시키면 안 된다
    }),
    false,
  );
});

test("서버 기록도 목록에 없으면 거부", () => {
  assert.equal(
    isTesterAllowed({
      allowlist: ["a@x.com"],
      tokenEmail: null,
      storedEmail: "b@x.com",
    }),
    false,
  );
});

test("⚠️ 목록이 비어 있으면 아무도 통과하지 않는다 — 테스트 종료 후 상태", () => {
  // 테스트가 끝나면 config/testers 를 비운다. 그때 이 폴백이 남아 있어도
  // 통과하는 사람이 없어야 한다.
  assert.equal(isTesterAllowed({allowlist: [], tokenEmail: "a@x.com"}), false);
  assert.equal(
    isTesterAllowed({allowlist: [], tokenEmail: null, storedEmail: "a@x.com"}),
    false,
  );
});

test("빈 문자열은 이메일이 없는 것으로 본다", () => {
  assert.equal(
    isTesterAllowed({
      allowlist: ["a@x.com"],
      tokenEmail: "   ",
      storedEmail: "a@x.com",
    }),
    true,
  );
});
