import 'package:connection_trace_ai_flutter/presentation/features/auth/views/ad_consent_notice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 처리결과 통지(추가 472)의 **법정 요건**을 고정한다.
///
/// 정보통신망법 §50⑦·시행령 §62의2는 수신 동의·철회를 받은 사실을 **14일 이내에**
/// 알리도록 한다. 안내서는 앱 팝업으로 갈음할 수 있다고 본다.
///
/// 담아야 하는 것 넷: **전송자 명칭 · 동의/철회의 사실 · 날짜 · 처리 결과.**
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required DateTime at,
    required List<String> media,
    required bool consented,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdConsentNoticeDialog(
            processedAt: at,
            media: media,
            consented: consented,
          ),
        ),
      ),
    );
  }

  group('🚨 날짜를 적는다 — "오늘"이 아니다', () {
    testWidgets('⭐ 연·월·일이 그대로 찍힌다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일'],
        consented: true,
      );
      expect(
        find.textContaining('2026년 9월 15일'),
        findsOneWidget,
        reason: '안내서 p.23 이 날짜를 적도록 한다. "오늘"·"금일"은 나중에 이 '
            '화면을 기억할 때 아무 정보가 아니고 증적으로도 쓸 수 없다',
      );
    });

    testWidgets('⭐ "오늘"·"금일"이라고 쓰지 않는다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일'],
        consented: true,
      );
      expect(find.textContaining('오늘'), findsNothing);
      expect(find.textContaining('금일'), findsNothing);
    });

    testWidgets('한 자리 월·일도 그대로 쓴다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 1, 5),
        media: const ['앱 알림'],
        consented: true,
      );
      expect(find.textContaining('2026년 1월 5일'), findsOneWidget);
    });
  });

  group('담아야 하는 것 넷', () {
    testWidgets('⭐ 전송자 명칭이 있다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일'],
        consented: true,
      );
      expect(
        find.textContaining('커넥션센스'),
        findsOneWidget,
        reason: '누가 처리했는지가 없으면 통지로 볼 수 없다',
      );
    });

    testWidgets('⭐ 동의와 철회를 갈라 말한다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일'],
        consented: true,
      );
      expect(find.textContaining('동의가'), findsOneWidget);

      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const [],
        consented: false,
      );
      expect(
        find.textContaining('철회가'),
        findsOneWidget,
        reason: '§50⑦ 은 동의만이 아니라 철회에도 통지를 요구한다',
      );
    });

    testWidgets('동의한 매체를 밝힌다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일', '앱 알림'],
        consented: true,
      );
      expect(find.text('이메일, 앱 알림'), findsOneWidget);
    });

    testWidgets('철회일 때는 매체 칸을 그리지 않는다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const [],
        consented: false,
      );
      expect(
        find.text('동의하신 매체'),
        findsNothing,
        reason: '끈 사람에게 "동의하신 매체"가 비어 보이면 오히려 헷갈린다',
      );
    });
  });

  group('🚨 여기에 광고를 섞지 않는다', () {
    testWidgets('⭐ 통지에 광고 문구가 없다', (tester) async {
      await pump(
        tester,
        at: DateTime(2026, 9, 15),
        media: const ['이메일'],
        consented: true,
      );
      // 안내서 p.23 — 통지에 광고가 섞이면 통지 전체가 광고성 정보가 되고,
      // 그러면 통지 자체가 동의 없는 전송이 될 수 있다.
      for (final bait in ['혜택', '할인', '이벤트', '추천', '지금']) {
        expect(
          find.textContaining(bait),
          findsNothing,
          reason: '"$bait" 같은 유인 문구가 들어가면 통지가 광고가 된다',
        );
      }
    });
  });
}
