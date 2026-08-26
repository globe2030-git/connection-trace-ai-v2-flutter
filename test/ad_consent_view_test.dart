import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/views/ad_consent_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 광고 수신 동의 화면의 **법 요건 동작**을 고정한다(추가 472 · 법무 회신 473).
///
/// 여기 있는 것들은 보기 좋으라고 만든 규칙이 아니다. 하나씩 조문이 붙어 있고,
/// 깨지면 **받아 둔 동의가 무효가 되거나 동의 없는 전송이 된다.**
///
/// ⚠️ 배치를 바꾸려면 [AdConsentView.textVersion]도 올려야 한다 — 나중에 배치를
/// 바꾸면 **이미 받은 동의가 무엇에 대한 동의였는지**가 달라진다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    SnsAuthProvider? provider = SnsAuthProvider.google,
    Future<bool> Function({required bool email, required bool push})? onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdConsentView(
          provider: provider,
          onSubmit: onSubmit ?? ({required email, required push}) async => true,
        ),
      ),
    );
  }

  Finder box(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(InkWell),
      );

  group('🚨 매체는 개인정보 이용 동의가 켜져야 열린다', () {
    const useTitle = '광고성 정보를 보내기 위해 아래 개인정보를 이용하는 데 동의합니다';
    const emailTitle = '이메일로 광고성 정보 받기';

    testWidgets('⭐ 전제를 안 켜면 매체를 켤 수 없다', (tester) async {
      var submitted = (email: false, push: false);
      await pump(
        tester,
        onSubmit: ({required email, required push}) async {
          submitted = (email: email, push: push);
          return true;
        },
      );

      // 전제를 끈 채로 이메일을 눌러 본다.
      await tester.tap(box(emailTitle).first, warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(
        submitted.email,
        isFalse,
        reason: '전제 없이 매체만 켜지면 "수신 동의는 있는데 개인정보를 쓸 근거가 '
            '없는" 상태가 된다 — 보내면 §15 위반, 안 보내면 이용자는 '
            '"동의했는데 왜 안 오나"가 된다',
      );
    });

    testWidgets('전제를 켜면 매체를 켤 수 있다', (tester) async {
      var submitted = (email: false, push: false);
      await pump(
        tester,
        onSubmit: ({required email, required push}) async {
          submitted = (email: email, push: push);
          return true;
        },
      );

      await tester.tap(box(useTitle).first);
      await tester.pump();
      await tester.tap(box(emailTitle).first);
      await tester.pump();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(submitted.email, isTrue);
    });

    testWidgets('⭐ 전제를 끄면 켜 두었던 매체도 함께 꺼진다', (tester) async {
      var submitted = (email: true, push: true);
      await pump(
        tester,
        onSubmit: ({required email, required push}) async {
          submitted = (email: email, push: push);
          return true;
        },
      );

      await tester.tap(box(useTitle).first);
      await tester.pump();
      await tester.tap(box(emailTitle).first);
      await tester.pump();
      // 다시 전제를 끈다.
      await tester.tap(box(useTitle).first);
      await tester.pump();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(
        submitted.email,
        isFalse,
        reason: '잠그기만 하고 값을 남겨 두면 "쓸 근거는 없는데 받겠다고 한 상태"가 '
            '그대로 저장된다',
      );
    });
  });

  group('🚨 네이버 계정에는 이메일 항목이 없다', () {
    testWidgets('⭐ 네이버면 이메일 체크박스를 그리지 않는다', (tester) async {
      await pump(tester, provider: SnsAuthProvider.naver);
      expect(
        find.text('이메일로 광고성 정보 받기'),
        findsNothing,
        reason: '네이버가 주는 것은 소유가 확인되지 않은 "연락처 이메일"이라 '
            '남의 주소일 수 있다. 그 주소로 광고를 보내면 동의하지 않은 '
            '제3자에게 전송한 것이 된다(망법 §50①)',
      );
      expect(find.text('앱 알림으로 광고성 정보 받기'), findsOneWidget);
    });

    testWidgets('⭐ 네이버면 이용 항목 고지에서도 이메일을 뺀다', (tester) async {
      await pump(tester, provider: SnsAuthProvider.naver);
      expect(
        find.text('앱 알림을 보내기 위한 기기 알림 토큰'),
        findsOneWidget,
        reason: '받지도 않을 항목을 이용 항목으로 고지하면 그것대로 사실과 다르다',
      );
    });

    testWidgets('구글이면 이메일 항목이 있다', (tester) async {
      await pump(tester, provider: SnsAuthProvider.google);
      expect(find.text('이메일로 광고성 정보 받기'), findsOneWidget);
    });
  });

  group('기본값과 거부 경로', () {
    testWidgets('⭐ 셋 다 꺼진 채로 시작한다', (tester) async {
      var submitted = (email: true, push: true);
      await pump(
        tester,
        onSubmit: ({required email, required push}) async {
          submitted = (email: email, push: push);
          return true;
        },
      );
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(submitted.email, isFalse);
      expect(
        submitted.push,
        isFalse,
        reason: '기본으로 켜 두고 끄게 하는 방식은 안내서 p.12 가 금지한다',
      );
    });

    testWidgets('⭐ 하나도 안 골라도 진행된다', (tester) async {
      var called = false;
      await pump(
        tester,
        onSubmit: ({required email, required push}) async {
          called = true;
          return true;
        },
      );
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();
      expect(
        called,
        isTrue,
        reason: '거부를 이유로 진행을 막으면 법 §22⑤ 위반이다',
      );
    });
  });

  group('🚨 서버가 거부하면 화면도 되돌린다', () {
    testWidgets('⭐ 저장 실패 시 체크가 풀리고 이유를 알린다', (tester) async {
      await pump(
        tester,
        onSubmit: ({required email, required push}) async => false,
      );

      const useTitle = '광고성 정보를 보내기 위해 아래 개인정보를 이용하는 데 동의합니다';
      await tester.tap(box(useTitle).first);
      await tester.pump();
      await tester.tap(box('이메일로 광고성 정보 받기').first);
      await tester.pump();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      expect(
        find.text('설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget,
        reason: '서버는 거부했는데 화면만 켜진 채 넘어가면 이용자는 동의한 줄 '
            '알고, 그건 동의 없는 이용이 된다. firestore.rules 에 필드가 없으면 '
            '실제로 이 경로를 탄다',
      );
    });
  });

  group('표시 요건', () {
    testWidgets('⭐ 제목에 "광고성 정보"가 있다', (tester) async {
      await pump(tester);
      expect(
        find.text('광고성 정보 수신 동의'),
        findsOneWidget,
        reason: '"새 소식"처럼 광고임을 흐리는 이름으로 받은 동의는 '
            '명시적 사전 동의로 보지 않는다(안내서 p.12는 "마케팅 동의"조차 금지)',
      );
    });

    testWidgets('⭐ [선택] 배지가 세 항목 전부에 있다', (tester) async {
      await pump(tester);
      expect(
        find.text('선택'),
        findsNWidgets(4), // 머리 배지 1 + 항목 3
        reason: '시행령 §17④ — 선택할 수 있다는 사실을 명확히 표시해야 한다',
      );
    });

    testWidgets('전송자 명칭을 밝힌다', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('크림하우스주식회사'),
        findsOneWidget,
        reason: '누가 보내는지 화면에 없으면 명시적 동의로 보기 어렵다(안내서 p.12)',
      );
    });
  });
}
