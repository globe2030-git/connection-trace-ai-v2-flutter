import 'package:connection_trace_ai_flutter/data/repositories/auth_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/email_signup_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// ⑧ 이메일 화면에 「비밀번호 확인」 칸이 없다는 것을 고정한다(추가 640,
/// 2026-08-31). 이 화면이 가입과 로그인을 겸하게 되면서(추가 636) 확인칸은
/// 로그인하는 사람에게 뜻이 없어졌다 — 이미 정해 둔 비밀번호를 다시
/// 입력하게 할 이유가 없다. 대신 「보기」 아이콘으로 오타를 눈으로
/// 확인하게 하므로, 그 토글이 실제로 동작하는지도 함께 고정한다.
void main() {
  Widget wrap() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
          create: (_) => AuthRepository(clearWebSession: () async {}),
        ),
      ],
      child: const MaterialApp(home: EmailSignupView()),
    );
  }

  testWidgets('비밀번호 필드는 하나뿐이고, 「확인」 칸은 없다', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('비밀번호 확인'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2), reason: '이메일 · 비밀번호 두 칸만 있어야 한다');
  });

  testWidgets('「보기」 아이콘을 누르면 비밀번호가 평문으로 바뀐다', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final passwordField = tester.widget<TextField>(find.byType(TextField).last);
    expect(passwordField.obscureText, isTrue, reason: '기본값은 가려진 상태여야 한다');

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    final toggled = tester.widget<TextField>(find.byType(TextField).last);
    expect(toggled.obscureText, isFalse, reason: '「보기」를 누르면 평문으로 보여야 한다');
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
