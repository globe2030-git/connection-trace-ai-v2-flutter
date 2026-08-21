import 'dart:math';
import 'dart:typed_data';

import 'package:connection_trace_ai_flutter/core/utils/card_rect_opencv.dart';
import 'package:flutter_test/flutter_test.dart';

/// 무늬 있는 배경 위의 밝은 명함. 2026-08-22 실측에서 검출이 통째로 실패한
/// 상황을 합성으로 재현한 것이다 — 배경 무늬가 캐니 경계선을 잘게 끊으면
/// 명함 외곽선이 닫힌 고리를 못 이뤄 네 점 후보가 하나도 안 나왔다.
Uint8List texturedScene({
  required int width,
  required int height,
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final rand = Random(20260822);
  final buffer = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inCard = x >= left && x < right && y >= top && y < bottom;
      // 배경은 어둡고 거칠게(실측 배경의 표준편차가 38이었다), 명함은 밝고
      // 매끈하게. 밝기 차는 실측값(58~73)과 같은 자리에 둔다.
      final base = inCard ? 185 : 112;
      final noise = inCard ? rand.nextInt(11) - 5 : rand.nextInt(121) - 60;
      buffer[y * width + x] = (base + noise).clamp(0, 255);
    }
  }
  return buffer;
}

void main() {
  group('edgeTouchingSides', () {
    test('화면 한가운데 사각형은 어느 변에도 닿지 않는다', () {
      final sides = edgeTouchingSides(
        const [(x: 200.0, y: 150.0), (x: 800.0, y: 150.0),
               (x: 800.0, y: 600.0), (x: 200.0, y: 600.0)],
        width: 1000,
        height: 750,
      );
      expect(sides, 0);
    });

    test('화면 전체를 덮는 사각형은 네 변에 닿는다 — 닫기가 만드는 가짜 후보', () {
      final sides = edgeTouchingSides(
        const [(x: 2.0, y: 4.0), (x: 997.0, y: 3.0),
               (x: 997.0, y: 747.0), (x: 3.0, y: 746.0)],
        width: 1000,
        height: 750,
      );
      expect(sides, 4);
      expect(sides, greaterThanOrEqualTo(kMaxEdgeTouchingSides));
    });

    test('세 변만 닿아도 버린다 — 실측에서 이 모양이 명함 비율을 통과했다', () {
      final sides = edgeTouchingSides(
        const [(x: 2.0, y: 12.0), (x: 996.0, y: 137.0),
               (x: 997.0, y: 738.0), (x: 2.0, y: 747.0)],
        width: 1000,
        height: 750,
      );
      expect(sides, greaterThanOrEqualTo(kMaxEdgeTouchingSides));
    });

    test('꼭짓점이 없으면 0', () {
      expect(edgeTouchingSides(const [], width: 100, height: 100), 0);
    });
  });

  group('무늬 있는 배경', () {
    test('끊긴 경계선을 이어 명함을 찾아낸다', () {
      const w = 1000, h = 750;
      final luma = texturedScene(
        width: w, height: h, left: 165, top: 156, right: 866, bottom: 520,
      );

      final result = detectCardQuadsWithOpenCv(luma, width: w, height: h);

      expect(result.imageOk, isTrue);
      // 닫기 연산이 없으면 여기가 0이었다(실측 8장 전부).
      expect(result.observations, greaterThan(0));

      // 찾은 것이 화면 테두리가 아니라 실제 명함 자리여야 한다.
      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i < 8; i += 2) {
        xs.add(result.quads[i] * w);
        ys.add(result.quads[i + 1] * h);
      }
      expect(xs.reduce(min), closeTo(165, 40));
      expect(xs.reduce(max), closeTo(866, 40));
      expect(ys.reduce(min), closeTo(156, 40));
      expect(ys.reduce(max), closeTo(520, 40));
    });
  });
}
