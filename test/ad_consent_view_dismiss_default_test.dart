import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/ad_consent_view.dart';

/// 광고 동의 화면이 **제출하면 닫히는지** 본다(추가 671).
///
/// ## 무엇을 지키려는 검사인가
///
/// 2026-09-03 실기기에서 잡았다. **설정 → 광고성 정보 수신에서 모두 끄고
/// 「저장」을 눌렀는데 화면이 그대로 있었다.**
///
/// ```
/// 서버      adConsentEmail=false · adConsentPush=false · changedAt 갱신됨  → 저장은 됐다
/// 화면      그대로                                                        → 안 닫혔다
/// ```
///
/// 원인: `dismissOnSubmit` 의 **기본값이 `false`** 였고 `settings_view` 가
/// 그 값을 **안 넘겼다.** 그래서 저장은 되는데 화면이 안 닫혔다.
///
/// 🚨 **같은 증상이 세 번째다.** 앞의 둘은 「첫 물음」 경로에서 났고
/// (2026-08-26, 저장 실패 → 제자리 / 고친 뒤 저장 성공 → 그래도 제자리),
/// 그때는 **그 경로만** 고쳤다. **설정 경로는 그대로 남아 있었다.**
///
/// ⚠️ **설정 경로가 오히려 더 나쁘다** — 첫 물음은 못 나가면 앱을 못 써서
/// 바로 티가 나는데, 설정은 뒤로가기로 나갈 수 있어 **「저장이 안 됐나?」로만
/// 보이고 이용자가 다시 누른다.**
///
/// 📌 그래서 기본값을 `true` 로 뒤집었다. **빠뜨려도 닫히는 쪽**이 기본이어야
/// 한다 — 종전에는 부르는 자리마다 기억해야 했고, 이번에 그걸 빠뜨렸다.
void main() {
  testWidgets('🚨 기본값으로 열면 제출 뒤 화면이 닫힌다', (tester) async {
    var submitted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AdConsentView(
                      provider: SnsAuthProvider.google,
                      submitLabel: '저장',
                      // 🚨 `dismissOnSubmit` 을 **일부러 안 넘긴다** — 이 검사의
                      //    요점이 「빠뜨려도 닫히는가」이기 때문이다.
                      onSubmit: ({required email, required push}) async {
                        submitted = true;
                        return true; // 저장 성공
                      },
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('저장'), findsOneWidget, reason: '화면이 열려야 한다');

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(submitted, isTrue, reason: 'onSubmit 이 불려야 한다');
    expect(
      find.text('저장'),
      findsNothing,
      reason:
          '저장에 성공했으면 화면이 닫혀야 한다. 안 닫히면 이용자에게는 '
          '「저장이 안 됐다」로 보이고, 실제로는 저장됐는데 다시 누른다.',
    );
    expect(find.text('열기'), findsOneWidget, reason: '앞 화면으로 돌아와야 한다');
  });

  testWidgets('🚨 저장에 실패해도 닫는다 — 머물면 안 한 줄 안다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => AdConsentView(
                      provider: SnsAuthProvider.google,
                      submitLabel: '저장',
                      onSubmit: ({required email, required push}) async =>
                          false, // 저장 실패
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 실패해도 닫는다. 저장이 안 됐으니 「동의하지 않은 상태」로 남고,
    // 그 상태에서는 아무것도 보내지 않는다 — 화면과 서버가 어긋나지 않는다.
    expect(find.text('열기'), findsOneWidget);
  });
}
