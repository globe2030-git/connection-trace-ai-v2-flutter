import 'package:flutter/foundation.dart';

import '../../core/services/social_oauth.dart' as social;

/// 회원가입/로그인에 쓸 수 있는 SNS 인증 수단.
///
/// ⚠️ **이름을 바꾸면 기존 이용자의 세션이 끊긴다.** `name`이 그대로 기기
/// 저장소(`_persist`)와 서버 claims에 적히기 때문이다.
///
/// 📌 Google·Apple은 Firebase가 기본 제공자로 알지만 **카카오·네이버는
/// 모른다.** 그래서 서버(`socialSignIn`)가 커스텀 토큰을 발급하는 경로를
/// 따로 탄다 — `social_oauth.dart` 참고.
enum SnsAuthProvider {
  google,
  apple,
  kakao,
  naver,
  /// 이메일+비밀번호 가입/로그인(추가 632, ⑧ EmailSignupView).
  ///
  /// ⚠️ **소셜 로그인이 아니다** — `socialProvider`가 `null`을 돌려주고
  /// [signInWithSocial]이 아니라 `AuthRepository.signInOrSignUpWithEmail`을
  /// 탄다. 그래도 이 enum에 넣은 이유는, 광고 동의(`adEmailChannelAvailable`)·
  /// 「최근 로그인」배지 등 **provider 하나로 분기하는 자리가 이미 많아서**,
  /// 별도 타입을 만들면 그 자리마다 이중 분기가 생기기 때문이다.
  email;

  String get displayName => switch (this) {
    SnsAuthProvider.google => 'Google',
    SnsAuthProvider.apple => 'Apple',
    SnsAuthProvider.kakao => '카카오',
    SnsAuthProvider.naver => '네이버',
    SnsAuthProvider.email => '이메일',
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
    // 카카오·네이버는 **빌드에 키가 들어 있어야** 쓸 수 있다. 키 없이 빌드된
    // 판에서는 버튼을 아예 숨긴다 — 눌러도 안 되는 버튼을 두면 이용자는
    // 고장으로 읽는다. 키 주입은 tool/build_app.sh 가 한다.
    SnsAuthProvider.kakao => social.isConfigured(social.SocialProvider.kakao),
    SnsAuthProvider.naver => social.isConfigured(social.SocialProvider.naver),
    // 이메일은 Firebase Auth 기본 제공자라 빌드 키가 필요 없다 — 항상 가능.
    SnsAuthProvider.email => true,
  };

  /// `social_oauth.dart` 쪽 제공자 값. 로그인 흐름을 부를 때 쓴다.
  /// ⚠️ 와일드카드(`_`)를 쓰지 않는다. 제공자를 새로 추가했을 때
  /// **컴파일러가 여기를 짚어 주도록** 남김없이 적는다 — 와일드카드로 두면
  /// 새 제공자가 조용히 `null`이 되어 "버튼은 보이는데 눌러도 아무 일이
  /// 없는" 상태가 된다.
  social.SocialProvider? get socialProvider => switch (this) {
    SnsAuthProvider.kakao => social.SocialProvider.kakao,
    SnsAuthProvider.naver => social.SocialProvider.naver,
    SnsAuthProvider.google || SnsAuthProvider.apple || SnsAuthProvider.email =>
      null,
  };

  String? get unavailableReason => switch (this) {
    SnsAuthProvider.google => null,
    SnsAuthProvider.apple => isAvailable
        ? null
        : 'Apple 로그인은 iOS/macOS 앱에서만 지원됩니다.',
    SnsAuthProvider.kakao || SnsAuthProvider.naver => isAvailable
        ? null
        : '$displayName 로그인은 이 빌드에서 준비되지 않았습니다.',
    SnsAuthProvider.email => null,
  };
}
