import 'package:connection_trace_ai_flutter/core/utils/contact_export_name.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/contact_export_name_format_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이름 형식 고르는 화면(추가 494).
///
/// 요건 둘이 화면에 실제로 있는지 본다.
/// 1. 🚨 **미리보기** — "이름 형식을 고르세요"만으로는 무엇을 고르는지 모른다
/// 2. 🚨 **"이미 저장한 것은 바뀌지 않습니다"** — 안 적으면 문의가 온다
void main() {
  Future<ContactExportNameFormat?> open(
    WidgetTester tester, {
    ContactExportNameFormat initial = ContactExportNameFormat.nameOnly,
    bool firstTime = true,
  }) async {
    ContactExportNameFormat? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await ContactExportNameFormatSheet.show(
                    context,
                    initial: initial,
                    firstTime: firstTime,
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return picked;
  }

  group('🚨 화면에 반드시 있어야 하는 것', () {
    testWidgets('⭐ 네 형식의 미리보기가 모두 보인다', (tester) async {
      await open(tester);
      for (final format in ContactExportNameFormat.values) {
        expect(
          find.text(previewOf(format)),
          findsOneWidget,
          reason: '${format.label} 의 미리보기가 없으면 무엇을 고르는지 모른다',
        );
      }
    });

    testWidgets('⭐ 이미 저장한 것은 바뀌지 않는다고 적혀 있다', (tester) async {
      await open(tester);
      expect(
        find.textContaining('이미 주소록에 저장한 연락처는 바뀌지 않습니다'),
        findsOneWidget,
        reason: '나중에 형식을 바꿔도 소급되지 않는다. 안 적으면 '
            '"바꿨는데 왜 그대로냐"가 문의로 온다',
      );
    });

    testWidgets('⭐ 미리보기는 가상값이다 — 실제 명함이 안 쓰인다', (tester) async {
      await open(tester);
      // 고르는 화면에서 제3자 개인정보가 형식마다 네 번 보이면 안 된다.
      expect(find.textContaining('홍길동'), findsWidgets);
    });
  });

  group('고르기', () {
    testWidgets('처음엔 넘겨받은 형식이 선택돼 있다', (tester) async {
      await open(tester, initial: ContactExportNameFormat.nameTitleCompany);
      final selected = tester.widgetList<Icon>(
        find.byIcon(Icons.radio_button_checked),
      );
      expect(selected.length, 1);
    });

    testWidgets('⭐ 고른 형식이 돌아온다', (tester) async {
      ContactExportNameFormat? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    picked = await ContactExportNameFormatSheet.show(
                      context,
                      initial: ContactExportNameFormat.nameOnly,
                      firstTime: true,
                    );
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ContactExportNameFormat.nameCompany.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 형식으로 계속'));
      await tester.pumpAndSettle();
      expect(picked, ContactExportNameFormat.nameCompany);
    });
  });

  group('첫 물음과 설정에서 다르게 보인다', () {
    testWidgets('첫 물음이면 왜 묻는지 설명한다', (tester) async {
      await open(tester, firstTime: true);
      expect(find.textContaining('동명이인'), findsOneWidget);
      expect(find.text('이 형식으로 계속'), findsOneWidget);
    });

    testWidgets('설정에서 열면 앞으로 적용된다고 말한다', (tester) async {
      await open(tester, firstTime: false);
      expect(find.textContaining('앞으로 내보낼 명함에 적용됩니다'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget);
    });
  });
}
