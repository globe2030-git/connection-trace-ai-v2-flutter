/// 회원가입/로그인에 쓸 수 있는 SNS 인증 수단. 카카오는 이번 범위에서 제외.
enum SnsAuthProvider {
  google,
  apple;

  String get displayName => switch (this) {
    SnsAuthProvider.google => 'Google',
    SnsAuthProvider.apple => 'Apple',
  };

  /// 지금 바로 로그인 가능한지 — Apple은 유료 Apple Developer Program
  /// 가입 전까지는 버튼만 보여주고 비활성화한다.
  bool get isAvailable => switch (this) {
    SnsAuthProvider.google => true,
    SnsAuthProvider.apple => false,
  };

  String? get unavailableReason => switch (this) {
    SnsAuthProvider.google => null,
    SnsAuthProvider.apple =>
      'Apple 로그인은 유료 Apple Developer Program 가입 후 지원 예정입니다.',
  };
}
