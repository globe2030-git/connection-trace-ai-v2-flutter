/**
 * 카카오·네이버 로그인 — 토큰을 받아 Firebase 계정으로 바꾸는 부분.
 *
 * ## 왜 서버가 필요한가
 *
 * Firebase Auth는 Google·Apple을 기본 제공자로 알지만 **카카오·네이버는
 * 모른다.** 붙이는 길은 둘뿐이다.
 *
 * ```
 * ① 커스텀 토큰   서버가 카카오/네이버 토큰을 검증하고 Firebase 토큰을 발급
 * ② OIDC          Firebase Identity Platform 업그레이드
 * ```
 *
 * **①을 골랐다**(사용자 결정 2026-08-20). ②는 SAML/OIDC가 무료 50 MAU 이후
 * **$0.015/MAU**라, 목표인 무료 1만 명이면 월 20만원이 나간다 — 과금 방향
 * (무료 1만·유료 100)에 대면 수익보다 비용이 크다.
 *
 * ⚠️ **액세스 토큰 검증을 클라이언트에 맡길 수 없다.** 앱이 "나 카카오
 * 12345번이야"라고 주장하는 것을 그대로 믿으면 아무나 남의 계정이 된다.
 * 반드시 **서버가 카카오/네이버에 직접 물어서** 확인해야 한다.
 *
 * ## 이 파일에는 HTTP 호출이 없다
 *
 * 순수 함수만 둔다. 실제 호출은 `index.ts`가 하고 결과를 여기로 넘긴다.
 * 이 저장소의 다른 함수들(`creditGrant`, `deviceLedger` 등)과 같은 방식이고,
 * **네트워크 없이 테스트할 수 있게** 하려는 것이다.
 */

/** 지원하는 제공자. */
export type SocialProvider = "kakao" | "naver";

/**
 * Firebase uid.
 *
 * ⚠️ **제공자 접두사를 반드시 붙인다.** 카카오 회원번호와 네이버 회원번호는
 * 서로 다른 체계라 **우연히 같은 값이 나올 수 있다.** 접두사가 없으면 남의
 * 명함이 통째로 보이는 사고가 된다.
 *
 * 형식이 바뀌면 **기존 이용자가 다른 계정이 되어 데이터가 끊긴다.**
 * 한번 정하면 못 바꾼다고 생각하고 다뤄야 한다.
 */
export function socialUid(provider: SocialProvider, id: string): string {
  const trimmed = (id ?? "").trim();
  if (!trimmed) throw new Error("소셜 회원번호가 비어 있다");
  return `${provider}:${trimmed}`;
}

/**
 * 우리가 계정에 담는 항목. **이게 전부다.**
 *
 * 카카오·네이버는 요청하면 휴대전화·생년월일·성별·연령대까지 준다. 하지만
 * `docs/planning/sns-auth-privacy-design-2026-08-19.md`의 권고안대로 **받지
 * 않는다** — 로그인에 필요 없고, 받는 순간 방침·파기·국외이전 서술이 전부
 * 늘어난다. 최소수집 원칙(개인정보 보호법 제16조)에도 맞다.
 */
export interface SocialProfile {
  uid: string;
  provider: SocialProvider;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
}

/** 값이 비어 있거나 문자열이 아니면 null로 만든다. */
function str(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length > 0 ? t : null;
}

/**
 * 카카오 `/v2/user/me` 응답 → 우리 프로필.
 *
 * 응답 모양:
 * ```
 * { id: 12345, kakao_account: { email, profile: { nickname, profile_image_url } } }
 * ```
 *
 * ⚠️ `id`가 **숫자로 온다.** 문자열로 바꿔 두지 않으면 uid가 자릿수에 따라
 * 흔들린다(자바스크립트 숫자 정밀도). 그래서 받자마자 문자열로 고정한다.
 *
 * ⚠️ **이메일은 없을 수 있다.** 카카오에서 이메일 제공에 동의하지 않은
 * 계정이 실제로 있다. 없다고 로그인을 막지 않는다 — 이메일은 식별자가
 * 아니라 표시용이다.
 */
export function parseKakaoUser(raw: unknown): SocialProfile {
  const o = (raw ?? {}) as Record<string, unknown>;
  const rawId = o.id;
  const id =
    typeof rawId === "number" ? String(rawId) : str(rawId) ?? "";
  if (!id) throw new Error("카카오 응답에 회원번호가 없다");

  const account = (o.kakao_account ?? {}) as Record<string, unknown>;
  const profile = (account.profile ?? {}) as Record<string, unknown>;

  return {
    uid: socialUid("kakao", id),
    provider: "kakao",
    email: str(account.email),
    displayName: str(profile.nickname),
    photoUrl: str(profile.profile_image_url),
  };
}

/**
 * 네이버 `/v1/nid/me` 응답 → 우리 프로필.
 *
 * 응답 모양:
 * ```
 * { resultcode: "00", message: "success",
 *   response: { id, email, nickname, name, profile_image, ... } }
 * ```
 *
 * ⚠️ **`resultcode`를 먼저 봐야 한다.** 네이버는 실패해도 HTTP 200으로
 * 답하는 경우가 있어, 상태 코드만 보고 성공으로 읽으면 빈 프로필이 그대로
 * 계정이 된다.
 *
 * ⚠️ **`name`이 아니라 `nickname`을 쓴다.** `name`은 실명이다. 표시용으로
 * 실명을 들고 있을 이유가 없다 — 최소수집.
 */
export function parseNaverUser(raw: unknown): SocialProfile {
  const o = (raw ?? {}) as Record<string, unknown>;
  const code = str(o.resultcode);
  if (code !== "00") {
    throw new Error(`네이버 응답 실패(resultcode=${code ?? "없음"})`);
  }
  const r = (o.response ?? {}) as Record<string, unknown>;
  const id = str(r.id);
  if (!id) throw new Error("네이버 응답에 회원번호가 없다");

  return {
    uid: socialUid("naver", id),
    provider: "naver",
    email: str(r.email),
    displayName: str(r.nickname),
    photoUrl: str(r.profile_image),
  };
}

/**
 * Firebase 사용자 레코드에 넣을 값.
 *
 * ⚠️ `photoUrl`이 http면 넣지 않는다. Firebase는 받아 주지만, 앱이 그 주소를
 * 그대로 불러 화면에 띄우면 평문 요청이 나간다.
 */
export function firebaseUserFields(p: SocialProfile): {
  displayName?: string;
  email?: string;
  photoURL?: string;
} {
  const out: {displayName?: string; email?: string; photoURL?: string} = {};
  if (p.displayName) out.displayName = p.displayName;
  if (p.email) out.email = p.email;
  if (p.photoUrl && p.photoUrl.startsWith("https://")) {
    out.photoURL = p.photoUrl;
  }
  return out;
}

/**
 * 커스텀 토큰에 실을 추가 정보(claims).
 *
 * ⚠️ **개인정보를 넣지 않는다.** 커스텀 토큰의 claims는 클라이언트가 디코드해
 * 읽을 수 있고 로그에도 남기 쉽다. 어느 제공자로 들어왔는지만 남긴다 —
 * 그건 "마지막에 무엇으로 로그인했나"를 화면에 보여 주는 데 필요하다
 * (재로그인 안내가 엉뚱한 버튼을 가리키면 이용자가 막힌다).
 */
export function tokenClaims(p: SocialProfile): {provider: SocialProvider} {
  return {provider: p.provider};
}

/**
 * 앱이 넘긴 요청이 쓸 만한지.
 *
 * ## ⚠️ 앱은 `code`를 보내지 `accessToken`을 보내지 않는다
 *
 * 로그인은 앱 안의 웹뷰에서 카카오/네이버 인증 화면을 열고, 되돌아오는
 * 주소에서 **인가 코드(`code`)**를 가로채는 방식이다. 그 코드를 액세스
 * 토큰으로 바꾸려면 **client_secret**이 필요한데(네이버는 필수),
 * **그것을 앱에 넣으면 안 된다** — 앱은 뜯어볼 수 있다. 그래서 교환도
 * 서버가 한다.
 *
 * `state`는 앱이 만든 난수다. 웹뷰가 되돌려준 값과 같은지 **앱이** 확인하고
 * 보내며, 여기서는 형식만 본다(다른 사이트가 끼워 넣은 응답을 걸러내는 용도).
 */
export function validateRequest(raw: unknown): {
  provider: SocialProvider;
  code: string;
  redirectUri: string;
} {
  const o = (raw ?? {}) as Record<string, unknown>;
  const provider = str(o.provider);
  const code = str(o.code);
  const redirectUri = str(o.redirectUri);
  if (provider !== "kakao" && provider !== "naver") {
    throw new Error("provider는 kakao 또는 naver여야 한다");
  }
  if (!code) throw new Error("code가 없다");
  if (!redirectUri) throw new Error("redirectUri가 없다");
  return {provider, code, redirectUri};
}

/** 인가 코드를 액세스 토큰으로 바꾸는 요청의 주소. */
export function tokenEndpoint(provider: SocialProvider): string {
  return provider === "kakao"
    ? "https://kauth.kakao.com/oauth/token"
    : "https://nid.naver.com/oauth2.0/token";
}

/**
 * 인가 코드 교환 요청 본문.
 *
 * ⚠️ **`client_secret`은 값이 있을 때만 넣는다.** 카카오는 콘솔에서 끄면
 * 보내면 **안 되고**(있으면 오류), 네이버는 **반드시** 있어야 한다. 빈
 * 문자열을 넣어 보내면 카카오 쪽에서 실패한다.
 */
export function tokenExchangeBody(params: {
  provider: SocialProvider;
  code: string;
  clientId: string;
  clientSecret: string | null;
  redirectUri: string;
}): string {
  const {provider, code, clientId, clientSecret, redirectUri} = params;
  if (!clientId?.trim()) throw new Error("clientId가 없다");
  if (provider === "naver" && !clientSecret?.trim()) {
    throw new Error("네이버는 clientSecret이 반드시 필요하다");
  }
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId.trim(),
    code,
    redirect_uri: redirectUri,
  });
  if (clientSecret?.trim()) body.set("client_secret", clientSecret.trim());
  return body.toString();
}

/**
 * 교환 응답에서 액세스 토큰을 꺼낸다.
 *
 * ⚠️ **네이버는 실패해도 HTTP 200으로 답한다.** 본문에 `error`가 들어 있는지
 * 먼저 봐야 한다. 상태 코드만 믿으면 토큰이 `undefined`인 채로 다음 단계까지
 * 흘러간다.
 */
export function parseTokenResponse(raw: unknown): string {
  const o = (raw ?? {}) as Record<string, unknown>;
  const err = str(o.error) ?? str(o.error_code);
  if (err) throw new Error(`토큰 교환 실패(${err})`);
  const token = str(o.access_token);
  if (!token) throw new Error("응답에 access_token이 없다");
  return token;
}
