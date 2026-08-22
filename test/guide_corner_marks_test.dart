import 'dart:ui';

import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/guide_corner_marks.dart';
import 'package:flutter_test/flutter_test.dart';

/// 추가 383이 실기기로 확인한 가이드 크기. **이 값들은 안 바뀐다** — 387은
/// 생김새만 바꾸고 크기는 그대로 둔다.
const iphone16Pro = Size(201, 360); // 짧은 변 50% = 201dp
const foldCover = Size(267, 479); // 짧은 변 65% = 267dp

void main() {
  group('guideCornerArmLength', () {
    test('짧은 변에 비례한다', () {
      final small = guideCornerArmLength(const Size(120, 215));
      final large = guideCornerArmLength(const Size(200, 358));
      expect(large, greaterThan(small));
    });

    test('실기기 값에서 상·하한 사이에 든다', () {
      for (final size in [iphone16Pro, foldCover]) {
        final arm = guideCornerArmLength(size);
        expect(arm, greaterThanOrEqualTo(kGuideCornerArmMin));
        expect(arm, lessThanOrEqualTo(kGuideCornerArmMax));
      }
    });

    test('⚠️ 팔이 짧은 변의 절반을 넘지 않는다 — 넘으면 네 변이 이어져 보인다', () {
      // 이어져 보이면 다시 "채우세요"가 되어 387의 목적이 사라진다.
      for (final size in [
        iphone16Pro,
        foldCover,
        const Size(120, 215),
        const Size(400, 716),
      ]) {
        final arm = guideCornerArmLength(size);
        expect(arm * 2, lessThan(size.width), reason: '가로: $size');
        expect(arm * 2, lessThan(size.height), reason: '세로: $size');
      }
    });

    test('아주 작은 가이드에서도 하한을 지킨다 — 점으로 보이면 틀로 안 읽힌다', () {
      expect(guideCornerArmLength(const Size(40, 72)), kGuideCornerArmMin);
    });

    test('아주 큰 가이드에서도 상한을 지킨다', () {
      expect(guideCornerArmLength(const Size(1000, 1790)), kGuideCornerArmMax);
    });

    test('크기가 0이면 0 — 그릴 것이 없다', () {
      expect(guideCornerArmLength(Size.zero), 0);
      expect(guideCornerArmLength(const Size(0, 100)), 0);
    });

    test('세로가 짧아도 짧은 변을 기준으로 삼는다', () {
      // 가로로 누운 가이드(폴드 펼침 등)에서도 같은 규칙이어야 한다.
      final tall = guideCornerArmLength(const Size(200, 100));
      final wide = guideCornerArmLength(const Size(100, 200));
      expect(tall, wide);
    });
  });

  group('GuideCornerMarksPainter', () {
    test('색·굵기·반지름이 바뀌면 다시 그린다', () {
      const base = GuideCornerMarksPainter(
        color: Color(0xFFFFFFFF),
        strokeWidth: 2.5,
        radius: 16,
      );
      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(
          const GuideCornerMarksPainter(
            color: Color(0xFF000000),
            strokeWidth: 2.5,
            radius: 16,
          ),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const GuideCornerMarksPainter(
            color: Color(0xFFFFFFFF),
            strokeWidth: 1,
            radius: 16,
          ),
        ),
        isTrue,
      );
    });
  });
}
