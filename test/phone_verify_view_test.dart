import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/features/auth/views/phone_verify_view.dart';

/// 휴대전화번호 확인 화면(추가 565)의 **화면 규칙**을 잠근다.
///
/// 🚨 여기서 잠그는 것은 **건너뛸 수 없다**는 것이다. 그것이 이 화면의
/// 존재 이유이고, 실수로 풀리면 방침이 통째로 무너지는데 **코드만 봐서는
/// 안 보인다**(`PopScope(canPop: false)` 한 줄이라 지우기 쉽다).
///
/// ⚠️ 서버를 부르는 경로(인증번호 받기·확인)는 여기서 안 누른다 — Firebase가
/// 필요하다. 그쪽 판정은 `functions/src/phoneOtp.test.ts`가 덮는다.
void main() {
  Widget wrap(VoidCallback onVerified) => MaterialApp(
        home: PhoneVerifyView(onVerified: onVerified),
      );

  testWidgets('🚨 뒤로가기로 빠져나갈 수 없다 — 건너뛰기가 없다', (tester) async {
    await tester.pumpWidget(wrap(() {}));

    final popScope = tester.widget<PopScope>(
      find.byType(PopScope).first,
    );
    // 이 한 줄이 방침을 지킨다. 지우면 안드로이드 뒤로가기 한 번으로 뚫린다.
    expect(popScope.canPop, isFalse);
  });

  testWidgets('인증번호를 받기 전에는 코드 칸을 그리지 않는다', (tester) async {
    await tester.pumpWidget(wrap(() {}));

    // **빈 칸을 그리지 않는다** — 이 저장소 규칙. 받기 전에는 넣을 것이 없다.
    expect(find.text('인증번호'), findsNothing);
    expect(find.text('6자리'), findsNothing);
    // 번호 칸과 받기 버튼은 처음부터 있다.
    expect(find.text('휴대전화번호'), findsOneWidget);
    expect(find.text('인증번호 받기'), findsOneWidget);
  });

  testWidgets('인증번호를 받기 전에는 「확인하고 시작하기」가 눌리지 않는다', (tester) async {
    var verified = false;
    await tester.pumpWidget(wrap(() => verified = true));

    await tester.tap(find.text('확인하고 시작하기'));
    await tester.pump();

    // 눌러도 아무 일이 없어야 한다 — 코드를 안 받았는데 통과하면 안 된다.
    expect(verified, isFalse);
  });

  testWidgets('⚠️ 「본인확인」이라는 말을 쓰지 않는다', (tester) async {
    await tester.pumpWidget(wrap(() {}));

    // 정보통신망법 §23의3의 「본인확인업무」는 지정 기관만 할 수 있는 법정
    // 용어다. 우리가 하는 것을 그렇게 부르면 과태료 조문의 외관을 스스로
    // 만든다(법률 조사 판단). 화면 어디에도 쓰지 않는다.
    expect(find.textContaining('본인확인'), findsNothing);
    expect(find.textContaining('본인 확인'), findsNothing);
    expect(find.text('휴대전화번호 확인'), findsOneWidget);
  });

  testWidgets('과장하지 않는다 — 확인하는 범위를 그대로 적는다', (tester) async {
    await tester.pumpWidget(wrap(() {}));

    // 이름·생년월일을 통신사에 맞춰 보지 않는다. 그렇게 읽힐 문구를 두지
    // 않는다(CLAUDE.md 4절 — 과장하지 않는다).
    expect(
      find.text('이 번호로 오는 인증번호를 받으시는지만 봅니다.'),
      findsOneWidget,
    );
  });
}
