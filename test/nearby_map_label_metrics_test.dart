import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_label_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

/// 묶음 마커 라벨 폭 계산(추가 452)을 고정한다.
///
/// 이 값은 `nearby_map_label_collision.dart`의 충돌 판정에 그대로 들어가므로,
/// 실제 `_GroupPin` 위젯이 그리는 폭과 어긋나면 충돌 판정이 화면과 맞지
/// 않는다 — 짧은 글자는 짧게, `kGroupLabelMaxWidth`를 넘는 글자는 그 값으로
/// 잘리는지를 확인한다.
void main() {
  test('짧은 글자는 최대 폭보다 좁게 잰다', () {
    final width = measureGroupLabelWidth('가');

    expect(width, greaterThan(kGroupLabelHorizontalPadding));
    expect(width, lessThan(kGroupLabelMaxWidth));
  });

  test('⭐ 아주 긴 글자는 최대 폭(kGroupLabelMaxWidth)에서 잘린다', () {
    final width = measureGroupLabelWidth('아주아주아주아주아주아주아주아주아주아주긴회사이름주식회사');

    expect(width, kGroupLabelMaxWidth);
  });

  test('글자가 길수록 폭도 넓다(최대 폭 안에서는)', () {
    final short = measureGroupLabelWidth('가');
    final long = measureGroupLabelWidth('가나다라마');

    expect(long, greaterThan(short));
  });
}
