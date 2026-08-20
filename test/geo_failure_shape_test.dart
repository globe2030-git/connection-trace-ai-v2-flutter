// 좌표 변환 실패 **형태 코드**를 사람이 읽을 말로 푸는 것(추가 342).
//
// ## 왜 이 테스트가 필요한가
//
// 집계는 예전부터 쌓이고 있었는데 **보여 주는 화면이 없었다.** 화면을 만들면서
// 가장 쉽게 저지를 실수가 **코드를 그대로 띄우는 것**이다 —
// `road=1;jibun=0;digit=1;bldg=1;len=M`을 화면에 올려도 아무도 못 읽는다.
//
// ⚠️ **만드는 쪽과 푸는 쪽이 어긋나면 조용히 틀린다.** 코드 모양이 바뀌었는데
// 푸는 쪽만 그대로면 화면에 엉뚱한 말이 뜨고, 그걸 근거로 판단하게 된다.
// 그래서 **실제 형태 코드 모양**으로 검사한다.
import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('형태 코드 풀기', () {
    test('도로명 + 번호 + 건물명', () {
      final s = GeoBackfillService.describeFailureShape(
        'road=1;jibun=0;digit=1;bldg=1;len=M',
      );
      expect(s, contains('도로명'));
      expect(s, contains('건물명'));
      expect(s, isNot(contains('번호 없음')));
      expect(s, contains('보통'));
    });

    test('지번', () {
      final s = GeoBackfillService.describeFailureShape(
        'road=0;jibun=1;digit=1;bldg=0;len=S',
      );
      expect(s, contains('지번'));
      expect(s, contains('짧음'));
    });

    test('둘 다 아니고 번호도 없다 — 가장 나쁜 모양', () {
      final s = GeoBackfillService.describeFailureShape(
        'road=0;jibun=0;digit=0;bldg=0;len=L',
      );
      expect(s, contains('둘 다 아님'));
      expect(s, contains('번호 없음'));
      expect(s, contains('긺'));
    });

    group('⚠️ 코드가 그대로 새어 나오지 않는다', () {
      test('푼 결과에 `=` 나 `;` 가 없다', () {
        final s = GeoBackfillService.describeFailureShape(
          'road=1;jibun=0;digit=1;bldg=1;len=M',
        );
        expect(s, isNot(contains('=')));
        expect(s, isNot(contains(';')));
        expect(s, isNot(contains('road')));
      });

      test('알 수 없는 코드는 **그대로** 돌려준다 — 지어내지 않는다', () {
        // 형태 코드가 바뀌었는데 푸는 쪽이 안 따라온 경우다. 억지로 해석해
        // 그럴듯한 말을 만들면 **틀린 근거로 판단하게 된다.**
        expect(GeoBackfillService.describeFailureShape('무엇인가'), '무엇인가');
        expect(GeoBackfillService.describeFailureShape(''), '');
      });
    });
  });
}
