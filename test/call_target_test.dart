/// `call_target.dart` 판정 테스트.
///
/// ⚠️ 이 테스트는 **2026-08-26 이전 동작을 그대로 박는 것**이다. 규칙을
/// 바꾸려고 쓴 것이 아니라, 화면 안에 묻혀 있던 규칙을 꺼내면서 그 자리에
/// 고정해 두려고 쓴 것이다.
///
/// 🚨 특히 "사무실 번호만 있는 인맥"은 **한 번 못 걸었던 자리**다(2026-08-10
/// 수정). 그 뒤로 이 규칙을 지키는지 확인하는 장치가 없었다.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/call_target.dart';

void main() {
  group('걸 번호가 없으면 아무것도 하지 않는다', () {
    test('둘 다 비었을 때', () {
      expect(resolveCallTarget(mobile: '', officePhone: ''), CallTarget.none);
    });

    test('둘 다 null일 때', () {
      expect(resolveCallTarget(), CallTarget.none);
    });

    // 빈 번호로 tel:을 여는 것이 2026-08-10 사고의 증상이었다.
    test('공백만 든 값은 없는 것으로 친다', () {
      expect(
        resolveCallTarget(mobile: '   ', officePhone: '\t'),
        CallTarget.none,
      );
    });
  });

  group('번호가 하나뿐이면 고르게 하지 않고 바로 건다', () {
    test('휴대폰만 있을 때', () {
      final t = resolveCallTarget(mobile: '010-1234-5678', officePhone: '');
      expect(t.kind, CallTargetKind.single);
      expect(t.number, '010-1234-5678');
    });

    // 🚨 회귀 방지 — 예전에는 휴대폰이 반드시 있다고 보고 사무실 번호만 있는
    // 인맥에게 빈 번호로 tel:을 열었다. 아무 일도 일어나지 않았다.
    test('사무실 전화만 있을 때도 똑같이 바로 건다(2026-08-10 회귀 방지)', () {
      final t = resolveCallTarget(mobile: '', officePhone: '02-123-4567');
      expect(t.kind, CallTargetKind.single);
      expect(t.number, '02-123-4567');
    });

    test('사무실 전화만 있고 휴대폰이 null이어도 마찬가지', () {
      final t = resolveCallTarget(officePhone: '02-123-4567');
      expect(t.kind, CallTargetKind.single);
      expect(t.number, '02-123-4567');
    });

    test('앞뒤 공백은 떼고 넘긴다', () {
      expect(resolveCallTarget(mobile: ' 010-1234-5678 ').number,
          '010-1234-5678');
      expect(resolveCallTarget(officePhone: ' 02-123-4567 ').number,
          '02-123-4567');
    });
  });

  group('둘 다 있으면 고르게 한다', () {
    test('시트를 띄운다', () {
      expect(
        resolveCallTarget(mobile: '010-1234-5678', officePhone: '02-123-4567'),
        CallTarget.choose,
      );
      // 고르게 하는 경우에는 번호를 미리 정하지 않는다
      expect(
        resolveCallTarget(
          mobile: '010-1234-5678',
          officePhone: '02-123-4567',
        ).number,
        isNull,
      );
    });

    test('한쪽이 공백뿐이면 둘 다 있는 것이 아니다', () {
      final t = resolveCallTarget(mobile: '010-1234-5678', officePhone: '  ');
      expect(t.kind, CallTargetKind.single);
      expect(t.number, '010-1234-5678');
    });
  });

  // 판정은 형식을 보지 않는다 — 형식 검사는 폼(card_form_validation)이 하고,
  // 여기서는 "있는가"만 본다. 저장된 값이 형식에 안 맞아도 걸어는 봐야 한다.
  test('형식이 이상해도 있으면 있는 것으로 친다', () {
    final t = resolveCallTarget(mobile: '01012345678');
    expect(t.kind, CallTargetKind.single);
    expect(t.number, '01012345678');
  });
}
