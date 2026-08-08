import 'dart:async';

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

  /// 토큰 발급을 기다리는 상한. 이 시간을 넘기면 포기하고 앱을 계속 띄운다.
  static const _activateTimeout = Duration(seconds: 5);

  /// 앱 시작 시 한 번 호출한다. `Firebase.initializeApp()` 이후여야 한다.
  ///
  /// **절대 앱 시작을 막지 않는다.** 예외뿐 아니라 "응답 없음"까지 막아야 한다.
  ///
  /// 왜 이렇게까지 하나 — 2026-08-08 실기기에서 실제로 터졌다. 이 함수를
  /// `main()`에서 `await`로 부르고 있었는데, 기기의 App Check 디버그 토큰이
  /// Firebase에 등록된 것과 달라지자 토큰 교환이 끝없이 재시도됐다. 예외가
  /// 나지 않으니 try/catch로도 못 잡았고, `runApp()`에 도달하지 못해 **UI가
  /// 하나도 없는 네이티브 스플래시가 영원히 떠 있는** 상태가 됐다. 사용자
  /// 눈에는 "무한 로딩"이고, 앱을 껐다 켜도 똑같았다.
  ///
  /// 더 위험한 건 테스터 배포다. TestFlight 빌드는 App Attest를 쓰는데 그게
  /// 느리거나 실패하는 기기에서는 **앱이 아예 열리지 않는다.** 20명에게
  /// 뿌렸다면 몇 명은 앱을 못 열었을 것이다.
  ///
  /// **App Check 토큰은 AI 브리핑을 호출할 때 필요하지 앱을 켜는 데 필요하지
  /// 않다.** 그래서 시작 경로에서 떼어낸다. 호출부는 `unawaited`로 부르고,
  /// 여기서도 타임아웃으로 한 번 더 막는다(이중 방어).
  static Future<void> activate() async {
    final useDebugProvider = _forceDebugProvider || !kReleaseMode;
    try {
      await FirebaseAppCheck.instance
          .activate(
            providerAndroid: useDebugProvider
                ? const AndroidDebugProvider()
                : const AndroidPlayIntegrityProvider(),
            providerApple: useDebugProvider
                ? const AppleDebugProvider()
                : const AppleAppAttestProvider(),
          )
          .timeout(_activateTimeout);
    } on TimeoutException {
      // 토큰이 늦게 준비돼도 SDK가 이후 호출에서 알아서 다시 시도한다.
      // 여기서 실패로 처리해도 AI 브리핑이 영구히 막히는 것은 아니다.
      debugPrint('App Check 활성화가 ${_activateTimeout.inSeconds}초 안에 끝나지 않아 계속 진행합니다.');
    } catch (e) {
      // 토큰 원문이나 계정 식별자가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('App Check 활성화 실패: ${e.runtimeType}');
    }
  }
}
