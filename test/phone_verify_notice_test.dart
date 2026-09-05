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
const _afterSend = '카카오톡을 확인하세요.';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: PhoneVerifyView(onVerified: () {})),
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
}
