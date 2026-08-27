import 'package:connection_trace_ai_flutter/core/services/geo_failure_lookup.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/geo_notice_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 좌표를 못 얻은 명함에 붙는 안내 줄(P1-25).
///
/// ## 🚨 여기서 지키는 것은 「말이 사실인가」다
///
/// 처음 후보 문구는 *"주소 위치를 확인할 수 없습니다"* 였다. **버렸다** —
/// 2026-08-21 실측에서 좌표 없는 30건이 **전부 지역으로 잘 보이고 있었고**,
/// 그것들에 대해 그 말은 **사실이 아니다.** 멀쩡한 것을 고장으로 읽게 만든다.
///
/// 📌 두 상태를 **갈라 말한다.** 하나는 *"지역으로만 표시된다"*, 다른 하나는
/// *"주변에 표시되지 않는다"*. 뜻이 다르므로 말도 달라야 한다.
void main() {
  Future<void> pump(WidgetTester tester, GeoNoticeState state,
          {VoidCallback? onEdit}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeoNoticeRow(state: state, onEditAddress: onEdit ?? () {}),
          ),
        ),
      );

  group('🚨 상태마다 다른 말을 한다', () {
    testWidgets('⭐ 지역으로 보이는 명함에 "확인할 수 없다"고 하지 않는다',
        (tester) async {
      await pump(tester, GeoNoticeState.regionOnly);
      expect(find.text('정확한 위치를 찾지 못해 지역으로만 표시됩니다'), findsOneWidget);
      expect(
        find.textContaining('확인할 수 없'),
        findsNothing,
        reason: '이 명함은 주변 화면에 지역 묶음으로 잘 보인다. "확인할 수 없다"는 '
            '사실이 아니고, 멀쩡한 것을 고장으로 읽게 만든다',
      );
    });

    testWidgets('⭐ 정말 사라지는 명함에만 "표시되지 않는다"고 한다', (tester) async {
      await pump(tester, GeoNoticeState.hidden);
      expect(find.text('주소로 위치를 찾지 못해 주변에 표시되지 않습니다'), findsOneWidget);
    });

    testWidgets('⭐ 좌표가 있으면 아무 말도 안 한다', (tester) async {
      await pump(tester, GeoNoticeState.located);
      expect(find.byType(TextButton), findsNothing);
      expect(GeoNoticeRow.messageFor(GeoNoticeState.located), isNull);
    });

    testWidgets('⭐ 주소가 없으면 침묵한다 — 지오코딩 실패가 아니다', (tester) async {
      await pump(tester, GeoNoticeState.noAddress);
      expect(find.byType(TextButton), findsNothing);
      expect(
        GeoNoticeRow.messageFor(GeoNoticeState.noAddress),
        isNull,
        reason: '주소 입력 누락은 성격이 다르다. "주소를 넣으면…"은 권유가 되고, '
            'P1-25 범위 밖이다 — 별건으로 다룬다',
      );
    });
  });

  group('🚨 경고처럼 보이지 않는다 — 고장이 아니다', () {
    testWidgets('⭐ 경고 아이콘을 쓰지 않는다', (tester) async {
      await pump(tester, GeoNoticeState.regionOnly);
      for (final warn in [
        Icons.warning,
        Icons.warning_amber,
        Icons.error,
        Icons.error_outline,
        Icons.report_problem,
      ]) {
        expect(
          find.byIcon(warn),
          findsNothing,
          reason: '지역으로 보이는 명함은 고장이 아니다. 이 줄은 "주소를 고치면 '
              '거리로도 보인다"는 선택지이지 경고가 아니다',
        );
      }
      expect(find.byIcon(Icons.place_outlined), findsOneWidget);
    });

    testWidgets('⭐ 붉은 계열을 쓰지 않는다', (tester) async {
      await pump(tester, GeoNoticeState.hidden);
      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final t in texts) {
        final c = t.style?.color;
        if (c == null) continue;
        expect(
          c.r > c.g * 1.5 && c.r > c.b * 1.5,
          isFalse,
          reason: '붉은 글씨는 "잘못됐다"로 읽힌다',
        );
      }
    });
  });

  group('할 일이 붙어 있다', () {
    testWidgets('⭐ [주소 수정]을 누르면 알린다', (tester) async {
      var tapped = false;
      await pump(tester, GeoNoticeState.regionOnly, onEdit: () => tapped = true);
      await tester.tap(find.text('주소 수정'));
      expect(
        tapped,
        isTrue,
        reason: '"왜 이렇게 보이는지"만 알리고 끝나면 이용자가 할 수 있는 것이 '
            '없다. 고치러 갈 길이 붙어 있어야 한다',
      );
    });
  });
}
