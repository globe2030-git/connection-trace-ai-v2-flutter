/// **인증 화면이 「어디로 가는지」를 말하는지 잠근다** (2026-09-06).
///
/// ## 왜 이 검사가 있나
///
/// 대체문자(SMS)를 끄면서(`phoneOtpSender.ts` `failover: "N"`) 인증번호가
/// **카카오톡으로만** 간다. 그런데 이 화면에는 카카오·알림톡 언급이 **한
/// 글자도 없었다**(법무 실물 확인). 그러면 이용자는 문자함을 보고, 안 오니
/// 다시 보내고, 포기한다 — **인증에 건너뛰기가 없어서 거기서 앱을 못 쓴다.**
///
/// ## 🚨 문안은 globe2030님이 직접 쓰셨다
///
/// ```
/// '인증은 카카오톡으로만 보내집니다.'   항상 보인다
/// '카카오톡을 확인하세요.'              인증번호를 받은 뒤에만 보인다
/// ```
///
/// **한 글자도 바꾸지 않는다.** 이 검사가 그 문장을 그대로 잠근다 — 없으면
/// 다음 사람이 말투를 다듬다가 조용히 바꿔 놓는다.
///
/// ⚠️ **이 검사가 못 보는 것**: 실제로 **눈에 띄는지**(글자 크기·색·자리),
/// 그리고 기기 화면에서 안 깨지는지. 규약 4장 — *"자동 테스트는 규칙을 보고
/// 사람은 화면을 본다."* 실기기 확인은 게이트를 켜는 날(런북 3단계)에 묶는다.
library;

import 'package:connection_trace_ai_flutter/presentation/features/auth/views/phone_verify_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _beforeSend = '인증은 카카오톡으로만 보내집니다.';
const _afterSend = '카카오톡을 확인해 주세요.';

Future<void> _pump(WidgetTester tester, {bool codeSent = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PhoneVerifyView(
        onVerified: () {},
        debugStartCodeSent: codeSent,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('🚨 번호를 넣기 전에 「카카오톡으로만 간다」를 말한다', (tester) async {
    await _pump(tester);

    expect(
      find.text(_beforeSend),
      findsOneWidget,
      reason: '⭐ 보내기 전에 알아야 카카오톡을 열어 둔다. 받은 뒤에 알려 주면 '
          '이미 문자함을 뒤진 뒤다',
    );
  });

  testWidgets('🚨 아직 안 보냈으면 「확인하세요」는 안 뜬다 — 빈 칸을 그리지 않는다', (tester) async {
    await _pump(tester);

    expect(
      find.text(_afterSend),
      findsNothing,
      reason: '보내지도 않았는데 「확인하세요」가 뜨면 없는 메시지를 찾게 만든다',
    );
  });

  testWidgets('⭐ 「만」이 살아 있다 — 부정문 없이 「이것뿐」을 말하는 자리', (tester) async {
    await _pump(tester);

    final text = tester.widget<Text>(find.text(_beforeSend));
    expect(
      text.data,
      contains('카카오톡으로만'),
      reason: '🚨 「카카오톡으로」로 줄면 「없으면 못 받는다」가 사라진다. '
          'globe2030님 지시: "부정적인 말은 피하는게 좋겠어." — '
          '「만」 한 글자가 그 역할을 한다',
    );
  });

  testWidgets('문안이 한 글자도 안 바뀌었는지 — globe2030님이 직접 쓰신 문장', (tester) async {
    await _pump(tester);

    // 🚨 부분 일치가 아니라 **완전 일치**로 잠근다. 말투를 다듬다가 조용히
    //    바뀌는 것을 막는 것이 이 검사의 목적이다.
    expect(find.text(_beforeSend), findsOneWidget);
  });

  // ────────────────────────────────────────────────────────────────────
  // 🚨 **아래 둘은 2026-09-06에 「검사가 안 잡는 것」을 발견하고 더했다.**
  //
  // 그날 ② 문구를 「확인하세요」→「확인해 주세요」로 바꿨는데 **검사가 하나도
  // 안 깨졌다.** 위 검사들이 ②를 보는 방식이 `findsNothing`(아직 안 보냈을 때
  // 없다) 뿐이라, **어떤 문자열로 바꿔도 통과**했기 때문이다.
  //
  // ⭐ **「통과만 확인한 검사는 안 잡는 검사일 수 있다」가 그대로 나왔다.**
  //    그래서 `debugStartCodeSent` 로 그 상태를 열어 실제로 잠근다.
  // ────────────────────────────────────────────────────────────────────

  testWidgets('🚨 인증번호를 받은 뒤에는 「카카오톡을 확인해 주세요」가 뜬다', (tester) async {
    await _pump(tester, codeSent: true);

    expect(
      find.text(_afterSend),
      findsOneWidget,
      reason: '⭐ 여기가 실제로 기다리는 자리다. 앞의 안내는 그때 이미 잊는다',
    );
  });

  testWidgets('🚨 ② 문안도 완전 일치로 잠근다 — 말투를 다듬어도 깨져야 한다', (tester) async {
    await _pump(tester, codeSent: true);

    // 이 화면의 다른 문구가 전부 「~해 주세요」체라서 그쪽으로 맞췄다
    // (2026-09-06 확정). **바꾸려면 이 검사가 먼저 빨개져야 한다.**
    final text = tester.widget<Text>(find.text(_afterSend));
    expect(text.data, _afterSend);
  });
}
