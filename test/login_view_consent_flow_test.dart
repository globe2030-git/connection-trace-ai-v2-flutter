import 'package:connection_trace_ai_flutter/data/repositories/auth_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/my_profile_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/login_view.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/signup_consent_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⑨(통합 동의 화면)가 로그인 화면과 맞물리는 핵심 회귀 지점을 고정한다
/// (추가 632, `email-signup-unified-consent-2026-08-31.md` §1·§2).
///
/// 🚨 **"OAuth가 취소돼도 동의는 유지된다"** — 이 저장소가 가장 중요하게
/// 지키라고 한 지점이다. 처음 버튼을 눌러 ⑨를 통과한 뒤, 실제 로그인이
/// 실패해(이 테스트 환경에는 Google 로그인 플러그인이 없어 반드시 실패한다)
/// 로그인 화면으로 돌아와도, **다시 버튼을 눌렀을 때 ⑨가 또 뜨면 안 된다.**
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_auth'),
          (call) async => null,
        );
  });

  Widget wrap() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthRepository>(
          create: (_) => AuthRepository(clearWebSession: () async {}),
        ),
        ChangeNotifierProvider<MyProfileRepository>(
          create: (_) => MyProfileRepository(),
        ),
      ],
      child: const MaterialApp(home: LoginView()),
    );
  }

  testWidgets('⭐ 버튼을 처음 누르면 ⑨(통합 동의)가 뜬다', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(SignupConsentView), findsNothing);
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupConsentView), findsOneWidget);
  });

  testWidgets('🚨 필수 3종을 다 체크해야 「동의하고 시작하기」가 활성화된다', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();

    FilledButton submitButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '동의하고 시작하기'));

    expect(submitButton().onPressed, isNull, reason: '아무 것도 안 골랐으면 눌리면 안 된다');

    await tester.tap(find.text('필수 항목에 모두 동의'));
    await tester.pumpAndSettle();

    expect(submitButton().onPressed, isNotNull, reason: '필수 3종을 다 켰으면 눌려야 한다');
  });

  testWidgets('⭐ OAuth가 취소·실패해도 동의는 유지된다 — ⑨가 다시 뜨지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 1) 처음 누르면 ⑨가 뜬다. 필수 3종을 체크하고 진행한다.
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupConsentView), findsOneWidget);

    await tester.tap(find.text('필수 항목에 모두 동의'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 시작하기'));
    await tester.pumpAndSettle();

    // 2) ⑨를 빠져나와 실제 로그인을 시도한다 — 이 테스트 환경에는 Google
    //    로그인 플러그인이 없어 반드시 실패한다(OAuth 취소·실패와 같은 결과).
    expect(find.byType(SignupConsentView), findsNothing);
    expect(find.byType(LoginView), findsOneWidget);

    // 3) 다시 눌러도 ⑨가 또 뜨면 안 된다 — 동의를 그대로 쥐고 있어야 한다.
    await tester.tap(find.text('Google로 계속하기'));
    await tester.pumpAndSettle();
    expect(
      find.byType(SignupConsentView),
      findsNothing,
      reason: '이미 ⑨를 통과했으면 재시도에서 다시 보여주면 안 된다',
    );
  });
}
