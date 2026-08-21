// 폴드를 접은 커버 화면에서 명함 촬영 가이드 프레임이 작게 그려지던
// 결함(사용자 실기기 제보, fix/fold-cover-capture-guide)의 회귀 방지.
//
// ⚠️ 이 파일은 **재작업 결과**다. 1차 수정은 "화면 폭이 340dp보다 좁으면"을
// 게이트로 썼는데(계산, 실측 아님), 실측 결과(2026-08-21, `adb dumpsys
// display`로 SM-F966N 직접 측정) **틀렸다** — 커버 화면 논리 폭이 411.4dp로
// 오히려 일반 폰(360~412dp)보다 넓어서, 1차 수정의 보정 분기가 실기기에서
// 한 번도 안 걸렸다. 사용자 실물 캡처·영상으로도 확인: 가이드가 화면 폭의
// 약 41%·높이의 약 31%로 **기존 계산식과 정확히 일치**했다.
//
// 진짜 원인은 폭이 아니라 **세로세로비**다. 커버 화면(411.4×960dp)의
// 비율은 2.33인데, 일반 폰은 (커버와 폭이 비슷하거나 더 넓어도) 대략
// 2.0~2.22에 머문다. 그래서 이번엔 **세로세로비**로 게이트를 걸고, 같은
// 폭(411dp)에서 비율만 다른 두 화면을 직접 대조하는 테스트를 포함한다.
import 'package:connection_trace_ai_flutter/core/utils/camera_guide_frame_size.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

/// 이 보정이 들어가기 전(원래 있던) 계산식을 그대로 재현한다 — "일반
/// 화면에서 크기가 달라지지 않았다"를 값으로 확인하기 위한 기준선(oracle).
Size _legacyGuideFrameSizeFor(Size screenSize) {
  var longEdge = screenSize.width * 0.74;
  final maxLongEdge = screenSize.height * 0.72;
  if (longEdge > maxLongEdge) longEdge = maxLongEdge;
  final shortEdge = longEdge * (184 / 330);
  return Size(shortEdge, longEdge);
}

void main() {
  group('guideFrameSizeFor — 일반 화면은 기존 계산과 완전히 같다(회귀 방지)', () {
    test('일반 폰 세로(390×844, 아이폰 계열, 비율 2.16)', () {
      const screen = Size(390, 844);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
      expect(
        screen.height / screen.width,
        lessThan(kNarrowAspectThreshold),
      );
    });

    test('일반 폰 세로(360×800, 흔한 안드로이드 기준폭, 비율 2.22)', () {
      const screen = Size(360, 800);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('펼친 폴드 내부 화면 세로(674×841, 거의 정사각형, 비율 1.25)', () {
      const screen = Size(674, 841);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
      expect(result.height, lessThanOrEqualTo(screen.height * 0.72 + 0.001));
    });

    test('펼친 폴드를 가로로 눕힌 경우(841×674) — 높이 상한이 걸리는 경로', () {
      const screen = Size(841, 674);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('태블릿 세로(768×1024, 비율 1.33)', () {
      const screen = Size(768, 1024);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test(
      '실측 커버(411.4×960)와 같은 폭이지만 비율이 정상인 폰(411.4×915, 비율 2.22)은 '
      '보정이 걸리지 않는다 — 폭이 아니라 비율이 원인임을 가르는 핵심 테스트',
      () {
        const screen = Size(411.4, 915);
        final result = guideFrameSizeFor(screen);
        final legacy = _legacyGuideFrameSizeFor(screen);
        expect(screen.height / screen.width, closeTo(2.2237, 0.001));
        expect(
          screen.height / screen.width,
          lessThan(kNarrowAspectThreshold),
        );
        expect(result.width, closeTo(legacy.width, 0.001));
        expect(result.height, closeTo(legacy.height, 0.001));
      },
    );
  });

  group('guideFrameSizeFor — 세로세로비가 큰 화면(커버 디스플레이)에서는 더 크게 그린다', () {
    test(
      '⭐ 실측 — 갤럭시 폴드(SM-F966N) 접은 커버 화면 411.4×960dp '
      '(adb dumpsys display, 물리 1080×2520px / density 420, 2026-08-21). '
      '비율 2.33로 일반 폰(2.0~2.22)보다 뚜렷이 크다.',
      () {
        const screen = Size(411.4, 960);
        final result = guideFrameSizeFor(screen);
        final legacy = _legacyGuideFrameSizeFor(screen);

        // 같은 폭(411dp대)의 일반 폰 테스트와 달리 여기서는 비율이
        // 문턱값을 넘어 보정이 걸려야 한다.
        expect(screen.height / screen.width, closeTo(2.3335, 0.001));
        expect(
          screen.height / screen.width,
          greaterThanOrEqualTo(kNarrowAspectThreshold),
        );

        // 1차 수정(폭 340dp 미만 게이트)은 이 폭(411.4dp)에서 전혀
        // 발동하지 않았다 — 그게 이번 재작업의 이유다. 새 계산은
        // 발동해야 한다.
        expect(result.width, greaterThan(legacy.width));
        expect(result.height, greaterThan(legacy.height));

        // 짧은 변은 화면 폭의 안전 상한(65%)까지 정확히 커진다.
        expect(
          result.width,
          moreOrLessEquals(
            screen.width * kNarrowAspectMaxShortEdgeRatio,
            epsilon: 0.001,
          ),
        );
        // 긴 변도 비례해서 커지지만, 높이 상한(72%)에는 한참 못 미친다
        // (약 50%) — 위아래 여백이 부족해지지 않는다는 뜻.
        expect(result.height, lessThan(screen.height * 0.72));
      },
    );

    test('더 좁은 커버 화면 추정 비율(320×760, 비율 2.375)에서도 같은 방향으로 커진다', () {
      const screen = Size(320, 760);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);

      expect(result.width, greaterThan(legacy.width));
      expect(result.height, greaterThan(legacy.height));
      expect(
        result.width,
        moreOrLessEquals(
          screen.width * kNarrowAspectMaxShortEdgeRatio,
          epsilon: 0.001,
        ),
      );
    });

    test('문턱값 바로 아래 비율(width 400, height 899 → 비율 2.2475)에서는 보정이 안 걸린다', () {
      const screen = Size(400, 899);
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(screen.height / screen.width, lessThan(kNarrowAspectThreshold));
      expect(result.width, closeTo(legacy.width, 0.001));
      expect(result.height, closeTo(legacy.height, 0.001));
    });

    test('문턱값 정확히(width 400, height 900 → 비율 2.25)에서는 보정이 걸린다(경계값)', () {
      const screen = Size(400, 900);
      expect(screen.height / screen.width, closeTo(kNarrowAspectThreshold, 0.0001));
      final result = guideFrameSizeFor(screen);
      final legacy = _legacyGuideFrameSizeFor(screen);
      expect(result.width, greaterThanOrEqualTo(legacy.width));
    });

    test('세로세로비가 커도 짧은 변이 화면 폭의 65%를 넘지 않는다(초점 거리 회귀 방지 상한)', () {
      // 극단적으로 세로세로비가 큰 화면을 가정해도 안전 상한을 넘지 않아야
      // 한다 — 2026-08-06에 가이드를 과하게 키웠다가 초점이 안 맞는 회귀를
      // 낸 적이 있다.
      const screen = Size(300, 2000); // 비율 6.67, 극단값
      final result = guideFrameSizeFor(screen);
      expect(result.width, lessThanOrEqualTo(screen.width * 0.65 + 0.001));
    });

    test('좁고 세로세로비가 커도 세로 공간이 부족하면 높이 상한(0.72)을 넘지 않는다', () {
      // 보정된 긴 변이 높이 상한을 넘어서면 다시 상한으로 잘려야 한다.
      const screen = Size(320, 300); // 비율 0.94 — 사실 이 케이스는 가로에
      // 가깝지만, 좁은 화면 + 낮은 높이 조합에서 clamp가 실제로 동작하는지
      // 확인하는 안전장치 테스트다.
      final result = guideFrameSizeFor(screen);
      expect(result.height, lessThanOrEqualTo(screen.height * 0.72 + 0.001));
    });

    test('카드 가로세로비(184/330)는 보정 후에도 유지된다', () {
      const screen = Size(411.4, 960);
      final result = guideFrameSizeFor(screen);
      expect(result.width / result.height, closeTo(184 / 330, 0.0001));
    });
  });
}
