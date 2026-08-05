import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱을 지웠다가 다시 설치했을 때 기기에 남은 보안 저장소 데이터를 비운다.
///
/// **왜 필요한가**: iOS의 Keychain 항목은 **앱을 삭제해도 지워지지 않는다.**
/// 앱 컨테이너(`shared_preferences`, 캐시 사진)만 사라지고 Keychain은 기기에
/// 그대로 남는다. 그래서 재설치하면
/// [`AuthRepository`]의 로그인 세션과 [`EncryptionKeyService`]의 계정별
/// 암호화 키가 되살아나, 설정 화면에 이전 로그인 정보가 그대로 보이는
/// 상태가 된다(2026-08-05 실기기에서 확인 — backlog 추가 78).
///
/// 이건 두 가지 이유로 고쳐야 한다:
/// 1. **사용자 기대와 어긋난다.** 앱을 지우면 흔적이 없어질 거라고 보는 게
///    자연스러운데 신원 정보가 기기에 남는다. 폰을 넘기거나 중고로 팔 때
///    (기기 초기화를 하지 않으면) 그대로 남는다.
/// 2. **개인정보처리방침의 보유기간 서술과 어긋난다.**
///
/// **어떻게 감지하나**: `shared_preferences`는 앱 삭제 시 지워지고 Keychain은
/// 안 지워진다는 **비대칭**을 그대로 이용한다. 앱 시작 시
/// `shared_preferences`에 설치 표식이 없으면 "이 설치본은 처음 실행되는
/// 것"이므로, 보안 저장소를 비우고 표식을 남긴다. 안드로이드는 앱 삭제 시
/// Keystore도 함께 지워지므로 이 정리는 사실상 아무 일도 하지 않는다(무해).
///
/// **데이터 손실이 없는 이유**: 암호화 키는 Firestore
/// `users/{uid}.encryptionKeyB64`에도 보관되므로, 다시 로그인하면
/// [`EncryptionKeyService`]가 서버에서 내려받아 기존 암호문을 그대로 연다.
/// 지워지는 것은 "기기에 캐시된 사본"일 뿐이다.
class FreshInstallService {
  /// `shared_preferences`에 남기는 설치 표식. 이 키가 없으면 재설치로 본다.
  static const String markerKey = 'install_marker_v1';

  /// 재설치로 판단되면 보안 저장소를 비운다. **앱 시작 시 다른 저장소 접근보다
  /// 먼저** 호출해야 한다.
  ///
  /// 반환값은 "실제로 정리를 수행했는지"다(최초 설치 포함).
  ///
  /// 실패했을 때는 **정리하지 않는 쪽**으로 넘어간다 —
  /// `shared_preferences`를 일시적으로 못 읽었다는 이유로 멀쩡히 쓰던
  /// 사용자를 로그아웃시키는 게 훨씬 나쁜 결과이기 때문이다.
  static Future<bool> purgeIfReinstalled({
    FlutterSecureStorage? secureStorage,
    Future<void> Function()? signOut,
  }) async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('설치 표식 확인 실패 — 정리를 건너뛴다: $e');
      return false;
    }

    if (prefs.getBool(markerKey) ?? false) return false;

    // 표식이 없다고 곧바로 재설치로 단정하면 안 된다. 이 로직이 없던 버전에서
    // 업데이트한 기존 사용자도 표식이 없기 때문이다 — 그대로 두면 **앱을 지운
    // 적도 없는 사용자 전원이 업데이트 한 번에 로그아웃된다.**
    //
    // 진짜 재설치라면 `shared_preferences`가 앱과 함께 통째로 지워져 **완전히
    // 비어 있다.** 반대로 쓰던 앱을 업데이트한 것이라면 명함·프로필·위치 동의
    // 같은 키가 남아 있다. 그 차이로 구분한다.
    final leftoverKeys = prefs.getKeys().where((k) => k != markerKey);
    if (leftoverKeys.isNotEmpty) {
      await prefs.setBool(markerKey, true);
      debugPrint('기존 설치본으로 판단 — 보안 저장소를 유지하고 표식만 남긴다.');
      return false;
    }

    // 여기부터는 이 설치본의 첫 실행이다.
    final storage = secureStorage ?? const FlutterSecureStorage();
    try {
      await storage.deleteAll();
    } catch (e) {
      // 최초 설치라면 지울 것도 없으므로 실패해도 진행한다.
      debugPrint('보안 저장소 정리 실패: $e');
    }

    // Firebase Auth SDK도 자체 세션을 Keychain에 보관하므로 함께 끊는다.
    // (우리 secure storage 항목만 지우면 Firebase는 여전히 로그인 상태다.)
    try {
      await (signOut ?? _defaultSignOut)();
    } catch (e) {
      debugPrint('Firebase 세션 정리 실패: $e');
    }

    await prefs.setBool(markerKey, true);
    debugPrint('재설치 감지 — 기기에 남아 있던 보안 저장소를 정리했다.');
    return true;
  }

  static Future<void> _defaultSignOut() => FirebaseAuth.instance.signOut();
}
