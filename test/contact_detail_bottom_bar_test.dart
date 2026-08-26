import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/contact_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 명함 상세 시트 **아래 고정 줄**의 폭을 실제로 잰다(추가 492).
///
/// 내보내기 버튼을 여기 넣으면서 **버튼이 셋**이 됐다. 390px 폭(가장 흔한
/// 세로 화면)에서 한글 라벨이 줄바꿈되거나 줄이 넘치는지는 **재 봐야 안다** —
/// 이 저장소는 계산을 확인이라고 부르지 않는다(CLAUDE.md 4절).
///
/// 시트 전체([ContactDetailView])는 `AuthRepository` 를 읽어 pump 할 수 없다.
/// 그래서 아래 줄만 떼어 [ContactDetailBottomBar] 로 만들었다.
ContactModel makeContact() => const ContactModel(
      id: 'test-id',
      name: '홍길동',
      company: '가상상사',
      title: '영업팀장',
      phone: '010-0000-0001',
      email: 'example@example.invalid',
      tags: [],
      talkingPoints: [],
    );

Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Column(children: [const Spacer(), child])),
    ),
  );
}

/// 그려진 텍스트가 **몇 줄**인지. 두 줄이면 버튼이 좁아 접힌 것이다.
int lineCount(WidgetTester tester, String text) {
  final para = tester.renderObject<RenderParagraph>(find.text(text));
  return para.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  ).length;
}

/// 텍스트가 **잘렸는지**.
///
/// 🚨 넘침(overflow) 예외가 안 났다고 멀쩡한 게 아니다. [Text] 의 기본
/// `overflow` 는 clip 이라 **좁으면 예외 없이 조용히 잘린다.** 그래서 그려진
/// 폭과 글자가 필요로 하는 폭을 직접 견준다.
bool isClipped(WidgetTester tester, String text) {
  final para = tester.renderObject<RenderParagraph>(find.text(text));
  return para.size.width + 0.5 < para.getMaxIntrinsicWidth(double.infinity);
}

void main() {
  group('390px 세로 화면에서 버튼 셋이 들어간다', () {
    testWidgets('⭐ 줄이 넘치지 않는다', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      expect(
        tester.takeException(),
        isNull,
        reason: 'RenderFlex overflow 가 나면 실기기에서 노란 줄무늬가 뜬다',
      );
    });

    testWidgets('⭐ 세 라벨이 한 줄로 남는다', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      expect(lineCount(tester, '닫기'), 1);
      expect(lineCount(tester, '내보내기'), 1);
      expect(lineCount(tester, '편집'), 1);
    });

    testWidgets('내보내기 버튼이 터치하기 충분한 크기다', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      // 아이콘이 아니라 **누르는 영역**을 잰다.
      final button = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.ios_share),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.height, greaterThanOrEqualTo(48));
      expect(button.width, greaterThanOrEqualTo(48));
    });

    testWidgets('⭐ 왼쪽부터 닫기·내보내기·편집 순서다', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(x('닫기'), lessThan(x('내보내기')));
      expect(x('내보내기'), lessThan(x('편집')));
    });

    testWidgets('⭐ 작은 화면(320px)에서도 잘리지 않는다', (tester) async {
      await pumpAt(tester, 320, ContactDetailBottomBar(contact: makeContact()));
      expect(tester.takeException(), isNull);
      expect(lineCount(tester, '닫기'), 1);
      // 🚨 넘침 예외가 없다고 멀쩡한 게 아니다 — 좁으면 조용히 잘린다.
      expect(isClipped(tester, '내보내기'), isFalse);
      expect(isClipped(tester, '편집'), isFalse);
    });
  });

  group('🚨 폭 실측 — 판단이 아니라 잰 값', () {
    /// 처음엔 *"버튼이 셋이 되면 한글이 줄바꿈된다"* 고 보고 아이콘만 두려
    /// 했다. **틀렸다** — 아래 수치가 그것을 잡았다. 이 저장소는 계산이
    /// 틀린 경위를 결론만 고치고 지우지 않는다(CLAUDE.md 4절).
    ///
    /// 그러니 이 숫자가 바뀌면 **배치를 다시 판단해야 한다.**
    testWidgets('⭐ 390px 에서 버튼 폭과 글자 폭', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      final button = tester.getSize(
        find.ancestor(
          of: find.text('내보내기'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.width, closeTo(110, 1));
      // 아이콘(18) + 사이 간격(8) + 글자. 버튼 안에 여유가 남아야 한다.
      final label = tester.renderObject<RenderParagraph>(find.text('내보내기'));
      expect(label.size.width, closeTo(56.4, 1));
      expect(
        18 + 8 + label.size.width,
        lessThan(button.width),
        reason: '남는 폭이 없으면 글자가 조용히 잘린다',
      );
    });

    testWidgets('⭐ 세 라벨 모두 잘리지 않는다', (tester) async {
      await pumpAt(tester, 390, ContactDetailBottomBar(contact: makeContact()));
      expect(isClipped(tester, '닫기'), isFalse);
      expect(isClipped(tester, '내보내기'), isFalse);
      expect(isClipped(tester, '편집'), isFalse);
    });
  });
}
