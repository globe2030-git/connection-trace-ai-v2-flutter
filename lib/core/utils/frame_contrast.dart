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
