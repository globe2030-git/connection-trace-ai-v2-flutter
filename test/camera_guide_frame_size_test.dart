import 'package:flutter/foundation.dart' show TargetPlatform;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/camera_guide_frame_size.dart';

/// 명함 촬영 가이드 상자 크기.
///
/// ## ⚠️ 2026-08-21 개정 — 비율이 아니라 **절대 크기**가 문제였다
///
/// 실기기 치수를 늘어놓고 보니 **비율은 같은데 dp 가 제각각**이었고,
/// 사용자가 반응한 값은 비율이 아니라 dp 였다.
///
/// ```
/// 폴드 펼침      41.3% = 309dp   → "너무 크네" (8/17)
/// 폴드 커버      65.0% = 267dp   → 좋다
/// 아이폰 16 Pro  41.3% = 166dp   → "작다"
/// ```
///
/// ⚠️ 아이폰(2.17)과 갤럭시 S24(2.17)는 **세로세로비가 같다.** 그래서
/// "아이폰만 키우기"는 세로비로는 불가능했다 — 문턱값 방식을 버린 이유다.
void main() {
  /// 짧은 변이 화면 폭에서 차지하는 비율.
  double widthRatio(Size screen) =>
      guideFrameSizeFor(screen, platform: TargetPlatform.android).width / screen.width;

  group('규칙: min(폭 × 플랫폼별 비율, 267dp)', () {
    test('아이폰은 폭의 50%', () {
      final s = guideFrameSizeFor(const Size(402, 874), platform: TargetPlatform.iOS);
      expect(s.width, closeTo(402 * kGuideShortEdgeRatioIos, 0.01));
    });

    test('⚠️ 아이폰 비율을 0.65 로 올리지 말 것 — 초점이 흐렸다', () {
      // 2026-08-21 실측. 폴드 커버는 0.65 에서 괜찮았지만 아이폰은 아니었다.
      // 카메라 최소 초점 거리가 기기마다 달라서다.
      expect(kGuideShortEdgeRatioIos, lessThan(0.65));
    });

    test('⭐ 안드로이드는 0.65 를 유지한다 — 폴드 커버에서 확인된 값', () {
      expect(kGuideShortEdgeRatioDefault, 0.65);
      final s = guideFrameSizeFor(const Size(411.4, 960),
          platform: TargetPlatform.android);
      expect(s.width, closeTo(267, 0.5), reason: '#384 값 그대로여야 한다');
    });

    test('⚠️ 같은 화면이라도 플랫폼이 다르면 크기가 다르다', () {
      const screen = Size(402, 874);
      final ios = guideFrameSizeFor(screen, platform: TargetPlatform.iOS);
      final android = guideFrameSizeFor(screen, platform: TargetPlatform.android);
      expect(ios.width, lessThan(android.width),
          reason: '아이폰은 초점 때문에 더 작아야 한다');
    });

    test('⭐ 넓은 화면은 절대 상한에서 멈춘다', () {
      // 폴드 펼침. 예전에는 309dp 였고 "너무 크다"는 제보를 받았다.
      final s = guideFrameSizeFor(const Size(749.7, 831.4), platform: TargetPlatform.android);
      expect(s.width, closeTo(kGuideMaxShortEdgeDp, 0.01));
      expect(s.width, lessThan(309), reason: '⭐ 줄어들어야 8/17 제보와 맞는다');
    });

    test('⭐ 폴더블 커버는 #384 값(267dp)을 그대로 유지한다', () {
      // 한때 전 기기를 한 값으로 맞추려다 커버를 226 으로 줄이는 안까지
      // 갔지만, 플랫폼으로 가르면 **좋다고 확인된 값을 건드리지 않아도
      // 된다.** 그게 플랫폼 분기를 택한 이유 중 하나다.
      final s = guideFrameSizeFor(const Size(411.4, 960),
          platform: TargetPlatform.android);
      expect(s.width, closeTo(267, 0.5));
    });

    test('카드 비율은 그대로다', () {
      final s = guideFrameSizeFor(const Size(402, 874), platform: TargetPlatform.iOS);
      expect(s.width / s.height, closeTo(kCardGuideAspectRatio, 0.0001));
    });
  });

  group('⭐ 실기기 12종 — 모두 커지거나 유지되고, 넓은 화면만 줄어든다', () {
    // ⚠️ 폴드 둘만 adb 실측. 나머지는 제원표 기준이다.
    const devices = <String, Size>{
      'iPhone SE 2/3': Size(375, 667),
      'iPhone 13 mini': Size(375, 812),
      'iPhone 12/13/14': Size(390, 844),
      'iPhone 15/16': Size(393, 852),
      'iPhone 16 Pro': Size(402, 874),
      'iPhone 16 Plus': Size(430, 932),
      'iPhone 16 Pro Max': Size(440, 956),
      '갤럭시 S6(구형)': Size(360, 800),
      '갤럭시 S24': Size(384, 832),
      '픽셀 8': Size(412, 892),
      '폴드 커버(실측)': Size(411.4, 960),
      '폴드 펼침(실측)': Size(749.7, 831.4),
    };

    test('⚠️ 어떤 기기도 높이 상한에 닿지 않는다 — 세로로 안 넘친다', () {
      // 폴더블 가로 화면에서 아래가 넘친 전례가 있다.
      devices.forEach((name, screen) {
        final s = guideFrameSizeFor(screen, platform: TargetPlatform.android);
        expect(
          s.height,
          lessThanOrEqualTo(screen.height * kGuideMaxHeightRatio + 0.01),
          reason: '$name 에서 높이 상한을 넘었다',
        );
      });
    });

    test('⚠️ 짧은 변이 절대 상한을 넘는 기기가 없다 — 초점 회귀 방지', () {
      // 키우면 명함을 더 가까이 대게 되고, 렌즈 최소 초점 거리보다 가까워지면
      // 초점이 영영 안 맞는다(2026-08-06 실기기).
      devices.forEach((name, screen) {
        expect(
          guideFrameSizeFor(screen, platform: TargetPlatform.android).width,
          lessThanOrEqualTo(kGuideMaxShortEdgeDp + 0.01),
          reason: '$name 에서 상한을 넘었다',
        );
      });
    });

    test('폭이 좁은 기기도 폭의 65%를 넘지 않는다 — 좌우 여백 확보', () {
      devices.forEach((name, screen) {
        expect(
          widthRatio(screen),
          lessThanOrEqualTo(kGuideShortEdgeRatioDefault + 0.001),
          reason: '$name 에서 화면을 너무 채운다',
        );
      });
    });
  });

  group('이상한 입력', () {
    test('⚠️ 0이나 음수에도 예외를 던지지 않는다', () {
      // 여기서 던지면 촬영 화면이 통째로 안 뜬다.
      expect(guideFrameSizeFor(Size.zero, platform: TargetPlatform.android), Size.zero);
      expect(guideFrameSizeFor(const Size(-100, -100), platform: TargetPlatform.android), Size.zero);
      expect(guideFrameSizeFor(const Size(0, 800), platform: TargetPlatform.android), Size.zero);
    });

    test('아주 낮은 화면에서는 높이 상한이 먼저 걸린다', () {
      // 가로로 눕힌 상태 등.
      final s = guideFrameSizeFor(const Size(800, 300), platform: TargetPlatform.android);
      expect(s.height, closeTo(300 * kGuideMaxHeightRatio, 0.01));
      expect(s.width / s.height, closeTo(kCardGuideAspectRatio, 0.0001));
    });
  });
}
