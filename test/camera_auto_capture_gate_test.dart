// "빈 공간인데 자동으로 찍힌다"(테스터 E-01)를 막는 판정의 회귀 방지.
//
// 예전 자동 촬영 조건은 **"화면이 흔들리지 않으면"** 하나뿐이라 명함이 있는지는
// 보지 않았다. 빈 벽을 향해 가만히 들고 있으면 오히려 가장 안정적이라 찍혔다.
//
// ⚠️ 이 계산이 틀리면 **자동 촬영이 통째로 멈춘다** — 빈 장면을 막으려다 진짜
// 명함까지 막는 쪽이 더 나쁜 고장이다. 실제로 임계값을 추측으로 10.0에 잡았다가
// 진짜 명함이 안 찍히는 회귀를 냈다(2026-08-14).
//
// ⚠️ **이 테스트는 임계값이 맞는지는 검증하지 못한다.** 여기 쓰는 합성 장면은
// 실제 카메라 샘플링 밀도(24x24 격자가 명함 글자를 거의 안 밟는다)를 재현하지
// 못하기 때문이다. 검증하는 것은 **장면 종류 사이의 크기 관계**뿐이다 —
// 민무늬 < 명함, 모서리는 대비가 커도 지배 톤이 낮다. 임계값 자체는 실기기에서
// 읽은 값으로 정한다(디버그 빌드 화면에 표시된다).
import 'package:connection_trace_ai_flutter/core/utils/frame_contrast.dart';
import 'package:flutter_test/flutter_test.dart';

/// 24x24 격자 샘플을 만든다(`_sampleGridSize`와 같은 크기).
List<int> grid(int Function(int x, int y) value) => [
  for (var y = 0; y < 24; y++)
    for (var x = 0; x < 24; x++) value(x, y),
];

void main() {
  test('민무늬 장면은 대비가 거의 0 — 빈 벽·책상', () {
    expect(
      centerFrameContrast(gridSize: 24, grid((_, _) => 200)),
      lessThan(1),
    );
  });

  test('센서 잡음 정도는 "볼 것이 있다"로 보지 않는다', () {
    // 카메라 센서 노이즈 정도로는 "볼 것이 있다"고 보면 안 된다.
    final noisy = grid((x, y) => 200 + ((x + y) % 3));
    expect(centerFrameContrast(gridSize: 24, noisy), lessThan(10));
  });

  test('글자가 있는 명함처럼 명암이 섞이면 대비가 크다', () {
    // 흰 바탕에 검은 글자 → 밝고 어두운 픽셀이 섞인다.
    final card = grid((x, y) => (x ~/ 2 + y ~/ 2) % 2 == 0 ? 240 : 30);
    expect(
      centerFrameContrast(gridSize: 24, card),
      greaterThan(10),
    );
  });

  test('가장자리만 복잡하고 가운데가 비면 걸러진다 — 가운데만 본다', () {
    // 가이드 프레임은 화면 중앙이다. 배경이 어수선해도 명함이 안 들어왔으면
    // 찍으면 안 된다.
    final edgesOnly = grid((x, y) {
      final inCenter = x >= 6 && x < 18 && y >= 6 && y < 18;
      return inCenter ? 200 : (x % 2 == 0 ? 255 : 0);
    });
    expect(
      centerFrameContrast(gridSize: 24, edgesOnly),
      lessThan(10),
    );
  });

  // 사용자 제보(2026-08-14): "빈공간을 찍지는 않는데 각이진 빈곳은 자동 촬영되".
  // 대비만으로는 모서리를 못 거른다 — 밝은 면과 어두운 면이 반반이라 대비가
  // **오히려 크다.** 그래서 "한쪽 톤이 지배적인가"를 함께 본다.
  group('각이 진 빈 곳을 명함과 가른다', () {
    test('화면을 반으로 가르는 모서리 — 대비는 크지만 지배 톤이 없다', () {
      final edge = grid((x, y) => x < 12 ? 30 : 230);
      expect(
        centerFrameContrast(edge, gridSize: 24),
        greaterThan(10),
        reason: '모서리는 대비가 커서 대비 검사만으로는 통과한다',
      );
      expect(
        centerDominantToneRatio(edge, gridSize: 24),
        lessThan(0.65),
        reason: '반반이라 지배 톤 검사에서 걸러져야 한다',
      );
    });

    test('밝은 명함 — 바탕이 지배적이고 글자는 소수', () {
      final card = grid((x, y) => (x % 5 == 0 && y % 4 == 0) ? 20 : 235);
      expect(centerFrameContrast(card, gridSize: 24), greaterThan(10));
      expect(
        centerDominantToneRatio(card, gridSize: 24),
        greaterThanOrEqualTo(0.65),
      );
    });

    test('어두운 명함도 받는다 — 더 많은 쪽을 본다', () {
      final darkCard = grid((x, y) => (x % 5 == 0 && y % 4 == 0) ? 235 : 25);
      expect(centerFrameContrast(darkCard, gridSize: 24), greaterThan(10));
      expect(
        centerDominantToneRatio(darkCard, gridSize: 24),
        greaterThanOrEqualTo(0.65),
      );
    });
  });
}
