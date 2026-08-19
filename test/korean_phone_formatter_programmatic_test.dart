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

  // ── 전화 모양이 아니면 손대지 않는다 (2026-08-19 실기기 제보, 추가 327) ──
  //
  // 포맷터만 부르면 뭐가 들어오든 전화번호로 만든다. 화면 코드는 그 앞에
  // "전화번호 모양인가"를 먼저 본다. 아래는 그 판정 규칙을 고정한다.
  bool looksLikePhone(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.startsWith('0') && d.length >= 9 && d.length <= 11;
  }

  group('전화 모양일 때만 정리한다 (추가 327)', () {
    test('⭐ 앞 0이 빠진 번호는 손대지 않는다 — 정리하면 자리가 밀린다', () {
      // 31-709-7071 → 숫자 9개, 0으로 시작 안 함 → 그대로 둔다.
      // 예전에는 317-09-7071 이 되어 원본보다 나빠졌다.
      expect(looksLikePhone('31-709-7071'), isFalse);
      expect(format('31-709-7071'), '317-09-7071'); // 포맷터 자체는 이렇게 만든다
    });

    test('⭐ 주소는 손대지 않는다', () {
      expect(looksLikePhone('07795 서울특별시 중구 을지로 12'), isFalse);
    });

    test('⭐ 이메일도 손대지 않는다', () {
      expect(looksLikePhone('E. andy.park@tg360tech.com'), isFalse);
    });

    test('진짜 전화번호는 정리한다', () {
      expect(looksLikePhone('010 1234 5678'), isTrue);
      expect(looksLikePhone('02-6360-6910'), isTrue);
      expect(looksLikePhone('031.709.7071'), isTrue);
      expect(looksLikePhone('M 010-9354-5742'), isTrue);
    });

    test('너무 짧거나 긴 것은 손대지 않는다', () {
      expect(looksLikePhone('010'), isFalse);
      expect(looksLikePhone('0101234567890123'), isFalse);
    });
  });
}
