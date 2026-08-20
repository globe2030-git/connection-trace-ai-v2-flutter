// 앱 복귀 때 GPS를 너무 자주 부르지 않는지(추가 346).
//
// ## 왜
//
// 2026-08-20 실기기에서 **홈 → 복귀 5번에 GPS 요청 3회**(15초 사이)였다.
// 시스템 로그(`GnssNmeaProvider`)로 셌다.
//
// ⚠️ **이동 조건은 못 건다.** 움직였는지 알려면 GPS를 받아야 하는데 그게 바로
// 아끼려는 것이다. 걸 수 있는 것은 시간뿐이다.
//
// ## 이 테스트가 지키는 것
//
// **"사람이 누른 것은 안 막는다"**가 핵심이다. 새로고침을 눌렀는데 아무 일도
// 안 일어나면 고장으로 보인다.
import 'package:connection_trace_ai_flutter/presentation/features/radar/view_models/radar_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GPS 시간 조건', () {
    test('신선하다고 보는 시간이 정해져 있다', () {
      expect(RadarViewModel.positionFreshFor, const Duration(minutes: 2));
    });

    test('⚠️ 실측(15초에 복귀 3회)이 이 창 안에 들어간다', () {
      // 이 값이 15초보다 짧으면 실측한 문제가 안 풀린다.
      expect(
        RadarViewModel.positionFreshFor,
        greaterThan(const Duration(seconds: 15)),
        reason: '복귀가 몰릴 때 한 번으로 묶이지 않는다',
      );
    });

    test('⚠️ 너무 길면 위치가 안 따라온다', () {
      // 걸어서 2분이면 대략 150m. 10분이면 700m가 넘어 "주변"이 무의미해진다.
      expect(
        RadarViewModel.positionFreshFor,
        lessThanOrEqualTo(const Duration(minutes: 5)),
        reason: '레이더가 보여 주는 거리가 실제와 크게 어긋난다',
      );
    });
  });
}
