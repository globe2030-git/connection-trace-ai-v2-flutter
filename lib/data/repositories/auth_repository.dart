import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/services/google_auth_gateway.dart';
import '../models/sns_auth_provider.dart';

class AuthException implements Exception {
  final String message;

  /// true면 "최근 로그인 상태가 아니어서" 실패한 것 — Firebase Auth의
  /// `requires-recent-login` 에러를 계정 삭제(backlog #49) 흐름에서
  /// 구분해 재인증 절차로 안내하는 데 쓴다.
  final bool requiresReauth;

  AuthException(this.message, {this.requiresReauth = false});
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

  /// 계정 삭제(backlog #49)의 마지막 단계 — Firebase Auth 계정 자체를
  /// 지우고, 로그아웃과 동일하게 로컬 세션(Google 로그아웃 + 암호화 저장된
  /// 세션 삭제)도 정리한다.
  ///
  /// 호출 순서 주의: 서버 쪽 Firestore 데이터(`DataBackupService
  /// .deleteAllUserData`)는 이 메서드보다 **먼저** 지워야 한다 — Firebase
  /// Auth 계정이 사라지면 더 이상 인증된 요청이 아니게 되어 Firestore 보안
  /// 규칙(본인 uid만 read/write 허용)에 막히기 때문이다.
  ///
  /// 최근 로그인 상태가 아니면 Firebase가 `requires-recent-login` 에러를
  /// 던지는데, 이 경우 [AuthException.requiresReauth]를 true로 세팅해
  /// 던진다 — 호출자(설정 화면)가 이를 보고 [reauthenticateWithGoogle]로
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
        throw AuthException('계정 삭제에 실패했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.');
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
