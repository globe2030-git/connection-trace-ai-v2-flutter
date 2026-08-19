// 퀵 매핑처럼 **코드로 넣는 값**도 하이픈 형식으로 정리되는지 고정한다.
//
// ⚠️ KoreanPhoneNumberFormatter는 TextInputFormatter라 **사람이 타이핑할 때만**
// 걸린다. 퀵 매핑은 값을 코드로 넣으므로 포맷터를 안 거치고, OCR이 읽은 그대로
// (`02 6360 6910`) 저장될 수 있다. 2026-08-19(추가 324)에 퀵 매핑에 사무실·팩스를
// 더하면서 이 구멍이 넓어져, 같은 포맷터를 코드에서도 불러 쓰기로 했다.
//
// 이 파일은 **포맷터가 그 일을 할 수 있는지**를 고정한다 — 화면 코드가 이것을
// 부르는지는 위젯 쪽 몫이다.
import 'package:connection_trace_ai_flutter/core/utils/korean_phone_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

String format(String raw) => KoreanPhoneNumberFormatter()
    .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: raw))
    .text;

void main() {
  group('코드로 넣는 전화번호도 하이픈으로 통일된다', () {
    test('⭐ 공백으로 읽힌 원문 — OCR이 흔히 이렇게 준다', () {
      expect(format('010 1234 5678'), '010-1234-5678');
      expect(format('02 6360 6910'), '02-6360-6910');
    });

    test('⭐ 붙여 읽힌 것도 나뉜다', () {
      expect(format('01012345678'), '010-1234-5678');
    });

    test('점·괄호로 구분된 것도 하이픈으로', () {
      expect(format('031.709.7071'), '031-709-7071');
      expect(format('(031) 709-7071'), '031-709-7071');
    });

    test('서울(02)은 지역번호를 두 자리로 끊는다', () {
      expect(format('0263606910'), '02-6360-6910');
    });

    test('이미 하이픈이면 그대로다', () {
      expect(format('010-1234-5678'), '010-1234-5678');
    });
  });
}
