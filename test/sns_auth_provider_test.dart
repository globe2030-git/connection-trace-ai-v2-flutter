import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';

void main() {
  // App Store Review Guideline 4.8 대응 — Apple 로그인은 iOS/macOS에서만
  // 노출돼야 하고, Android 등 다른 플랫폼에서는 버튼 자체가 없어야 한다
  // (login_view.dart가 이 값을 보고 렌더링 여부를 결정한다).
  final originalPlatform = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  group('SnsAuthProvider.google', () {
    test('모든 플랫폼에서 항상 사용 가능하다', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(SnsAuthProvider.google.isAvailable, isTrue, reason: '$platform');
        expect(SnsAuthProvider.google.unavailableReason, isNull);
      }
    });
  });

  group('SnsAuthProvider.apple', () {
    test('iOS에서는 사용 가능하고 준비중 사유가 없다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(SnsAuthProvider.apple.isAvailable, isTrue);
      expect(SnsAuthProvider.apple.unavailableReason, isNull);
    });

    test('macOS에서는 사용 가능하고 준비중 사유가 없다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(SnsAuthProvider.apple.isAvailable, isTrue);
      expect(SnsAuthProvider.apple.unavailableReason, isNull);
    });

    test('Android에서는 사용 불가하고 안내 문구가 있다', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(SnsAuthProvider.apple.isAvailable, isFalse);
      expect(SnsAuthProvider.apple.unavailableReason, isNotNull);
    });
  });

  group('SnsAuthProvider.email (추가 632)', () {
    test('모든 플랫폼에서 항상 사용 가능하다 — 빌드 키가 필요 없다', () {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(SnsAuthProvider.email.isAvailable, isTrue, reason: '$platform');
        expect(SnsAuthProvider.email.unavailableReason, isNull);
      }
    });

    test('socialProvider는 null이다 — social_oauth.dart 경로를 타지 않는다', () {
      expect(SnsAuthProvider.email.socialProvider, isNull);
    });
  });
}
