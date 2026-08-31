// 만 14세 확인을 안 했을 때 로그인 버튼이 「이유를 말하는가」 (추가 626).
//
// 🚨 **왜 있나**: 카카오·네이버 버튼은 **공식 브랜드 이미지를 통째로** 쓴다.
// 그래서 눌리지 않는 상태에서도 **밝은 노랑·초록 그대로**이고, 이용자는
// 멀쩡해 보이는 버튼을 눌렀는데 **아무 일도 안 일어나는** 것을 본다.
//
// ⚠️ 이 저장소는 그 원칙을 이미 알고 있었다 — 로그인 화면 주석에
// *"눌러도 안 되는 버튼을 두면 이용자는 고장으로 읽는다"* 가 있고 애플 버튼은
// 그래서 아예 안 그린다. **그런데 이 자리에는 적용이 안 됐다.**
import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/widgets/official_social_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  final art = OfficialButtonArt.of(SnsAuthProvider.kakao);

  testWidgets('⭐ 눌리지 않을 때 탭하면 이유를 말할 기회가 온다', (tester) async {
    if (art == null) return; // 공식 애셋이 없는 제공자면 건너뛴다
    var blocked = 0;
    var pressed = 0;
    await tester.pumpWidget(
      wrap(
        OfficialSocialButton(
          art: art,
          isLoading: false,
          onPressed: null, // 만 14세 미확인 상태
          onBlockedTap: () => blocked++,
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(blocked, 1, reason: '눌리지 않는 버튼이 아무 말도 안 하면 안 된다');
    expect(pressed, 0, reason: '로그인은 여전히 시작되지 않아야 한다');
  });

  testWidgets('🚨 눌리는 상태에서는 안내가 끼어들지 않는다', (tester) async {
    if (art == null) return;
    var blocked = 0;
    var pressed = 0;
    await tester.pumpWidget(
      wrap(
        OfficialSocialButton(
          art: art,
          isLoading: false,
          onPressed: () => pressed++,
          onBlockedTap: () => blocked++,
        ),
      ),
    );
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(pressed, 1);
    expect(blocked, 0, reason: '정상 로그인 경로에 안내가 끼면 안 된다');
  });
}
