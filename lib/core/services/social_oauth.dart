// 카카오·네이버 로그인의 **주소를 만들고 되돌아온 주소를 읽는** 부분.
//
// ## 왜 웹뷰인가
//
// 카카오·네이버는 각자 네이티브 SDK를 준다. 더 나은 경험(카카오톡 앱으로
// 바로 로그인)을 주지만 **`AndroidManifest.xml`·`Info.plist`·URL 스킴·키
// 해시를 건드려야 한다.** 지금은 다른 세션이 배포 빌드를 준비 중이라
// **빌드 설정을 건드리지 않는 쪽**을 골랐다. 앱이 이미 싣고 있는
// `webview_flutter`로 인증 화면을 열면 새 의존성도, 네이티브 설정 변경도
// 없다.
//
// 📌 앱-투-앱 로그인은 나중에 네이티브 SDK로 얹을 수 있다. 그때도 서버
// 함수(`socialSignIn`)는 그대로 쓸 수 있도록 코드 교환을 서버에 두었다.
//
// ## ⚠️ 여기서 토큰을 만들지 않는다
//
// 웹뷰에서 손에 들어오는 것은 **인가 코드**뿐이다. 그것을 액세스 토큰으로
// 바꾸려면 `client_secret`이 필요한데(네이버는 필수) **앱에 넣을 수 없다.**
// 그래서 코드를 그대로 서버(`socialSignIn`)로 넘긴다.

import 'dart:math';

enum SocialProvider {
  kakao,
  naver;

  String get displayName => switch (this) {
    SocialProvider.kakao => '카카오',
    SocialProvider.naver => '네이버',
  };

  /// 서버(`socialSignIn`)가 알아듣는 이름. **바꾸면 서버도 함께 바꿔야 한다.**
  String get wireName => name;
}

/// 인증이 끝나고 되돌아오는 주소.
///
/// ⚠️ **실제로 열리는 페이지가 아니다.** 웹뷰가 이 주소로 이동하려는 순간
/// 가로채서 코드를 꺼내고 창을 닫는다. 그래서 이 경로에 무언가를 올려 둘
/// 필요가 없다 — 다만 **카카오·네이버 콘솔에 같은 값을 등록**해야 한다.
/// 등록된 값과 한 글자라도 다르면 제공자가 거부한다.
const String kOauthRedirectBase = 'https://connection-sense.web.app/oauth';

String redirectUriFor(SocialProvider p) => '$kOauthRedirectBase/${p.name}';

/// CSRF 방지용 난수.
///
/// 인증을 시작할 때 만들어 보내고, 되돌아온 주소의 `state`가 같은지 확인한다.
/// 다르면 **다른 곳에서 시작된 응답**이므로 버린다.
String generateState([Random? rng]) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final r = rng ?? Random.secure();
  return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
}

/// 인증 화면 주소.
///
/// 📌 **`scope`를 넣지 않는다.** 카카오·네이버 모두 콘솔에서 정한 동의항목을
/// 쓰므로, 코드에서 다시 요구하면 콘솔 설정과 어긋나 이용자에게 보이는 동의
/// 화면이 두 벌이 된다. 어떤 항목을 받을지는 **콘솔 한 곳에서만** 정한다
/// (`docs/planning/sns-auth-privacy-design-2026-08-19.md` 권고안 —
/// 휴대전화·생년월일은 받지 않는다).
Uri authorizeUrl({required SocialProvider provider, required String state}) {
  final redirect = redirectUriFor(provider);
  return switch (provider) {
    SocialProvider.kakao => Uri.https('kauth.kakao.com', '/oauth/authorize', {
      'response_type': 'code',
      'client_id': kKakaoRestKey,
      'redirect_uri': redirect,
      'state': state,
    }),
    SocialProvider.naver => Uri.https('nid.naver.com', '/oauth2.0/authorize', {
      'response_type': 'code',
      'client_id': kNaverClientId,
      'redirect_uri': redirect,
      'state': state,
    }),
  };
}

/// 빌드할 때 넣는 공개 식별자.
///
/// ⚠️ **비밀값이 아니다.** 인증 화면 주소에 그대로 실려 나가는 값이라 숨길
/// 수 없고 숨길 필요도 없다. 안전장치는 **콘솔에 등록한 redirect_uri**다 —
/// 남이 이 값을 알아도 우리 주소로만 되돌아온다.
///
/// 진짜 비밀값(`client_secret`)은 서버에만 있다.
const String kKakaoRestKey = String.fromEnvironment('KAKAO_REST_KEY');
const String kNaverClientId = String.fromEnvironment('NAVER_CLIENT_ID');

bool isConfigured(SocialProvider p) => switch (p) {
  SocialProvider.kakao => kKakaoRestKey.trim().isNotEmpty,
  SocialProvider.naver => kNaverClientId.trim().isNotEmpty,
};

/// 되돌아온 주소에서 읽어 낸 것.
sealed class OauthOutcome {
  const OauthOutcome();
}

/// 코드를 받았다. 서버로 넘기면 된다.
class OauthCode extends OauthOutcome {
  final String code;

  /// 인증을 시작할 때 만든 난수. 대조까지 끝난 값이다.
  ///
  /// ⚠️ **서버가 다시 쓴다.** 네이버는 토큰 요청 변수표에도 `state`를 필수로
  /// 두고 있어서, 코드만 넘기면 교환이 실패한다(카카오는 인증 단계에서만 쓴다).
  final String state;

  const OauthCode(this.code, this.state);
}

/// 제공자가 거절했거나 이용자가 취소했다.
class OauthFailed extends OauthOutcome {
  /// 화면에 그대로 보여 줄 수 있는 한글 문구.
  final String message;
  const OauthFailed(this.message);
}

/// 웹뷰가 이동하려는 주소가 **우리 되돌아오는 주소**인지.
///
/// ⚠️ **`startsWith`로 느슨하게 보면 안 된다.** `https://connection-sense.web.app.evil.com/oauth/kakao`
/// 같은 주소가 통과한다. 호스트와 경로를 따로 확인한다.
bool isRedirect(Uri uri, SocialProvider provider) {
  final target = Uri.parse(redirectUriFor(provider));
  return uri.scheme == target.scheme &&
      uri.host == target.host &&
      uri.path == target.path;
}

/// 웹뷰가 **그대로 열어도 되는 주소**인지 — `http`/`https` 만 통과한다.
///
/// ## ⚠️ 왜 걸러야 하나
///
/// 카카오 로그인 화면에는 *"카카오톡으로 로그인"* 이 있고, 그것을 누르면
/// `kakaotalk://` 또는 `intent://` 로 이동하려 한다. 웹뷰는 이런 스킴을
/// 모르기 때문에 **`ERR_UNKNOWN_URL_SCHEME` 오류 화면**을 띄운다. 이용자
/// 눈에는 로그인이 고장 난 것으로 보인다.
///
/// 📌 이 저장소에는 **같은 유형의 전례**가 있다 — 주소 검색이 안 되던 버그에서
/// 화면에 뜬 `ERR_UNKNOWN_URL_SCHEME`은 증상이었고 원인은 `file://` origin
/// 이었다. 증상이 같으니 원인도 같다고 읽지 말 것: 이번 원인은 **앱 링크**다.
///
/// ## ⚠️ 막기만 하고 열어 주지는 않는다
///
/// `url_launcher`로 카카오톡을 띄울 수는 있다. 하지만 **띄우면 돌아올 길이
/// 없다** — 우리는 네이티브 SDK를 쓰지 않아 앱에 되돌아오는 URL 스킴을
/// 등록해 두지 않았다. 카카오톡에서 동의를 마쳐도 앱으로 못 돌아오고 거기서
/// 끊긴다. 그래서 **막고 웹 로그인 화면에 머무르게 하는 편이 낫다.**
bool isWebNavigation(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'about';
}

/// 되돌아온 주소를 읽는다.
///
/// ⚠️ **`state`를 반드시 대조한다.** 다르면 우리가 시작한 인증이 아니다.
OauthOutcome readRedirect(Uri uri, {required String expectedState}) {
  final q = uri.queryParameters;

  final err = q['error'] ?? q['error_code'];
  if (err != null && err.trim().isNotEmpty) {
    // 이용자가 "취소"를 누른 경우가 대부분이다. 제공자가 주는 영문 설명을
    // 그대로 띄우면 무슨 일인지 알 수 없으므로 우리 문구로 바꾼다.
    final cancelled =
        err.contains('access_denied') || err.contains('user_cancel');
    return OauthFailed(
      cancelled ? '로그인을 취소했어요.' : '로그인에 실패했어요. 다시 시도해 주세요.',
    );
  }

  final state = q['state'];
  if (state == null || state != expectedState) {
    return const OauthFailed('로그인 응답이 올바르지 않아요. 다시 시도해 주세요.');
  }

  final code = q['code'];
  if (code == null || code.trim().isEmpty) {
    return const OauthFailed('로그인 정보를 받지 못했어요. 다시 시도해 주세요.');
  }
  return OauthCode(code, state);
}
