import 'package:connection_trace_ai_flutter/core/utils/vcard_util.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/contact_export_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 내보내기 확인 창(추가 492).
///
/// 여기서 지키는 것은 하나다 — **적힌 것과 실제로 나가는 것이 같아야 한다.**
/// 없는 항목을 적으면 거짓말이고, 나가는 항목을 빠뜨리면 이용자가 모른 채
/// 내보낸다.
ContactModel c({
  String name = '홍길동',
  String company = '가상상사',
  String title = '영업팀장',
  String phone = '010-0000-0001',
  String? officePhone,
  String email = 'example@example.invalid',
  String? address,
  String? website,
  String? fax,
  String? memo,
}) =>
    ContactModel(
      id: 'id',
      name: name,
      company: company,
      title: title,
      phone: phone,
      officePhone: officePhone,
      email: email,
      address: address,
      website: website,
      fax: fax,
      memo: memo,
      tags: const [],
      talkingPoints: const [],
    );

void main() {
  group('🚨 담기는 항목은 실제로 값이 있는 것만', () {
    test('⭐ 이메일이 없으면 "이메일"을 적지 않는다', () {
      expect(
        ContactExportConfirmDialog.itemsOf(c(email: '')),
        isNot(contains('이메일')),
        reason: '없는 것을 적으면 거짓말이다. 이 저장소는 화면을 채우려고 '
            '없는 것을 만들지 않는다',
      );
    });

    test('⭐ 공백뿐인 값도 없는 것으로 본다', () {
      expect(ContactExportConfirmDialog.itemsOf(c(email: '   ')),
          isNot(contains('이메일')));
    });

    test('휴대폰이 없어도 사무실 번호가 있으면 "전화번호"를 적는다', () {
      expect(
        ContactExportConfirmDialog.itemsOf(c(phone: '', officePhone: '02-000-0001')),
        contains('전화번호'),
      );
    });

    test('주소·홈페이지·팩스는 있을 때만 나온다', () {
      expect(ContactExportConfirmDialog.itemsOf(c()), isNot(contains('주소')));
      expect(
        ContactExportConfirmDialog.itemsOf(c(address: '서울시 강남구')),
        contains('주소'),
      );
      expect(
        ContactExportConfirmDialog.itemsOf(c(website: 'example.invalid')),
        contains('홈페이지'),
      );
      expect(ContactExportConfirmDialog.itemsOf(c(fax: '02-000-9999')),
          contains('팩스'));
    });

    test('⭐ 메모는 목록에 없다 — 내보내지 않기 때문이다', () {
      expect(
        ContactExportConfirmDialog.itemsOf(c(memo: '골프 좋아함')),
        isNot(contains('메모')),
      );
    });
  });

  group('🚨 적힌 것과 실제로 나가는 것이 같다', () {
    /// 확인 창의 목록과 [VCardUtil.encodeContact] 가 따로 놀면, 창은
    /// *"이메일이 담깁니다"* 라고 하는데 파일에는 없는 상태가 된다. 둘을
    /// 묶어 둔다.
    void checkPair(ContactModel contact) {
      final items = ContactExportConfirmDialog.itemsOf(contact);
      final vcard = VCardUtil.encodeContact(contact);
      expect(items.contains('이메일'), vcard.contains('EMAIL:'),
          reason: '이메일');
      expect(items.contains('주소'), vcard.contains('ADR;'), reason: '주소');
      expect(items.contains('홈페이지'), vcard.contains('URL:'), reason: '홈페이지');
      expect(items.contains('팩스'), vcard.contains('TYPE=FAX'), reason: '팩스');
      expect(items.contains('전화번호'), vcard.contains('TEL;'), reason: '전화번호');
    }

    test('⭐ 다 있는 명함', () {
      checkPair(c(
        address: '서울시 강남구',
        website: 'example.invalid',
        fax: '02-000-9999',
      ));
    });

    test('⭐ 연락처가 이름뿐인 명함', () {
      checkPair(c(company: '', title: '', phone: '', email: ''));
    });

    test('⭐ 사무실 번호만 있는 명함', () {
      checkPair(c(phone: '', email: '', officePhone: '02-000-0001'));
    });
  });

  group('화면', () {
    Future<bool?> open(WidgetTester tester, ContactModel contact) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result =
                        await ContactExportConfirmDialog.show(context, contact);
                  },
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('이름을 넣어 누구를 저장하는지 보여 준다', (tester) async {
      await open(tester, c());
      expect(find.textContaining('홍길동'), findsOneWidget);
    });

    testWidgets('이름이 비어 있어도 문장이 깨지지 않는다', (tester) async {
      await open(tester, c(name: ''));
      expect(find.text('이 명함을 연락처에 저장할까요?'), findsOneWidget);
    });

    testWidgets('⭐ 메모가 빠진다는 것을 말해 준다', (tester) async {
      await open(tester, c(memo: '골프 좋아함'));
      expect(
        find.text('메모는 담기지 않습니다.'),
        findsOneWidget,
        reason: '말하지 않으면 나갔다고 오해할 수 있다',
      );
      // 메모 내용 자체는 절대 보이면 안 된다.
      expect(find.textContaining('골프'), findsNothing);
    });

    testWidgets('⭐ 취소하면 false — 공유 시트가 뜨지 않는다', (tester) async {
      await open(tester, c());
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      // show() 는 null 을 false 로 바꿔 돌려준다.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('계속을 누르면 창이 닫힌다', (tester) async {
      await open(tester, c());
      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
