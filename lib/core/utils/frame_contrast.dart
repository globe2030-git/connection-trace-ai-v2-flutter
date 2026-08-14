import 'dart:math' as math;

/// 카메라 프레임 격자 샘플의 **가운데 절반**에서 밝기 표준편차를 낸다.
///
/// 자동 촬영을 "흔들리지 않는가"로만 판단하면 **빈 벽이나 책상도 찍힌다** —
/// 오히려 아무것도 없는 장면이 가장 안정적이라 더 잘 찍혔다(테스터 E-01
/// "촬영 버튼을 누르지 않았는데 빈 공간이 촬영됨"). 그래서 "볼 것이 있는가"를
/// 함께 본다.
///
/// 가이드 프레임이 화면 중앙에 있으므로 **가운데 절반**만 본다. 글자가 있는
/// 명함은 밝고 어두운 픽셀이 섞여 표준편차가 크고, 민무늬 면은 거의 평평하다.
///
/// ⚠️ 문서 경계를 실제로 검출하는 것은 아니다(그건 더 큰 작업이다). 여기서
/// 거르려는 것은 **아무것도 없는 장면**이지 "명함이 반듯한가"가 아니다.
double centerFrameContrast(List<int> sample, {required int gridSize}) {
  final lo = gridSize ~/ 4;
  final hi = gridSize - lo;
  var sum = 0.0;
  var count = 0;
  for (var y = lo; y < hi; y++) {
    for (var x = lo; x < hi; x++) {
      final i = y * gridSize + x;
      if (i >= sample.length) continue;
      sum += sample[i];
      count++;
    }
  }
  if (count == 0) return 0;
  final mean = sum / count;
  var squared = 0.0;
  for (var y = lo; y < hi; y++) {
    for (var x = lo; x < hi; x++) {
      final i = y * gridSize + x;
      if (i >= sample.length) continue;
      final d = sample[i] - mean;
      squared += d * d;
    }
  }
  return math.sqrt(squared / count);
}

/// 가운데 절반에서 **한쪽 톤이 차지하는 비율**(0.5~1.0).
///
/// 대비만으로는 **각이 진 빈 곳**을 못 거른다 — 책상이나 벽 모서리는 밝은 면과
/// 어두운 면이 반반이라 대비가 오히려 크다(사용자 제보 "빈공간을 찍지는 않는데
/// 각이진 빈곳은 자동 촬영되").
///
/// 명함은 **바탕이 지배적**이고 글자가 소수다. 밝은 명함이든 어두운 명함이든
/// 한쪽 톤이 대부분을 차지한다. 반면 모서리 장면은 대략 반반이라 0.5 근처다.
/// 그래서 밝은 쪽·어두운 쪽 중 **더 많은 쪽**의 비율을 돌려준다.
double centerDominantToneRatio(List<int> sample, {required int gridSize}) {
  final lo = gridSize ~/ 4;
  final hi = gridSize - lo;
  final values = <int>[];
  for (var y = lo; y < hi; y++) {
    for (var x = lo; x < hi; x++) {
      final i = y * gridSize + x;
      if (i < sample.length) values.add(sample[i]);
    }
  }
  if (values.isEmpty) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final bright = values.where((v) => v > mean).length;
  final ratio = bright / values.length;
  return math.max(ratio, 1 - ratio);
}
