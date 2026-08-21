import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/common/collapsing_list_header.dart';

/// 목록 상단 고정(UI 개선 ⑦, 2026-08-21)이 실제로 무엇을 접고 무엇을
/// 고정하는지 고정한다. 지갑·주변 화면이 함께 쓸 공용 컴포넌트라 화면
/// 맥락(WalletViewModel 등) 없이 이 컴포넌트만 떼어 본다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool collapsed,
    Key? decoratedKey,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollapsingListHeader(
            collapsed: collapsed,
            expandedTop: const Text('큰 제목'),
            collapsedTop: const Text('축약 제목'),
            pinnedTools: const Text('검색+정렬'),
          ),
        ),
      ),
    );
  }

  group('CollapsingListHeader', () {
    testWidgets('펼친 상태에서는 큰 제목만 보이고 축약 제목은 없다', (
      tester,
    ) async {
      await pump(tester, collapsed: false);

      expect(find.text('큰 제목'), findsOneWidget);
      expect(find.text('축약 제목'), findsNothing);
      expect(
        find.text('검색+정렬'),
        findsOneWidget,
        reason: '도구줄은 펼친 상태에서도 당연히 보인다',
      );
    });

    testWidgets('⭐ 접으면 큰 제목은 사라지고 축약 제목이 뜨는데, 도구줄은 그대로다', (
      tester,
    ) async {
      await pump(tester, collapsed: true);
      await tester.pumpAndSettle();

      expect(
        find.text('큰 제목'),
        findsNothing,
        reason: '브리프 표: 큰 제목 블록은 흘려보낸다',
      );
      expect(find.text('축약 제목'), findsOneWidget);
      expect(
        find.text('검색+정렬'),
        findsOneWidget,
        reason: '브리프 표: 검색창·정렬 칩은 고정이다 — 접혀도 사라지면 안 된다',
      );
    });

    testWidgets('접힌 상태에서만 그림자를 그린다(층 표현)', (tester) async {
      await pump(tester, collapsed: false);
      final expandedBox = tester.widget<DecoratedBox>(
        find.byKey(CollapsingListHeader.shadowBoxKey),
      );
      expect(
        (expandedBox.decoration as BoxDecoration).boxShadow,
        isNull,
        reason: '펼친 상태에서는 목록과 같은 층이라 그림자가 없어야 한다',
      );

      await pump(tester, collapsed: true);
      await tester.pumpAndSettle();
      final collapsedBox = tester.widget<DecoratedBox>(
        find.byKey(CollapsingListHeader.shadowBoxKey),
      );
      expect(
        (collapsedBox.decoration as BoxDecoration).boxShadow,
        isNotNull,
        reason: '고정 상태에서는 목록 위에 떠 있는 층임을 그림자로 보여야 한다',
      );
    });
  });

  group('HeaderCollapseTracker', () {
    test('히스테리시스 없이 경계 하나로만 판정하지 않는다 — 접는 지점과 펴는 지점이 다르다', () {
      final tracker = HeaderCollapseTracker(collapseAt: 28, expandAt: 6);

      expect(tracker.collapsed, isFalse);
      expect(tracker.update(0), isFalse, reason: '맨 위 — 아무 변화 없음');

      expect(tracker.update(30), isTrue, reason: '28을 넘으면 접힌다');
      expect(tracker.collapsed, isTrue);

      expect(
        tracker.update(15),
        isFalse,
        reason: '15는 expandAt(6)보다 커서 편 상태로 돌아가지 않는다 — 히스테리시스',
      );
      expect(tracker.collapsed, isTrue);

      expect(tracker.update(3), isTrue, reason: 'expandAt 아래로 내려가면 편다');
      expect(tracker.collapsed, isFalse);
    });

    test('reset()은 스크롤 위치와 무관하게 강제로 편다', () {
      final tracker = HeaderCollapseTracker();
      tracker.update(100);
      expect(tracker.collapsed, isTrue);

      tracker.reset();
      expect(tracker.collapsed, isFalse);
    });
  });
}
