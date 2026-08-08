import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Firebase App Check — "이 호출이 진짜 우리 앱에서 왔는가"를 증명하는 토큰을
/// 발급받아, 이후 Firebase 호출(특히 Cloud Functions `generateBriefing`)에
/// 자동으로 실어 보낸다.
///
/// **왜 필요한가**: `generateBriefing`은 `request.auth`만 검사했다. 즉 Google
/// 로그인만 통과하면 우리 앱이 아닌 스크립트도 호출할 수 있었는데, 그 호출은
/// 회사 명의 **유료** Gemini 키로 나가므로 그대로 요금이 된다. uid당 하루 10회
/// 한도가 있지만 계정을 여러 개 만들면 우회된다(backlog 추가 82 신규-B).
/// 2026-08-08부터 서버가 `enforceAppCheck: true`로 토큰을 요구한다.
///
/// **토큰을 못 만들면 AI 브리핑이 막힌다.** 그래서 어떤 제공자를 쓰는지가
/// 중요하다 — 아래 [_forceDebugProvider] 주석 참고.
class AppCheckService {
  /// 릴리스 빌드인데도 debug 제공자를 쓰게 하는 탈출구
  /// (`--dart-define=APP_CHECK_DEBUG=true`).
  ///
  /// **왜 필요한가 — 2026-08-08 실기기에서 확인한 사실**: 정식 무결성 검증기는
  /// 스토어 배포를 전제로 한다.
  /// - **Play Integrity**는 Google Play가 아는 앱만 통과시킨다. 지금 Android
  ///   릴리스는 Play에 없고 debug 키로 서명돼 있다(P1-19).
  /// - **App Attest**는 개발 서명 빌드를 거부한다. 실제로 iPhone 16 Pro에
  ///   릴리스 빌드를 직접 설치해 호출해 보니 Firebase가
  ///   `403 App attestation failed`로 증명을 거부했다(TestFlight/App Store
  ///   빌드여야 통과, 그건 P0-1 해결 후에나 가능).
  ///
  /// 그래서 **스토어를 거치지 않는 빌드**(테스터 배포용 APK, devicectl로 직접
  /// 설치하는 iOS 빌드)는 이 플래그를 켜서 debug 제공자를 쓰고, 그 기기의
  /// 디버그 토큰을 Firebase에 등록해서 쓴다. `tool/build_app.sh`에
  /// `appcheck-debug` 인자로 붙일 수 있다.
  ///
  /// ⚠️ **스토어에 올리는 빌드에는 절대 켜지 말 것** — 켜면 아무나 디버그
  /// 토큰만 있으면 우리 앱인 척할 수 있어 App Check가 무의미해진다.
  static const bool _forceDebugProvider = bool.fromEnvironment(
    'APP_CHECK_DEBUG',
  );

  /// 앱 시작 시 한 번 호출한다. `Firebase.initializeApp()` 이후여야 한다.
  ///
  /// 실패해도 앱을 멈추지 않는다 — 토큰 발급은 네트워크와 OS 서비스(Play
  /// 서비스, Apple 서버)에 의존해 실패할 수 있는데, 그때 앱 전체가 안 뜨는
  /// 것보다 AI 브리핑만 안 되는 편이 낫다. 다른 화면은 App Check와 무관하다.
  static Future<void> activate() async {
    final useDebugProvider = _forceDebugProvider || !kReleaseMode;
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugProvider
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: useDebugProvider
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
    } catch (e) {
      // 토큰 원문이나 계정 식별자가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('App Check 활성화 실패: ${e.runtimeType}');
    }
  }
}
