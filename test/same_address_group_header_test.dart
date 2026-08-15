import 'package:connection_trace_ai_flutter/presentation/common/same_address_group_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 같은 주소 묶음 머리글(F-15)이 **실제로 무엇을 그리는지** 고정한다.
///
/// 묶는 규칙은 `address_grouping_test.dart`가 본다. 여기서 보는 것은 그 결과가
/// 화면에 어떻게 나타나는가다 — 실기기 확인에는 **같은 주소를 가진 명함이 두 장
/// 있어야** 하는데, 확인 시점의 실제 데이터에는 그런 짝이 없었다(2026-08-15).
/// 사용자 데이터를 만들어 넣지 않고 이 부분을 덮기 위해 위젯 테스트로 남긴다.
void main() {
  Future<void> pump(WidgetTester tester, {required String address, required int count}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SameAddressGroupHeader(address: address, count: count),
        ),
      ),
    );
  }

  testWidgets('⭐ 주소와 인원수를 함께 보여 준다', (tester) async {
    await pump(tester, address: '서울특별시 강남구 테헤란로 123', count: 3);

    expect(find.text('서울특별시 강남구 테헤란로 123'), findsOneWidget);
    expect(
      find.text('3명'),
      findsOneWidget,
      reason: '사용자가 알고 싶은 것은 "이 건물에 몇 명"이다',
    );
  });

  testWidgets('긴 주소는 한 줄로 자른다', (tester) async {
    await pump(
      tester,
      address: '서울특별시 영등포구 양평로21가길 19 선유도 우림라이온스밸리 B동 1234호',
      count: 2,
    );

    final text = tester.widget<Text>(find.textContaining('양평로21가길'));
    expect(text.maxLines, 1);
    expect(
      text.overflow,
      TextOverflow.ellipsis,
      reason: '두 줄로 넘어가면 목록의 리듬이 깨진다',
    );
  });

  testWidgets('⭐ 스크린리더에 머리글로 읽힌다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, address: '테헤란로 123', count: 2);

    // 매처(`matchesSemantics`/`containsSemantics`)는 지정하지 않은 플래그까지
    // 함께 검사하거나 폐기 예정이라, 여기서 지키려는 둘만 직접 본다 —
    // 머리글로 읽히는가, 무엇이라고 읽히는가.
    final node = tester.getSemantics(find.byType(SameAddressGroupHeader));
    expect(node.label, '테헤란로 123에 2명');
    expect(
      node.flagsCollection.isHeader,
      isTrue,
      reason: '머리글로 읽혀야 스크린리더 사용자가 묶음 단위로 건너뛸 수 있다',
    );
    handle.dispose();
  });
}
