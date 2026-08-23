// 형태 코드가 다르면 **화면 설명도 달라야 한다**(추가 408).
//
// ## 무엇이 문제였나
//
// 2026-08-22 실기기 진단에서 "도로명·보통"이 **두 줄로 갈라져** 떴다(52장과
// 1장). 집계는 형태 코드별로 맞았는데 **푸는 쪽이 두 코드를 같은 말로**
// 만들어, 화면에서는 같은 항목이 두 번 있는 것처럼 보였다.
//
// 원인은 `describeFailureShape`가 **`jibun`을 `road=1`일 때 안 보여 주는**
// 것이었다. 그래서 `road=1;jibun=0`과 `road=1;jibun=1`이 똑같이 "도로명"이
// 됐다. 그런데 이 둘은 **다른 주소**다 — 뒤엣것은 도로명과 지번이 한 주소에
// 같이 든 것이고, 지오코더가 못 푸는 이유도 다를 수 있다.
//
// ⚠️ **집계를 합치지 않고 설명을 갈랐다.** 합치면 화면은 깔끔해지지만 둘을
// 가르던 정보가 사라진다. 이 화면의 목적이 "왜 실패하는가"를 형태로 좁히는
// 것이므로, 구별되는 것은 구별해서 보여 준다.
//
// ## 이 테스트가 지키는 것
//
// 라벨을 손볼 때 **또 겹치는 것**을 막는다. 사람 눈으로는 안 보인다 —
// 겹치는 순간이 아니라 그 코드가 실제로 쌓인 뒤에야 화면에 드러나기 때문에,
// 위 결함도 실기기 표본 98장을 모으고 나서야 보였다.
import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제로 만들어질 수 있는 형태 코드만 모은다.
///
/// `_addressShape`는 도로명·지번을 **숫자가 뒤따를 때만** 1로 잡으므로
/// `road=1`이나 `jibun=1`이면 `digit`은 반드시 1이다. 있을 수 없는 조합까지
/// 넣고 검사하면 **없는 결함을 잡았다고 착각**하게 된다.
List<String> reachableShapes() {
  final out = <String>[];
  for (final road in [0, 1]) {
    for (final jibun in [0, 1]) {
      for (final digit in [0, 1]) {
        if ((road == 1 || jibun == 1) && digit == 0) continue;
        for (final bldg in [0, 1]) {
          for (final len in ['S', 'M', 'L']) {
            out.add('road=$road;jibun=$jibun;digit=$digit;bldg=$bldg;len=$len');
          }
        }
      }
    }
  }
  return out;
}

void main() {
  group('형태 코드 ↔ 화면 설명', () {
    test('⭐ 서로 다른 코드가 같은 설명으로 풀리지 않는다', () {
      final byLabel = <String, List<String>>{};
      for (final shape in reachableShapes()) {
        byLabel
            .putIfAbsent(GeoBackfillService.describeFailureShape(shape), () => [])
            .add(shape);
      }
      final collisions = byLabel.entries.where((e) => e.value.length > 1);
      expect(
        collisions.map((e) => '${e.key} ← ${e.value.join(", ")}').toList(),
        isEmpty,
        reason: '같은 말로 풀리는 코드가 있으면 진단 화면에 같은 줄이 여러 번 뜬다',
      );
    });

    test('실제로 겹쳤던 두 코드가 갈린다 — 도로명만 vs 도로명+지번', () {
      final onlyRoad = GeoBackfillService.describeFailureShape(
        'road=1;jibun=0;digit=1;bldg=0;len=M',
      );
      final mixed = GeoBackfillService.describeFailureShape(
        'road=1;jibun=1;digit=1;bldg=0;len=M',
      );
      expect(onlyRoad, isNot(mixed));
      // 섞인 쪽도 여전히 "도로명"으로 읽혀야 한다 — 화면에서 도로명 무리와
      // 나란히 놓고 볼 수 있어야 87% 같은 비율을 셀 수 있다.
      expect(mixed, contains('도로명'));
      expect(mixed, contains('지번'));
    });
  });
}
