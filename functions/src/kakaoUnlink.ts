import {timingSafeEqual} from "node:crypto";

/**
 * 카카오 **연결 해제 웹훅** 수신에 쓰는 순수 로직.
 *
 * ## 왜 필요한가 — 안 받으면 파기 의무를 못 지킨다
 *
 * 이용자가 우리 앱이 아니라 **카카오계정 설정(카카오톡 > 연결된 서비스)에서
 * 연결을 끊으면 우리 쪽에는 아무 신호가 없다.** 그 사람의 명함과 계정 데이터가
 * 서버에 영구히 남는다. 연결 끊기는 **동의 철회**이므로 파기 의무가 걸린다.
 *
 * ## 카카오 공식 문서에서 확인한 것 (2026-08-22 원문 조회)
 *
 * ```
 * 메서드      GET 또는 POST — 둘 다 온다
 * 인증        Authorization: KakaoAK {대표 어드민 키}
 * 본문        app_id · user_id · referrer_type · group_user_token(선택)
 * 응답        3초 안에 200 OK
 * 콘솔        앱 관리 > [앱] > [웹훅] > [연결 해제 웹훅]
 * ```
 *
 * `referrer_type` 5종 — `ACCOUNT_DELETE`(카카오계정 탈퇴) ·
 * `FORCED_ACCOUNT_DELETE`(장기휴면·고객센터 강제탈퇴) · `UNLINK_FROM_ADMIN` ·
 * `UNLINK_FROM_APPS`(계정 페이지에서 연결 해제) · `INCOMPLETE_SIGN_UP`.
 * **다섯 다 파기 대상이다** — 전부 동의 철회이거나 계정 소멸이다.
 *
 * 📌 **우리가 unlink API를 부른 경우에는 웹훅이 오지 않는다**(문서 명시). 즉
 * 앱 안의 탈퇴 흐름과 이 경로는 겹치지 않는다. 그래도 멱등하게 만든다 — 이미
 * 지운 uid로 다시 와도 조용히 끝나야 한다.
 *
 * ## ⚠️ 이 파일의 안전 핵심은 인증이다
 *
 * 검증이 **정적 비밀값 대조** 하나뿐이다(서명도 논스도 없다). 검증을 빠뜨리면
 * **아무나 호출해 남의 계정을 지울 수 있는 구멍**이 된다. 그래서
 * [adminKeyMatches]는 본문을 읽기 **전에** 부르고, 실패하면 거기서 끝낸다.
 */

/** 접수 문서를 담는 컬렉션. 문서 ID는 uid다. */
export const SOCIAL_UNLINK_REQUESTS = "socialUnlinkRequests";

/** 카카오가 쓰는 인증 헤더 접두사. */
const KAKAO_AUTH_PREFIX = "KakaoAK ";

/**
 * `Authorization` 헤더가 우리 대표 어드민 키와 같은지.
 *
 * ⚠️ **길이를 먼저 비교한다.** `timingSafeEqual`은 길이가 다르면 던지기
 * 때문이다. 길이가 새는 것은 감수한다 — 키 자체를 한 글자씩 맞혀 가는 공격을
 * 막는 것이 목적이고, 그건 길이가 아니라 내용 비교 시간에서 샌다.
 *
 * 빈 기대값이면 **항상 거짓**이다. 시크릿이 안 붙은 채 배포되면 검증이 통째로
 * 무력해지는데, 그 상태를 "통과"로 두면 안 된다.
 */
export function adminKeyMatches(
  authorizationHeader: string | undefined | null,
  expectedAdminKey: string | undefined | null,
): boolean {
  const expected = (expectedAdminKey ?? "").trim();
  if (!expected) return false;

  const header = (authorizationHeader ?? "").trim();
  if (!header.startsWith(KAKAO_AUTH_PREFIX)) return false;

  const received = header.slice(KAKAO_AUTH_PREFIX.length).trim();
  const a = Buffer.from(received, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** 웹훅이 알려 준 것. 개인정보는 담기지 않는다 — 회원번호와 사유뿐이다. */
export interface KakaoUnlinkPayload {
  /** 카카오 회원번호. 문자열로 다룬다 — 숫자로 바꾸면 큰 값이 뭉개진다. */
  userId: string;
  /** 우리 앱 식별자. 안 올 수도 있어 `null`을 허용한다. */
  appId: string | null;
  /** 연결이 끊긴 사유. 안 올 수도 있다. */
  referrerType: string | null;
}

/**
 * GET 질의문자열과 POST 본문을 **함께** 받아 필요한 값만 뽑는다.
 *
 * 둘을 합치는 이유: 카카오는 **GET 또는 POST 둘 다** 보낸다고만 밝히고 본문
 * `Content-Type`은 문서에 적어 두지 않았다. 어느 쪽으로 오든 읽히게 해 두는
 * 편이, 실서버에서 형식이 달라 조용히 못 받는 것보다 낫다.
 *
 * `user_id`가 없으면 `null` — 그건 우리가 처리할 수 있는 요청이 아니다.
 */
export function parseKakaoUnlinkPayload(
  ...sources: Array<Record<string, unknown> | undefined | null>
): KakaoUnlinkPayload | null {
  const pick = (key: string): string | null => {
    for (const source of sources) {
      const raw = source?.[key];
      if (raw === undefined || raw === null) continue;
      const value = String(raw).trim();
      if (value) return value;
    }
    return null;
  };

  const userId = pick("user_id");
  if (!userId) return null;

  return {
    userId,
    appId: pick("app_id"),
    referrerType: pick("referrer_type"),
  };
}

/**
 * 페이로드의 `app_id`가 우리 앱 것인지.
 *
 * 어드민 키 검증에 더한 **이중 확인**이다. 다만 `app_id`가 안 오거나 우리가
 * 기대값을 안 갖고 있으면 **막지 않는다** — 여기서 막으면 설정이 덜 된 상태에서
 * 파기가 통째로 멈추고, 그건 "안 지워져 남는" 쪽으로 틀리는 것이다. 인증은
 * 이미 어드민 키가 하고 있다.
 */
export function appIdAllowed(
  payloadAppId: string | null,
  expectedAppId: string | undefined | null,
): boolean {
  const expected = (expectedAppId ?? "").trim();
  if (!expected) return true;
  if (!payloadAppId) return true;
  return payloadAppId.trim() === expected;
}
