// 폴드를 접은 커버 화면에서 명함 촬영 가이드 프레임이 작게 그려지던
// 결함(사용자 실기기 제보, fix/fold-cover-capture-guide)의 회귀 방지.
//
// 원인: 가이드의 긴 변(세로 방향)이 항상 "화면 폭 × 0.74"로만 정해져서,
// 화면 모양과 무관하게 화면 폭의 약 41%(0.74 × 카드비율)라는 **같은
// 비율**이 적용됐다. 그래서 커버 화면처럼 폭 자체가 좁은 기기에서는
// 세로 공간이 남아도는데도 가이드 절대 크기(dp)가 작게 나왔다.
//
// 고친 방식: 화면 폭이 문턱값(kNarrowScreenWidthThreshold, 340dp) 아래일
// 때만 가이드 짧은 변이 화면 폭의 최소 kNarrowScreenWidthRatio(0.62)를
// 차지하도록 다시 계산한다. 일반 폰·펼친 폴드·태블릿(폭이 문턱값 이상인
// 모든 경우)은 이 분기를 타지 않아 기존 계산과 **완전히 같은 값**이
// 나와야 한다 — 그래서 아래 "일반 화면" 테스트들은 옛 계산식을 손으로
// 다시 넣어 값을 비교한다(회귀 검증).
import 'package:connection_trace_ai_flutter/core/utils/camera_guide_frame_size.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

/// 이 보정이 들어가기 전의 계산식을 그대로 재현한다 — "일반 화면에서
/// 크기가 달라지지 않았다"를 값으로 확인하기 위한 기준선(oracle)이다.
Size _legacyGuideFrameSizeFor(Size screenSize) {
  var longEdge = screenSize.width * 0.74;
  final maxLongEdge = screenSize.height * 0.72;
  if (longEdge > maxLongEdge) longEdge = maxLongEdge;
  final shortEdge = longEdge * (184 / 330);
  return Size(shortEdge, longEdge);
}

void main() {
  group('guideFrameSizeFor — 일반 화면은 기존 계산과 완전히 같다(회귀 방지)', () {
    test('일반 폰 세로(390×844, 아이폰 계열)', () {
      const screen = Size(390, 844);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
      // 폭이 문턱값(340) 이상이라 보정 분기를 타지 않았는지도 명시적으로 확인.
      expect(screen.width, greaterThanOrEqualTo(kNarrowScreenWidthThreshold));
    });

    test('일반 폰 세로(360×800, 흔한 안드로이드 기준폭)', () {
      const screen = Size(360, 800);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('펼친 폴드 내부 화면 세로(674×841, 거의 정사각형)', () {
      const screen = Size(674, 841);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
      // 폭이 넓어 높이 상한(0.72)에 걸리는 경로까지 기존과 같은지 확인.
      expect(result.height, lessThanOrEqualTo(screen.height * 0.72 + 0.001));
    });

    test('펼친 폴드를 가로로 눕힌 경우(841×674) — 높이 상한이 걸리는 경로', () {
      const screen = Size(841, 674);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('태블릿 세로(768×1024)', () {
      const screen = Size(768, 1024);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });
  });

  group('guideFrameSizeFor — 좁은 화면(커버 디스플레이)에서는 가로폭을 더 쓴다', () {
    test('커버 화면 추정 비율(320×720)에서 옛 계산보다 뚜렷이 커진다', () {
      const screen = Size(320, 720);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);

      // 문턱값보다 좁아 보정 분기를 탄다.
      expect(screen.width, lessThan(kNarrowScreenWidthThreshold));

      // 짧은 변(화면 가로폭 방향)이 옛 계산보다 커야 한다 — 이게 이번
      // 수정의 핵심이다.
      expect(result.width, greaterThan(legacy.width));
      // 화면 폭의 최소 비율을 보장한다.
      expect(
        result.width,
        moreOrLessEquals(
          screen.width * kNarrowScreenWidthRatio,
          epsilon: 0.001,
        ),
      );
      // 긴 변도 비례해서 커져야 카드 비율이 유지된다.
      expect(result.height, greaterThan(legacy.height));
    });

    test('더 좁은 커버 화면 추정 비율(300×760)에서도 같은 방향으로 커진다', () {
      const screen = Size(300, 760);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);

      expect(result.width, greaterThan(legacy.width));
      expect(result.height, greaterThan(legacy.height));
      expect(
        result.width,
        moreOrLessEquals(
          screen.width * kNarrowScreenWidthRatio,
          epsilon: 0.001,
        ),
      );
    });

    test('문턱값 바로 아래(339×900)에서도 보정이 걸린다', () {
      const screen = Size(339, 900);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, greaterThan(legacy.width));
    });

    test('문턱값 정확히(340×900)에서는 보정이 걸리지 않는다(경계값)', () {
      const screen = Size(kNarrowScreenWidthThreshold, 900);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('좁은 화면이라도 세로 공간이 부족하면 높이 상한(0.72)을 넘지 않는다', () {
      // 극단적으로 좁고 낮은 화면을 가정 — 보정된 긴 변이 높이 상한을
      // 넘어서면 다시 상한으로 잘려야 한다.
      const screen = Size(320, 300);
      final result = guideFrameSizeFor(screen);
      expect(result.height, lessThanOrEqualTo(screen.height * 0.72 + 0.001));
    });

    test('카드 가로세로비(184/330)는 보정 후에도 유지된다', () {
      const screen = Size(320, 900);
      final result = guideFrameSizeFor(screen);
      expect(
        result.width / result.height,
        closeTo(184 / 330, 0.0001),
      );
    });
  });
}
