import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/signup_consent_view.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/widgets/consent_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ⑨(통합 동의 화면) 자체의 로직을 화면 단위로 고정한다(추가 632, §5-1·§8).
void main() {
  Widget wrap(SnsAuthProvider provider) =>
      MaterialApp(home: SignupConsentView(provider: provider));

  testWidgets('⭐ 필수 3종을 다 체크해야 「동의하고 시작하기」가 활성화된다', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(SnsAuthProvider.google));
    await tester.pumpAndSettle();

    FilledButton submitButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '동의하고 시작하기'),
    );
    expect(submitButton().onPressed, isNull);

    // 라벨은 "[필수] " 배지와 한 RichText 안에 있어 기본 find.text/textContaining
    // 은 standalone RichText를 보지 않는다 — findRichText: true로 잡는다.
    await tester.tap(find.textContaining('만 14세 이상입니다', findRichText: true));
    await tester.tap(find.textContaining('이용약관에 동의', findRichText: true));
    await tester.pumpAndSettle();
    expect(submitButton().onPressed, isNull, reason: '방침 확인이 아직 안 켜졌다');

    await tester.tap(
      find.textContaining('개인정보처리방침 확인', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(submitButton().onPressed, isNotNull, reason: '필수 3종이 다 켜졌다');
  });

  testWidgets('🚨 「필수 항목에 모두 동의」는 필수 3종만 켠다 — 광고 수신은 그대로 꺼져 있다', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(SnsAuthProvider.google));
    await tester.pumpAndSettle();

    await tester.tap(find.text('필수 항목에 모두 동의'));
    await tester.pumpAndSettle();

    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '동의하고 시작하기'),
    );
    expect(submit.onPressed, isNotNull, reason: '필수 3종은 켜졌어야 한다');

    final adRow = tester.widget<ChannelRow>(
      find.widgetWithText(ChannelRow, '광고성 정보 수신'),
    );
    expect(
      adRow.checked,
      isFalse,
      reason: '일괄 체크가 선택 항목까지 켜면 안 된다(추가 457 — 안내서가 금지)',
    );
  });

  testWidgets('⭐ 네이버로 시작하면 이메일 채널이 안 보인다', (tester) async {
    await tester.pumpWidget(wrap(SnsAuthProvider.naver));
    await tester.pumpAndSettle();

    expect(find.text('이메일로 받기'), findsNothing);
    expect(find.text('앱 알림으로 받기'), findsOneWidget);
  });

  testWidgets('구글로 시작하면 이메일 채널이 보인다', (tester) async {
    await tester.pumpWidget(wrap(SnsAuthProvider.google));
    await tester.pumpAndSettle();

    expect(find.text('이메일로 받기'), findsOneWidget);
  });

  testWidgets('취소(뒤로가기)하면 null을 돌려준다', (tester) async {
    ConsentChoice? result;
    var pushed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              pushed = true;
              result = await Navigator.of(context).push<ConsentChoice>(
                MaterialPageRoute(
                  builder: (_) =>
                      const SignupConsentView(provider: SnsAuthProvider.google),
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(pushed, isTrue);

    // 시스템 뒤로가기 대신 Navigator.pop()으로 취소를 흉내낸다.
    final navigator = tester
        .state<NavigatorState>(find.byType(Navigator).last);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
