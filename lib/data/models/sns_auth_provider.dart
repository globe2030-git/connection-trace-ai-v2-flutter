import 'package:flutter/foundation.dart';

/// 회원가입/로그인에 쓸 수 있는 SNS 인증 수단. 카카오는 이번 범위에서 제외.
enum SnsAuthProvider {
  google,
  apple;

  String get displayName => switch (this) {
    SnsAuthProvider.google => 'Google',
    SnsAuthProvider.apple => 'Apple',
  };

  /// 지금 바로 로그인 가능한지.
  ///
  /// Apple은 **iOS/macOS에서만** true다 — App Store Review Guideline 4.8은
  /// "제3자 SNS 로그인을 제공하면 Apple 로그인도 동등하게 제공해야 한다"는
  /// App Store(iOS) 심사 요구사항이라 Android에는 적용되지 않는다. Android에서
  /// Apple 로그인을 붙이려면 Apple Developer 콘솔에 Services ID를 추가로
  /// 만들고 웹 리다이렉트 URL을 구성해야 하는데, 이건 iOS 네이티브
  /// AuthenticationServices 플로우와 별개의 작업이라 이번 범위에서는 의도적으로
  /// 제외했다(PM 결정, backlog 참고 — 임의로 확장하지 말 것).
  bool get isAvailable => switch (this) {
    SnsAuthProvider.google => true,
    SnsAuthProvider.apple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS,
  };

  String? get unavailableReason => switch (this) {
    SnsAuthProvider.google => null,
    SnsAuthProvider.apple => isAvailable
        ? null
        : 'Apple 로그인은 iOS/macOS 앱에서만 지원됩니다.',
  };
}
