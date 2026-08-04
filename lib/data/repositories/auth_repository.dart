import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/services/google_auth_gateway.dart';
import '../models/sns_auth_provider.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
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

  final FlutterSecureStorage _secureStorage;

  bool _isLoading = true;
  bool _isSignedIn = false;
  SnsAuthProvider? _provider;
  String? _displayName;
  String? _email;
  String? _photoUrl;

  AuthRepository({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _load();
  }

  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  SnsAuthProvider? get provider => _provider;
  String? get displayName => _displayName;
  String? get email => _email;
  String? get photoUrl => _photoUrl;

  /// 명함/프로필 서버 백업·복원(backlog 추가 66)에 쓰는 Firebase Auth 계정
  /// 고유 ID. 기기 로컬 세션(`_isSignedIn` 등)과는 별개로, Firebase 쪽 로그인
  /// 상태가 살아있을 때만 값이 있다 — 게스트 QA 로그인(`signInAsGuest`)이나
  /// Firebase Auth 초기화 전에는 null이라 백업/복원 로직은 이 값이 있을
  /// 때만 동작해야 한다.
  String? get firebaseUid => fb_auth.FirebaseAuth.instance.currentUser?.uid;

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
    _provider = SnsAuthProvider.google;
    _displayName = account.displayName;
    _email = account.email;
    _photoUrl = account.photoUrl;
    _isSignedIn = true;
    notifyListeners();
    await _persist();
  }

  Future<void> signInWithApple() async {
    throw AuthException(SnsAuthProvider.apple.unavailableReason!);
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
