import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart' as fb_functions;
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/services/google_auth_gateway.dart';
import '../../core/services/social_oauth.dart' as social;
import '../../core/services/social_web_session.dart';
import '../models/sns_auth_provider.dart';

class AuthException implements Exception {
  final String message;

  /// true면 "최근 로그인 상태가 아니어서" 실패한 것 — Firebase Auth의
  /// `requires-recent-login` 에러를 계정 삭제(backlog #49) 흐름에서
  /// 구분해 재인증 절차로 안내하는 데 쓴다.
  final bool requiresReauth;

  /// true면 이메일 로그인에서 비밀번호가 틀린 것(`wrong-password`/
  /// `invalid-credential`) — 화면이 비밀번호 재설정(⑩) 링크를 보여줄
  /// 근거로 쓴다(추가 632, §5-2).
  final bool offerPasswordReset;

  AuthException(
    this.message, {
    this.requiresReauth = false,
    this.offerPasswordReset = false,
  });
  @override
  String toString() => message;
}

/// SNS 계정으로 로그인 상태를 관리한다.
///
/// 아직 별도 회원 서버(계정 DB)가 없기 때문에 "회원가입"은 실제로는 이
/// 기기에 로그인 세션을 암호화 저장(Keychain/Keystore)해 두는 것이며, 다른
/// 기기에서는 다시 로그인해야 한다. 서버가 생기면 이 세션을 서버 발급
/// 토큰으로 교체할 예정 — docs/planning/HANDOFF.md 참고.
class AuthRepository extends ChangeNotifier {
  static const _sessionKey = 'auth_session_v1';

  /// 로그인 화면에서 "최근" 배지로 보여줄, 지난번에 성공한 로그인 수단 하나.
  ///
  /// ⚠️ **`_sessionKey`(위, secure storage)와 일부러 분리된 값이다.** `signOut()`은
  /// `_sessionKey`를 지우지만 이 값은 지우지 않는다 — 로그아웃 뒤에도 "최근"을
  /// 보여주는 것이 이 값의 존재 이유다(설계: docs/planning/specs/login-recent-provider-2026-08-29.md).
  /// 반대로 계정 삭제([deleteFirebaseAccountAndLocalSession])에서는 지운다 —
  /// 없어진 계정으로 이용자를 유도하면 안 되기 때문이다.
  ///
  /// `shared_preferences`(평문)를 쓰는 이유: 값이 provider 이름 문자열
  /// 하나뿐이라 개인정보가 아니다. `flutter_secure_storage`를 쓸 이유가 없다.
  static const _lastProviderKey = 'last_login_provider_v1';

  final FlutterSecureStorage _secureStorage;

  /// 웹뷰에 남은 카카오·네이버 세션 쿠키를 지우는 함수.
  ///
  /// 테스트에서 갈아 끼울 수 있게 주입받는다 — 실제 구현은 플랫폼 채널을
  /// 타므로 `flutter test`에서는 부를 수 없다.
  final ClearSocialWebSession _clearWebSession;

  bool _isLoading = true;
  bool _isSignedIn = false;
  SnsAuthProvider? _provider;
  String? _displayName;
  String? _email;
  String? _photoUrl;
  SnsAuthProvider? _lastProvider;

  /// [_loadLastProvider]의 비동기 읽기가 끝나기 전에 로그인/로그아웃/계정삭제로
  /// [_lastProvider]가 먼저 바뀌면, 늦게 끝난 읽기가 그 값을 다시 덮어써
  /// 버리는 경합이 생길 수 있다(생성자에서 읽기를 시작한 직후 곧바로 쓰기가
  /// 일어나는 경우 — 실사용에선 거의 없지만 테스트에서 실제로 재현됐다).
  /// 쓰기가 있을 때마다 올려서, 읽기가 끝났을 때 그 사이 쓰기가 있었으면
  /// 읽은 값을 버린다.
  int _lastProviderWriteVersion = 0;

  AuthRepository({
    FlutterSecureStorage? secureStorage,
    ClearSocialWebSession? clearWebSession,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _clearWebSession = clearWebSession ?? clearSocialWebSession {
    _load();
    _loadLastProvider();
  }

  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  SnsAuthProvider? get provider => _provider;
  String? get displayName => _displayName;
  String? get email => _email;
  String? get photoUrl => _photoUrl;

  /// 로그인 화면 "최근" 배지용 — 지난번 로그인 성공 수단. 활성 세션이 없어도
  /// (로그아웃 상태여도) 값이 남아 있을 수 있다. 자세한 설명은 [_lastProviderKey]
  /// 참고.
  SnsAuthProvider? get lastProvider => _lastProvider;

  /// 명함/프로필 서버 백업·복원(backlog 추가 66)에 쓰는 Firebase Auth 계정
  /// 고유 ID. 기기 로컬 세션(`_isSignedIn` 등)과는 별개로, Firebase 쪽 로그인
  /// 상태가 살아있을 때만 값이 있다 — 게스트 QA 로그인(`signInAsGuest`)이나
  /// Firebase Auth 초기화 전에는 null이라 백업/복원 로직은 이 값이 있을
  /// 때만 동작해야 한다.
  String? get firebaseUid => fb_auth.FirebaseAuth.instance.currentUser?.uid;

  /// 이 계정이 **만들어진 시각**(UTC). 번호 확인 게이트의 「신규 가입자만」을
  /// 가르는 기준이다(추가 645).
  ///
  /// ⭐ **Firebase Auth 가 주는 값을 쓴다.** 계정이 생길 때 서버가 한 번
  /// 찍고 그 뒤로 바뀌지 않으며, 기존 이용자에게도 **이미 들어 있다** —
  /// 새로 필드를 만들면 그 전에 가입한 사람에게는 값이 없어서 소급이 안 된다.
  ///
  /// ⚠️ `users/{uid}.cohortWeek`을 쓰려다 그만두었다. 그 필드는 가입 시각이
  /// 아니라 **「계측을 배포한 뒤 처음 로그인한 주차」**다(`index.ts`가
  /// 없으면 그때 채운다). 기존 이용자가 오늘 로그인하면 **이번 주로 채워져
  /// 신규로 보인다** — 막으려던 사람을 정확히 반대로 가른다.
  ///
  /// 🚨 **없으면 `null`이다.** 부르는 쪽은 모르는 것을 신규로 보면 안 된다.
  DateTime? get firebaseAccountCreatedAt =>
      fb_auth.FirebaseAuth.instance.currentUser?.metadata.creationTime;

  /// 이메일 계정인데 아직 이메일 소유 확인(인증 메일 클릭)을 안 했는가
  /// (추가 632, §7 — 설정 화면 배지·재발송 버튼용).
  ///
  /// ⚠️ **이메일이 아닌 계정은 항상 false다.** 소셜 로그인은 제공자가 이미
  /// 소유를 확인한 주소를 준다(또는 애초에 이메일이 없다) — 이 앱이 따로
  /// 확인할 것이 없다.
  bool get needsEmailVerification {
    if (_provider != SnsAuthProvider.email) return false;
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // Firebase가 캐시해 둔 값이라 실제로는 인증됐는데 이 값만 낡았을 수
    // 있다 — 그래도 설정 화면이 "재발송" 버튼을 보여주는 정도라 큰 문제는
    // 없다. 최신값이 필요하면 호출자가 user.reload() 후 다시 읽는다.
    return !user.emailVerified;
  }

  /// 관리자 전용 화면(설정 → 관리자 1:1 문의 관리)을 **메뉴에 띄울지 말지**만
  /// 정하는 값이다. 실제 차단은 서버(`firestore.rules`의 `isAdmin()`)가 하며,
  /// 이 값을 우회해 화면을 열어도 데이터는 못 읽는다 — 여기서 막는 것은
  /// "일반 사용자에게 관리자 메뉴가 보이고, 누르면 권한 오류가 뜨는" UX다
  /// (2026-08-13 실기기 확인, backlog 추가 178).
  ///
  /// 판단 기준을 `firestore.rules`와 똑같이 맞춘다 — **Firebase Auth 토큰의
  /// 이메일 + 이메일 인증 완료**. 로컬 세션의 `email`을 쓰지 않는 이유는
  /// 카카오/네이버 로그인에서 그 값이 Firebase 토큰 이메일과 다를 수 있어서,
  /// 앱과 서버의 판단이 갈리면 메뉴는 보이는데 열리지는 않는 상태가 된다.
  ///
  /// ⚠️ 이메일 목록이 `firestore.rules`와 두 곳에 나뉜다. 관리자를 추가할 때는
  /// **규칙이 진짜 관문이므로 규칙을 먼저 고치고** 이 목록도 같이 맞춘다.
  /// 여기만 고치면 메뉴만 생기고 아무것도 안 보인다.
  static const _adminEmails = {
    'connectionsense@creamhouse.net',
    'globe@creamhouse.net',
  };

  bool get isAdmin {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return false;
    final email = user.email?.toLowerCase();
    return email != null && _adminEmails.contains(email);
  }

  Future<void> _load() async {
    try {
      final raw = await _secureStorage.read(key: _sessionKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _provider = _providerFromName(json['provider'] as String?);
        _displayName = json['displayName'] as String?;
        _email = json['email'] as String?;
        _photoUrl = json['photoUrl'] as String?;
        _isSignedIn = _provider != null;
      }
    } catch (e) {
      debugPrint('Error loading auth session: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  SnsAuthProvider? _providerFromName(String? name) {
    if (name == null) return null;
    for (final p in SnsAuthProvider.values) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// [_load]와 별개로 "최근 로그인 수단"을 읽는다. 활성 세션(`_sessionKey`)이
  /// 없어도(로그아웃 상태여도) 이 값은 남아 있을 수 있어 따로 읽는다.
  Future<void> _loadLastProvider() async {
    final versionAtStart = _lastProviderWriteVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 읽는 동안 로그인/로그아웃/계정삭제로 이미 값이 바뀌었으면, 늦게
      // 도착한 이 값(더 오래된 값)으로 덮어쓰지 않는다.
      if (_lastProviderWriteVersion != versionAtStart) return;
      _lastProvider = _providerFromName(prefs.getString(_lastProviderKey));
    } catch (e) {
      debugPrint('Error loading last login provider: $e');
    } finally {
      if (_lastProviderWriteVersion == versionAtStart) notifyListeners();
    }
  }

  /// [lastProvider]를 기록한다 — [completeSignIn]에서만 부른다. 게스트 로그인
  /// ([signInAsGuest])은 이 경로를 타지 않아 "최근"으로 기록되지 않는다.
  Future<void> _saveLastProvider(SnsAuthProvider provider) async {
    _lastProviderWriteVersion++;
    _lastProvider = provider;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastProviderKey, provider.name);
    } catch (e) {
      debugPrint('Error saving last login provider: $e');
    }
  }

  /// 로그인 성공 공통 처리. Google·Apple·카카오/네이버 세 경로가 각자
  /// 필드를 세팅하고 세션을 저장하는 코드를 똑같이 반복하고 있었는데, 그
  /// 중 하나가 "최근 로그인 수단 기록"을 빠뜨리는 사고를 막기 위해 한
  /// 곳으로 모았다. `@visibleForTesting`인 이유: 실제 SNS 로그인 세
  /// 경로는 전부 Firebase Auth/Functions 네트워크 호출을 거쳐 `flutter
  /// test`에서 직접 부를 수 없다(Firebase 앱 초기화가 없어 예외가 남).
  /// 이 메서드는 세 경로가 인증에 성공한 뒤 실제로 실행하는 코드와 동일한
  /// 코드이므로, 이걸 직접 호출해 검증하는 것이 "성공 시 무엇이 저장되는가"를
  /// 확인하는 정확한 방법이다.
  @visibleForTesting
  Future<void> completeSignIn(
    SnsAuthProvider provider, {
    String? displayName,
    String? email,
    String? photoUrl,
  }) async {
    _provider = provider;
    _displayName = displayName;
    _email = email;
    _photoUrl = photoUrl;
    _isSignedIn = true;
    notifyListeners();
    await _persist();
    await _saveLastProvider(provider);
  }

  Future<void> signInWithGoogle() async {
    await GoogleAuthGateway.ensureInitialized();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } catch (e) {
      throw AuthException('Google 로그인에 실패했습니다. 다시 시도해 주세요.');
    }
    // Firebase Auth에도 같은 Google 계정으로 로그인해서 명함/프로필 서버
    // 백업·복원(backlog 추가 66)에 쓸 고유 uid를 얻는다. 이 단계가 실패해도
    // 로그인 자체(로컬 세션)는 그대로 진행 — 서버 백업은 선택적 부가 기능이지
    // 로그인을 막는 필수 조건이 아니다.
    try {
      final idToken = account.authentication.idToken;
      if (idToken != null) {
        final credential = fb_auth.GoogleAuthProvider.credential(
          idToken: idToken,
        );
        await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
      } else {
        debugPrint('Google idToken이 없어 Firebase Auth 로그인을 건너뜀');
      }
    } catch (e) {
      debugPrint('Firebase Auth 로그인 실패(로컬 로그인은 계속 진행): $e');
    }
    await completeSignIn(
      SnsAuthProvider.google,
      displayName: account.displayName,
      email: account.email,
      photoUrl: account.photoUrl,
    );
  }

  /// 카카오·네이버 로그인.
  ///
  /// ## Google·Apple 과 흐름이 다르다
  ///
  /// Firebase Auth는 카카오·네이버를 기본 제공자로 모른다. 그래서
  ///
  /// ```
  /// 1. 앱: 웹뷰로 인증 → 인가 코드
  /// 2. 서버(socialSignIn): 코드 → 액세스 토큰 → 사용자 정보 → 커스텀 토큰
  /// 3. 앱: 커스텀 토큰으로 Firebase 로그인
  /// ```
  ///
  /// ⚠️ **여기서는 Firebase 로그인 실패를 넘기지 않는다.** Google 로그인은
  /// 실패해도 로컬 세션으로 계속 가지만(서버 백업은 부가 기능), 카카오·네이버는
  /// **Firebase uid 자체가 서버에서 나온다.** 실패하면 명함을 저장할 자리가
  /// 없으므로 로그인을 성립시키면 안 된다.
  ///
  /// [openAuth]는 인증 화면을 띄우는 함수다. 화면 코드를 이 파일에 들이지
  /// 않으려고 밖에서 넘긴다(테스트에서도 갈아 끼울 수 있다).
  Future<void> signInWithSocial(
    SnsAuthProvider provider,
    Future<social.OauthOutcome> Function(social.SocialProvider) openAuth,
  ) async {
    final target = provider.socialProvider;
    if (target == null) {
      throw AuthException('${provider.displayName} 로그인은 지원하지 않습니다.');
    }
    if (!provider.isAvailable) {
      throw AuthException(provider.unavailableReason!);
    }

    final outcome = await openAuth(target);
    if (outcome is social.OauthFailed) {
      throw AuthException(outcome.message);
    }
    final code = (outcome as social.OauthCode).code;

    final Map<String, dynamic> data;
    try {
      final callable = fb_functions.FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('socialSignIn');
      final result = await callable.call<Map<String, dynamic>>({
        'provider': target.wireName,
        'code': code,
        'redirectUri': social.redirectUriFor(target),
        'state': outcome.state,
      });
      data = result.data;
    } on fb_functions.FirebaseFunctionsException catch (e) {
      // ⚠️ 서버가 주는 영문 메시지를 그대로 띄우지 않는다. 이용자가 할 수
      // 있는 일이 코드마다 다르다.
      // ⚠️ 뭉뚱그린 문구 하나로 두면 어디서 막혔는지 알 수 없다. 실기기에서
      // "카카오 로그인에 실패했어요"만 뜨는 바람에, 서버 함수가 아직 배포되지
      // 않은 것인지 인증이 거부된 것인지 화면만 보고는 가릴 수 없었다
      // (2026-08-20). 이용자가 할 수 있는 일이 코드마다 다르므로 갈라 놓는다.
      debugPrint('socialSignIn 실패: code=${e.code}');
      throw AuthException(switch (e.code) {
        'unauthenticated' => '로그인 정보를 확인하지 못했어요. 다시 시도해 주세요.',
        'unavailable' => '로그인 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.',
        // 함수가 아직 배포되지 않았을 때 온다. 이용자가 할 수 있는 일이 없으므로
        // "다시 시도"라고 하지 않는다 — 눌러도 같은 결과다.
        'not-found' || 'internal' =>
          '${provider.displayName} 로그인이 아직 준비되지 않았어요.',
        'deadline-exceeded' => '응답이 늦어요. 잠시 후 다시 시도해 주세요.',
        _ => '${provider.displayName} 로그인에 실패했어요. (${e.code})',
      });
    } catch (e) {
      debugPrint('socialSignIn 예외: $e');
      throw AuthException('${provider.displayName} 로그인에 실패했어요. 다시 시도해 주세요.');
    }

    final token = (data['token'] as String?)?.trim();
    if (token == null || token.isEmpty) {
      throw AuthException('${provider.displayName} 로그인에 실패했어요. 다시 시도해 주세요.');
    }

    final fb_auth.UserCredential cred;
    try {
      cred = await fb_auth.FirebaseAuth.instance.signInWithCustomToken(token);
    } catch (e) {
      debugPrint('커스텀 토큰 로그인 실패: $e');
      throw AuthException('로그인을 마치지 못했어요. 다시 시도해 주세요.');
    }

    final user = cred.user;
    await completeSignIn(
      provider,
      displayName: user?.displayName,
      email: user?.email,
      photoUrl: user?.photoURL,
    );
  }

  Future<void> signInWithApple() async {
    if (!SnsAuthProvider.apple.isAvailable) {
      throw AuthException(SnsAuthProvider.apple.unavailableReason!);
    }

    // 재전송(replay) 공격 방지용 nonce. Apple에는 SHA-256 해시를 보내고,
    // Firebase Auth 자격 증명을 만들 때는 원문(raw) nonce를 함께 제출해
    // Firebase가 해시를 검증하게 한다.
    final rawNonce = generateNonce();
    final hashedNonce = _sha256(rawNonce);

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // 사용자가 Apple 로그인 시트를 그냥 닫은 것 — 실패가 아니라 취소이므로
        // Google 경로와 달리 에러 배너 없이 조용히 반환한다.
        return;
      }
      throw AuthException('Apple 로그인에 실패했습니다. 다시 시도해 주세요.');
    } catch (e) {
      throw AuthException('Apple 로그인에 실패했습니다. 다시 시도해 주세요.');
    }

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw AuthException('Apple 로그인에 실패했습니다. 다시 시도해 주세요.');
    }

    // Google 경로는 Firebase Auth 로그인이 실패해도 로컬 세션(로그인 자체)은
    // 그대로 진행한다 — Google 계정 자체가 별도의 신원 소스이기 때문이다.
    // 반면 Apple은 Firebase uid 외에 다른 신원 소스가 없으므로(이 앱에는
    // 별도 회원 서버가 없다), Firebase 로그인이 실패하면 곧바로 로그인
    // 실패로 처리한다.
    final fb_auth.UserCredential userCredential;
    try {
      final oauthCredential = fb_auth.OAuthProvider(
        'apple.com',
      ).credential(idToken: identityToken, rawNonce: rawNonce);
      userCredential = await fb_auth.FirebaseAuth.instance
          .signInWithCredential(oauthCredential);
    } catch (e) {
      throw AuthException('Apple 로그인에 실패했습니다. 다시 시도해 주세요.');
    }

    final user = userCredential.user;

    // Apple은 givenName/familyName/email을 "최초 인증 1회에만" 내려준다.
    // 이번에 이름을 받았다면 Firebase 계정에도 저장해 두 번째 로그인부터는
    // FirebaseAuth.currentUser.displayName을 fallback으로 쓸 수 있게 한다.
    final givenName = credential.givenName;
    final familyName = credential.familyName;
    final nameParts = [
      givenName,
      familyName,
    ].whereType<String>().where((n) => n.isNotEmpty);
    final resolvedName = nameParts.isEmpty ? null : nameParts.join(' ');
    if (resolvedName != null && user != null) {
      try {
        await user.updateDisplayName(resolvedName);
      } catch (e) {
        debugPrint('Apple 로그인 displayName 저장 실패: $e');
      }
    }

    // 이름을 이번에 못 받았으면(재로그인) Firebase에 저장돼 있던 이전 값을
    // fallback으로 쓴다. 그마저 없으면 "애플 사용자" 같은 이름을 지어내지
    // 않고 null로 둔다 — 화면이 이름 없음을 알아서 처리해야 한다.
    // Hide My Email로 받은 @privaterelay.appleid.com 릴레이 주소도 정상적인
    // 이메일 값이므로 그대로 저장한다.
    await completeSignIn(
      SnsAuthProvider.apple,
      displayName: resolvedName ?? user?.displayName,
      email: credential.email ?? user?.email,
      photoUrl: user?.photoURL,
    );

    // App Store 요구(계정 삭제 시 Apple 토큰 폐기, P1-38): 서버가 나중에
    // 폐기할 수 있도록 authorization_code를 보내 refresh_token으로 교환·보관
    // 하게 한다. 로그인 흐름을 막지 않도록 기다리지 않고, 실패해도 무시한다
    // (authorization_code는 발급 후 5분 내 교환해야 해 로그인 직후에 보낸다).
    if (user != null && credential.authorizationCode.isNotEmpty) {
      unawaited(_storeAppleRefreshTokenOnServer(credential.authorizationCode));
    }
  }

  /// Apple authorization_code를 서버로 보내 refresh_token으로 교환·보관하게
  /// 한다(탈퇴 시 폐기용, P1-38). 실패는 조용히 무시한다 — 로그인 자체는
  /// 이미 성공했고, 다음 로그인에 다시 시도된다.
  Future<void> _storeAppleRefreshTokenOnServer(String authorizationCode) async {
    try {
      await fb_functions.FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('storeAppleRefreshToken')
          .call<Map<String, dynamic>>({
        'authorizationCode': authorizationCode,
      });
    } catch (e) {
      // 개인정보·토큰 원문이 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('Apple refresh token 서버 저장 실패: ${e.runtimeType}');
    }
  }

  /// 이메일+비밀번호로 가입하거나(계정이 없으면), 이미 있으면 로그인한다
  /// (추가 632, §5-2 / 추가 636에서 순서를 뒤집었다).
  ///
  /// ⚠️ **갈래 UI(로그인/가입 화면 분리)를 두지 않는다** — 원칙은 추가 632와
  /// 같다. 다만 **가입을 먼저 시도한다.** 이 프로젝트는 이메일 열거
  /// 방지(email enumeration protection, `emailPrivacyConfig
  /// .enableImprovedEmailPrivacy`)가 켜져 있는데, 이게 켜지면 signIn 실패는
  /// 계정이 없든 비밀번호가 틀렸든 **전부 `invalid-credential`로 뭉쳐서만
  /// 돌아온다** — `user-not-found`가 더 이상 나오지 않는다(2026-09-01 실기기
  /// 제보로 발견: 새 이메일 가입 시도가 전부 "비밀번호가 올바르지 않습니다"로
  /// 막혔다). signIn을 먼저 타면 가입 분기(`user-not-found`)에 영원히
  /// 도달하지 못한다.
  ///
  /// 반대로 **가입(`createUserWithEmailAndPassword`)은 지금도 계정이 이미
  /// 있으면 `email-already-in-use`를 분명히 돌려준다** — Google 공식 문서가
  /// "Invalid sign-up cases continue to return EMAIL_EXISTS errors"라고
  /// 명시한다(실측 확인:
  /// https://docs.cloud.google.com/identity-platform/docs/admin/email-enumeration-protection
  /// , 2026-09-01). 그래서 가입을 먼저 시도하고, 이미 있는 계정이면 그
  /// 안에서 로그인으로 폴백하는 쪽으로 순서를 뒤집었다.
  ///
  /// `fetchSignInMethodsForEmail`로 존재 여부를 먼저 물어보는 방법은 쓰지
  /// 않는다 — 같은 열거 방지 설정에서 그 API도 항상 빈 배열만 돌려줘 애초에
  /// 못 쓴다(위 문서: "A list of sign-in methods ... is no longer returned").
  /// 열거 방지 자체를 끄는 방법도 쓰지 않는다 — 서버 설정 변경은 배포
  /// 성격이고, 끄면 계정 목록이 새어 나가 방침 ⑩(비밀번호 재설정에서
  /// 가입 여부를 알려주지 않는다)과 정면으로 부딪친다.
  ///
  /// ⚠️ **왜 `flutter test`가 이 결함을 못 잡았나**: 이 메서드는
  /// `fb_auth.FirebaseAuth.instance`를 직접 부른다 — 모킹 지점(DI 주입)이
  /// 없어 `flutter test`에서는 애초에 이 메서드를 실행하는 테스트가 없다.
  /// 즉 "목이 실물과 다른 값을 돌려줘서 속았다"가 아니라, **자동 테스트가
  /// 이 경로 자체를 타지 않는다** — 실기기(또는 Firebase 프로젝트 실물
  /// 설정)로만 드러나는 유형이다.
  Future<void> signInOrSignUpWithEmail(String email, String password) async {
    final trimmed = email.trim();

    // 가입을 먼저 시도한다.
    final fb_auth.UserCredential cred;
    try {
      cred = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: trimmed, password: password);
    } on fb_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          // 이미 있는 계정이다 — 로그인으로 폴백한다. 정상 경로다(가입
          // 화면에 다시 오는 재방문 이용자는 대부분 여기를 탄다).
          await _signInExistingEmailAccount(trimmed, password);
          return;
        case 'weak-password':
          throw AuthException('6자 이상의 비밀번호를 입력해 주세요.');
        case 'invalid-email':
          throw AuthException('이메일 형식을 확인해 주세요.');
        default:
          debugPrint('이메일 가입 실패: ${e.code}');
          throw AuthException('가입에 실패했어요. 다시 시도해 주세요.');
      }
    } catch (e) {
      debugPrint('이메일 가입 예외: $e');
      throw AuthException('가입 중 문제가 발생했습니다. 다시 시도해 주세요.');
    }

    // 가입 직후 인증 메일 발송(추가 632, §7) — 실패해도 가입 자체는
    // 유지한다. 번호 인증이 실질적인 신원 확인 역할을 대신하므로, 이메일
    // 인증 실패로 가입을 막을 이유가 없다.
    try {
      await cred.user?.sendEmailVerification();
    } catch (e) {
      debugPrint('가입 직후 인증 메일 발송 실패: ${e.runtimeType}');
    }

    await completeSignIn(
      SnsAuthProvider.email,
      displayName: cred.user?.displayName,
      email: cred.user?.email ?? trimmed,
      photoUrl: cred.user?.photoURL,
    );
  }

  /// [signInOrSignUpWithEmail]에서 `email-already-in-use`를 받았을 때
  /// 로그인으로 폴백한다(추가 636).
  ///
  /// ⚠️ **어떤 수단으로 이미 가입돼 있는지는 여기서도 밝히지 않는다** —
  /// 계정 식별 매트릭스(추가 371)가 "이메일 자동 병합은 전 형태 금지"를
  /// 요구한다. 열거 방지가 켜져 있어 "비밀번호가 틀렸다"와 "이 이메일은
  /// SNS로 가입돼 비밀번호 자체가 없다"를 서버 응답만으로 구분할 수도 없다
  /// (둘 다 `invalid-credential`) — 그래서 두 경우 모두 같은 일반 문구로
  /// 답한다. 이전에는 "다른 방법으로 이미 가입돼 있어요"처럼 더 구체적인
  /// 문구를 썼지만, 그 문구도 결국 수단을 밝히지 않았을 뿐 이 메서드에서
  /// email-already-in-use는 더 이상 오류가 아니라 **정상 로그인 경로**가
  /// 됐으므로 여기서는 쓰지 않는다.
  Future<void> _signInExistingEmailAccount(
    String trimmed,
    String password,
  ) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance
          .signInWithEmailAndPassword(email: trimmed, password: password);
      await completeSignIn(
        SnsAuthProvider.email,
        displayName: cred.user?.displayName,
        email: cred.user?.email ?? trimmed,
        photoUrl: cred.user?.photoURL,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
        case 'user-not-found': // 이론상 여기서는 안 나오지만 방어적으로 처리
          throw AuthException(
            '비밀번호가 올바르지 않습니다.',
            offerPasswordReset: true,
          );
        case 'invalid-email':
          throw AuthException('이메일 형식을 확인해 주세요.');
        case 'user-disabled':
          throw AuthException('비활성화된 계정입니다. 고객센터에 문의해 주세요.');
        default:
          debugPrint('이메일 로그인 실패: ${e.code}');
          throw AuthException('로그인에 실패했어요. 다시 시도해 주세요.');
      }
    } catch (e) {
      debugPrint('이메일 로그인 예외: $e');
      throw AuthException('로그인 중 문제가 발생했습니다. 다시 시도해 주세요.');
    }
  }

  /// 비밀번호 재설정 메일을 보낸다(⑩ `PasswordResetView`, 추가 632 §5-3).
  ///
  /// 🚨 **가입한 이메일인지 알려주지 않는다.** `user-not-found`도 성공했을
  /// 때와 똑같이 조용히 반환한다 — 계정 존재 여부를 노출하면 그 자체가
  /// 개인정보 유출(가입 사실)이 된다.
  Future<void> sendPasswordReset(String email) async {
    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim(),
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return;
      if (e.code == 'invalid-email') {
        // 존재 여부가 아니라 **입력한 문자열 자체의 형식 문제**라 이건
        // 갈라도 열거 통로가 되지 않는다.
        throw AuthException('이메일 형식을 확인해 주세요.');
      }
      debugPrint('비밀번호 재설정 메일 발송 실패: ${e.code}');
      throw AuthException('메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
    } catch (e) {
      debugPrint('비밀번호 재설정 예외: $e');
      throw AuthException('메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  /// 이메일 인증 메일을 다시 보낸다(설정 화면 "인증 안 됨" 배지의 재발송
  /// 버튼, 추가 632 §7).
  Future<void> resendVerificationEmail() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AuthException('로그인 상태가 아닙니다. 다시 로그인해 주세요.');
    }
    try {
      await user.sendEmailVerification();
    } catch (e) {
      debugPrint('인증 메일 재발송 실패: ${e.runtimeType}');
      throw AuthException('메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Google Cloud OAuth 클라이언트 등록 전(HANDOFF.md 해야 할 일 7번)에도
  /// 로그인 게이트에 막히지 않고 나머지 화면을 QA할 수 있도록 하는 임시
  /// 우회로. `kDebugMode`로 감싸 있어 release/profile 빌드(스토어 제출용)
  /// 에는 아예 포함되지 않고, 세션도 저장하지 않아 앱을 다시 켜면 원래대로
  /// 로그인 화면부터 시작한다. Gmail OAuth 설정이 끝나 Google 로그인이
  /// 실제로 동작하게 되면 이 메서드와 로그인 화면의 호출부를 지울 것.
  void signInAsGuest() {
    if (!kDebugMode) return;
    _isSignedIn = true;
    _provider = null;
    _displayName = 'QA 게스트';
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_provider == SnsAuthProvider.google) {
      try {
        await GoogleAuthGateway.ensureInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Error signing out of Google: $e');
      }
    }
    // ⚠️ 카카오·네이버는 웹뷰에 제공자 세션 쿠키를 남긴다. 안 지우면 같은
    // 기기의 다음 사람이 '카카오로 계속하기'를 눌렀을 때 **아이디를 묻지 않고
    // 앞사람 계정으로 들어간다** — 이 앱에서는 그게 곧 남의 명함(제3자
    // 개인정보)을 여는 것이다. 자세한 경위는 social_web_session.dart 참고.
    //
    // ⚠️ **여기서 던지면 로그아웃 자체가 막힌다.** 쿠키를 못 지운 것보다
    // 로그아웃을 못 하는 쪽이 나쁘다. (기본 구현은 스스로 삼키지만, 그것에
    // 기대면 구현을 바꾸는 날 조용히 깨진다 — 부르는 쪽에서도 막는다.)
    try {
      await _clearWebSession();
    } catch (e) {
      debugPrint('Error clearing social web session: $e');
    }
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Error signing out of Firebase Auth: $e');
    }
    _isSignedIn = false;
    _provider = null;
    _displayName = null;
    _email = null;
    _photoUrl = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _sessionKey);
    } catch (e) {
      debugPrint('Error clearing auth session: $e');
    }
  }

  /// 계정 삭제(backlog #49) 직전 재인증이 필요할 때(Firebase Auth의
  /// `requires-recent-login`) Google 계정으로 다시 로그인해 최신 자격
  /// 증명을 얻고 현재 Firebase Auth 사용자에 재인증을 건다.
  Future<void> reauthenticateWithGoogle() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AuthException('로그인 상태가 아닙니다. 다시 로그인해 주세요.');
    }
    await GoogleAuthGateway.ensureInitialized();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } catch (e) {
      throw AuthException('Google 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw AuthException('Google 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
    try {
      final credential = fb_auth.GoogleAuthProvider.credential(
        idToken: idToken,
      );
      await user.reauthenticateWithCredential(credential);
    } catch (e) {
      throw AuthException('Google 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
  }

  /// 계정 삭제(backlog #49) 직전 재인증이 필요할 때 Apple 계정으로 다시
  /// 로그인해 최신 자격 증명을 얻고 현재 Firebase Auth 사용자에 재인증을
  /// 건다. [reauthenticateWithGoogle]과 대칭되는 Apple 버전.
  Future<void> reauthenticateWithApple() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw AuthException('로그인 상태가 아닙니다. 다시 로그인해 주세요.');
    }
    final rawNonce = generateNonce();
    final hashedNonce = _sha256(rawNonce);
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } catch (e) {
      throw AuthException('Apple 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw AuthException('Apple 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
    try {
      final oauthCredential = fb_auth.OAuthProvider(
        'apple.com',
      ).credential(idToken: identityToken, rawNonce: rawNonce);
      await user.reauthenticateWithCredential(oauthCredential);
    } catch (e) {
      throw AuthException('Apple 재인증에 실패했습니다. 다시 시도해 주세요.');
    }
  }

  /// 계정 삭제 재인증 진입점 — 현재 로그인된 SNS provider에 맞는 재인증
  /// 메서드로 라우팅한다. 호출자(설정 화면)는 provider별 분기를 알 필요
  /// 없이 이 메서드 하나만 부르면 된다.
  ///
  /// provider를 알 수 없는 경우(예: 게스트 QA 로그인)에는 재인증할 SNS
  /// 계정 자체가 없으므로 명확한 예외를 던진다.
  ///
  /// ## ⚠️ 카카오·네이버는 [openAuth] 가 있어야 한다
  ///
  /// 이 둘은 커스텀 토큰으로 로그인하므로, 재인증도 **인증 화면을 다시 띄워
  /// 새 토큰을 받는 것**이다. 화면을 띄우는 함수가 없으면 재인증을 할 수
  /// 없고, **재인증이 막히면 계정 삭제가 막힌다** — 개인정보 파기 의무와
  /// 직결되는 자리라 조용히 실패하게 두지 않고 이유를 밝혀 던진다.
  Future<void> reauthenticateCurrentProvider({
    Future<social.OauthOutcome> Function(social.SocialProvider)? openAuth,
  }) async {
    switch (_provider) {
      case SnsAuthProvider.google:
        await reauthenticateWithGoogle();
      case SnsAuthProvider.apple:
        await reauthenticateWithApple();
      case SnsAuthProvider.kakao:
      case SnsAuthProvider.naver:
        // ⚠️ 두 사유를 갈라서 말한다. 문구 하나로 뭉치면 이용자는 **자기가
        // 뭘 해야 하는지** 알 수 없고, 우리도 화면만 보고는 원인을 못 가린다.
        if (!_provider!.isAvailable) {
          // 키 없이 빌드된 판. 이용자가 다시 눌러도 결과가 같으므로
          // "다시 시도"라고 하지 않는다.
          throw AuthException(
            '이 빌드에서는 ${_provider!.displayName} 계정을 확인할 수 없어 계정을 지울 수 없습니다. '
            '정식 앱에서 다시 시도해 주세요.',
          );
        }
        if (openAuth == null) {
          // 부르는 쪽이 인증 화면 여는 함수를 안 넘긴 것 — 이용자 잘못이
          // 아니라 **우리 배선 문제**다. 조용히 지나가면 "탈퇴가 안 되는데
          // 이유를 모르는" 상태가 된다.
          throw AuthException('${_provider!.displayName} 재인증 화면을 열지 못했습니다. 앱을 다시 켠 뒤 시도해 주세요.');
        }
        // 다시 로그인하는 것이 곧 재인증이다 — signInWithCustomToken 이
        // "최근 로그인" 시각을 갱신한다.
        await signInWithSocial(_provider!, openAuth);
      case SnsAuthProvider.email:
        // ⚠️ **범위 밖(추가 632 §7·마감 대응 지침)** — 비밀번호를 다시 입력받는
        // 화면이 아직 없다. 계정 삭제가 "최근 로그인 아님"으로 막힌 이메일
        // 계정은, 로그아웃 후 재로그인하면 Firebase 세션이 새로워져 이
        // 조건 자체가 사라진다 — 그 우회로를 안내한다. 막다른 예외로 두지
        // 않고 다음에 할 일을 알려 준다.
        throw AuthException(
          '보안을 위해 다시 로그인해야 합니다. 로그아웃한 뒤 이메일로 다시 '
          '로그인하고, 계정 삭제를 다시 시도해 주세요.',
        );
      case null:
        throw AuthException('재인증할 수 있는 로그인 수단이 없습니다. 다시 로그인해 주세요.');
    }
  }

  /// 계정 삭제(backlog #49)의 마지막 단계 — Firebase Auth 계정 자체를
  /// 지우고, 로그아웃과 동일하게 로컬 세션(Google 로그아웃 + 암호화 저장된
  /// 세션 삭제)도 정리한다.
  ///
  /// 호출 순서 주의: 서버 쪽 Firestore 데이터(`DataBackupService
  /// .deleteAllUserData`)는 이 메서드보다 **먼저** 지워야 한다 — Firebase
  /// Auth 계정이 사라지면 더 이상 인증된 요청이 아니게 되어 Firestore 보안
  /// 규칙(본인 uid만 read/write 허용)에 막히기 때문이다.
  ///
  /// 다른 기기에서 이미 이 계정을 삭제했는지 확인한다.
  ///
  /// **왜 필요한가(다기기 시나리오)**: 기기 A에서 계정을 삭제하면 서버의 계정
  /// (uid)이 사라지지만, 기기 B는 그 사실을 모른 채 옛 로그인 세션을 들고 있다.
  /// 이 상태에서 B가 계정 삭제를 시도하면 서버에 토큰을 갱신하려다 실패하는데,
  /// 그 실패가 "네트워크 오류"처럼 보여 사용자를 혼란스럽게 한다(실제 원인은
  /// "계정이 이미 없음"). 삭제 흐름을 타기 전에 이걸 먼저 판별해, 이미 없는
  /// 계정이면 서버 요청 없이 로컬만 정리하고 로그아웃시킨다.
  ///
  /// 토큰을 **강제 갱신**해서, `user-not-found`/`user-token-expired`/
  /// `user-disabled`로 실패하면 계정이 이미 없는 것으로 보고 true를 반환한다.
  /// 네트워크 등 다른 이유의 실패는 그대로 던져(호출자가 진짜 오류로 처리).
  Future<bool> isAccountAlreadyDeleted() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return true; // 로컬 세션조차 없으면 이미 없는 것
    try {
      await user.getIdToken(true);
      return false; // 갱신 성공 = 서버에 계정이 살아 있음
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'user-token-expired' ||
          e.code == 'user-disabled') {
        return true;
      }
      rethrow; // 네트워크 등 진짜 실패는 호출자에게 넘긴다
    }
  }

  /// 최근 로그인 상태가 아니면 Firebase가 `requires-recent-login` 에러를
  /// 던지는데, 이 경우 [AuthException.requiresReauth]를 true로 세팅해
  /// 던진다 — 호출자(설정 화면)가 이를 보고 [reauthenticateCurrentProvider]로
  /// 재인증한 뒤 이 메서드를 다시 호출해야 한다.
  Future<void> deleteFirebaseAccountAndLocalSession() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.delete();
      } on fb_auth.FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          throw AuthException(
            '보안을 위해 다시 로그인해주세요.',
            requiresReauth: true,
          );
        }
        // 다른 기기에서 이미 삭제된 계정이면 서버엔 지울 게 없다 — 삭제의
        // 목표(계정 제거)는 이미 달성됐으므로 실패로 보지 않고 로컬 정리로
        // 넘어간다(아래 signOut 흐름과 동일한 종착점).
        if (e.code != 'user-not-found' &&
            e.code != 'user-token-expired' &&
            e.code != 'user-disabled') {
          throw AuthException('계정 삭제에 실패했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.');
        }
      } catch (e) {
        throw AuthException('계정 삭제에 실패했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.');
      }
    }
    if (_provider == SnsAuthProvider.google) {
      try {
        await GoogleAuthGateway.ensureInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('Error signing out of Google after account deletion: $e');
      }
    }
    // ⚠️ 탈퇴에서는 더 무겁다 — 쿠키가 남으면 "탈퇴했는데 다시 눌렀더니
    // 로그인되더라"가 된다. 개인정보 파기 의무와 어긋나 보인다.
    // 그래도 여기서 던지지 않는다: 계정은 이미 지워진 뒤라, 여기서 멈추면
    // 로컬 세션만 남아 "지워졌는데 로그인된 것처럼 보이는" 상태가 된다.
    try {
      await _clearWebSession();
    } catch (e) {
      debugPrint('Error clearing social web session after account deletion: $e');
    }
    _isSignedIn = false;
    _provider = null;
    _displayName = null;
    _email = null;
    _photoUrl = null;
    notifyListeners();
    try {
      await _secureStorage.delete(key: _sessionKey);
    } catch (e) {
      debugPrint('Error clearing auth session after account deletion: $e');
    }
    // 계정 자체가 없어졌으므로 "최근"으로 안내하면 안 된다(로그아웃과 달리
    // 여기서는 지운다 — docs/planning/specs/login-recent-provider-2026-08-29.md §4-3).
    await clearLastProviderForAccountDeletion();
  }

  /// 계정 삭제([deleteFirebaseAccountAndLocalSession])에서만 부른다 — 삭제된
  /// 계정을 "최근"으로 안내하면 없어진 계정으로 이용자를 유도하는 꼴이 된다.
  /// `@visibleForTesting`인 이유: [deleteFirebaseAccountAndLocalSession] 자체는
  /// 첫 줄이 `FirebaseAuth.instance`라 Firebase 앱 초기화가 없는 `flutter
  /// test`에서는 부를 수 없다(예외가 던져진다) — 그래서 이 메서드만 따로
  /// 떼어 검증한다(Firebase를 건드리지 않는 순수 로컬 정리이므로 가능하다).
  @visibleForTesting
  Future<void> clearLastProviderForAccountDeletion() async {
    _lastProviderWriteVersion++;
    _lastProvider = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastProviderKey);
    } catch (e) {
      debugPrint('Error clearing last login provider: $e');
    }
  }

  Future<void> _persist() async {
    try {
      await _secureStorage.write(
        key: _sessionKey,
        value: jsonEncode({
          'provider': _provider?.name,
          'displayName': _displayName,
          'email': _email,
          'photoUrl': _photoUrl,
        }),
      );
    } catch (e) {
      debugPrint('Error saving auth session: $e');
    }
  }
}
