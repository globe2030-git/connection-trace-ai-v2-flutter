// 같은 사람 판정 규칙 검증 (P1-40 → 2026-08-26 확장 → **2026-08-29 좁힘**, 추가 577).
//
// ## 규칙이 바뀌었다 — 「이름 + 휴대폰」이 기준이다
//
// 종전에는 셋이었다. ① 휴대폰만 같으면 ② 이메일 완전일치 ③ 양쪽 다 번호가
// 없을 때 이름+회사. 사용자가 **이름 + 휴대폰**으로 확정했다.
//
// ⭐ 얻는 것: **회사 대표번호를 함께 쓰는 두 사람이 더 이상 한 명으로 안 묶인다.**
//    지금까지 ①에 걸려 묶였고 실제로 흔한 경우였다.
//
// 🚨 잃는 것: **휴대폰이 없는 명함끼리는 검사가 아예 안 돈다.** 2026-08-26에
//    필수 조건이 「휴대폰·사무실 전화·이메일 중 하나」로 바뀌어 **휴대폰 없는
//    명함이 실제로 생긴다.** 그래서 B안으로 갔다 — 이름은 반드시 AND로 걸고,
//    휴대폰으로 판정할 수 없을 때만 사무실·직통·이메일을 본다.
//
// 📌 **대표번호 함정이 되살아나지 않는 이유**: 그 함정은 **번호만** 보고 묶어서
//    생겼다. 이름을 AND로 걸면 대표번호를 공유해도 이름이 다르면 안 묶인다.
//
// ⚠️ 표본으로는 "휴대폰 없는 명함이 얼마나 되나"를 못 쟀다 — 8/20 신규 95장은
//    **0장(0%)**인데, 그때는 휴대폰이 **단독 필수**여서 빈 채로 저장할 방법이
//    없었다. **재는 도구가 답을 미리 정해 놓은 표본**이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';

ContactModel _card({
  required String id,
  String name = '홍길동',
  String company = '가상상사',
  String phone = '',
  String? officePhone,
  String? directPhone,
  String email = '',
}) => ContactModel(
  id: id,
  name: name,
  company: company,
  title: '팀장',
  phone: phone,
  officePhone: officePhone,
  directPhone: directPhone,
  email: email,
  tags: const [],
  talkingPoints: const [],
);

DuplicateMatch? hit(
  List<ContactModel> list, {
  String name = '홍길동',
  String phone = '',
  String email = '',
  String? office,
  String? direct,
  String? excludeId,
}) => ContactsRepository.matchIn(
  list,
  name: name,
  phone: phone,
  email: email,
  officePhone: office,
  directPhone: direct,
  excludeId: excludeId,
);

void main() {
  group('⭐ 이름 + 휴대폰 — 확실한 중복', () {
    test('둘 다 같으면 중복이다', () {
      final m = hit([
        _card(id: 'c1', phone: '010-1234-5678'),
      ], phone: '010-1234-5678');
      expect(m?.contact.id, 'c1');
      expect(m?.field, DuplicateMatchField.nameAndMobile);
    });

    test('표기가 달라도 같은 번호로 본다', () {
      expect(
        hit([_card(id: 'c1', phone: '01012345678')], phone: '010-1234-5678')
            ?.contact
            .id,
        'c1',
      );
    });

    test('🚨 번호가 같아도 이름이 다르면 아니다 — 대표번호 함정을 막는 자리다', () {
      expect(
        hit(
          [_card(id: 'c1', name: '김철수', phone: '010-1234-5678')],
          name: '홍길동',
          phone: '010-1234-5678',
        ),
        isNull,
      );
    });

    test('이름이 같아도 휴대폰이 다르면 아니다 — 동명이인이 걸린다', () {
      expect(
        hit([_card(id: 'c1', phone: '010-1111-1111')], phone: '010-2222-2222'),
        isNull,
      );
    });

    test('자기 자신은 제외한다(편집 중)', () {
      expect(
        hit(
          [_card(id: 'c1', phone: '010-1234-5678')],
          phone: '010-1234-5678',
          excludeId: 'c1',
        ),
        isNull,
      );
    });
  });

  group('🚨 휴대폰이 없을 때 — 이름 + 사무실·직통·이메일 (확신이 낮다)', () {
    test('사무실 번호가 같으면 걸린다', () {
      final m = hit(
        [_card(id: 'c1', officePhone: '02-111-2222')],
        office: '02-111-2222',
      );
      expect(m?.contact.id, 'c1');
      expect(m?.field, DuplicateMatchField.nameAndOtherContact);
    });

    test('이메일이 같으면 걸린다', () {
      expect(
        hit([_card(id: 'c1', email: 'a@b.com')], email: 'a@b.com')?.field,
        DuplicateMatchField.nameAndOtherContact,
      );
    });

    test('직통이 상대의 사무실과 같아도 걸린다 — 칸을 가리지 않는다', () {
      expect(
        hit([_card(id: 'c1', officePhone: '02-111-2222')], direct: '02-111-2222')
            ?.contact
            .id,
        'c1',
      );
    });

    test('🚨 양쪽 다 휴대폰이 있는데 안 맞았으면 약한 축으로 뒤집지 않는다', () {
      expect(
        hit(
          [
            _card(
              id: 'c1',
              phone: '010-1111-1111',
              officePhone: '02-111-2222',
            ),
          ],
          phone: '010-2222-2222',
          office: '02-111-2222',
        ),
        isNull,
        reason: '휴대폰이 다르다는 것은 "다른 사람"이라는 신호다',
      );
    });

    test('이름이 다르면 사무실이 같아도 아니다 — 대표번호를 함께 쓰는 남남', () {
      expect(
        hit(
          [_card(id: 'c1', name: '김철수', officePhone: '02-111-2222')],
          name: '홍길동',
          office: '02-111-2222',
        ),
        isNull,
      );
    });

    test('⭐ 확실한 쪽이 있으면 그것을 먼저 돌려준다', () {
      final m = hit(
        [
          _card(id: '약함', officePhone: '02-111-2222'),
          _card(id: '확실', phone: '010-1234-5678'),
        ],
        phone: '010-1234-5678',
        office: '02-111-2222',
      );
      expect(m?.contact.id, '확실');
      expect(m?.field, DuplicateMatchField.nameAndMobile);
    });
  });

  group('이름이 없으면 아무것도 못 한다', () {
    test('이름 칸이 비면 검사하지 않는다', () {
      expect(
        hit([_card(id: 'c1', phone: '010-1234-5678')], name: '', phone: '010-1234-5678'),
        isNull,
      );
    });
  });

  group('🚨 「중복이 없다」와 「검사를 못 했다」를 가른다', () {
    test('이름과 연락 수단이 하나라도 있으면 검사할 수 있다', () {
      expect(
        ContactsRepository.canCheckDuplicate(name: '홍길동', phone: '010-1234-5678'),
        isTrue,
      );
      expect(
        ContactsRepository.canCheckDuplicate(name: '홍길동', officePhone: '02-1-2'),
        isTrue,
      );
      expect(
        ContactsRepository.canCheckDuplicate(name: '홍길동', email: 'a@b.com'),
        isTrue,
      );
    });

    test('이름이 없으면 못 한다', () {
      expect(
        ContactsRepository.canCheckDuplicate(name: '', phone: '010-1234-5678'),
        isFalse,
      );
    });

    test('연락 수단이 하나도 없으면 못 한다 — 화면이 그렇게 말해야 한다', () {
      expect(ContactsRepository.canCheckDuplicate(name: '홍길동'), isFalse);
    });
  });
}
