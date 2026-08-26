// 같은 사람 판정 규칙 검증 (P1-40 확장, 2026-08-26 사용자 확정).
//
// 종전 판정은 휴대폰 칸끼리만 비교했다. 그런데 명함에는 이메일도 있고, 폰
// 주소록에서 가져오면 번호가 아예 없는 항목도 흔하다. 넓히면서 **넓히면 안
// 되는 자리**도 함께 못 박는다.
//
// 🚨 사용자 지적: "대표번호는 같은 사람이 많아서 안 돼."
//    회사 대표번호는 그 회사 사람 모두의 명함에 같이 인쇄된다. 그것으로
//    사람을 맞추면 남남을 같은 사람으로 본다. **중복을 놓치는 것보다 엉뚱한
//    사람을 합치라고 권하는 것이 더 나쁘다** — 전자는 두 건이 쌓일 뿐이지만
//    후자는 데이터를 섞는다.
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
}) {
  return ContactModel(
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
}

void main() {
  group('휴대폰 — 휴대폰끼리만 본다', () {
    test('같은 번호면 같은 사람으로 본다', () {
      final cards = [_card(id: 'a', phone: '010-1111-2222')];

      final hit = ContactsRepository.matchIn(cards, phone: '010-1111-2222');

      expect(hit?.contact.id, 'a');
      expect(hit?.field, DuplicateMatchField.mobile);
    });

    test('국가번호 표기가 달라도 같은 번호로 본다', () {
      // 뒤 9자리로 자르는 규칙의 근거. 여기가 깨지면 +82 표기가 섞였을 때
      // 같은 번호가 다른 번호로 읽힌다.
      final cards = [_card(id: 'a', phone: '010-1111-2222')];

      expect(
        ContactsRepository.matchIn(cards, phone: '+82 10 1111 2222')?.contact.id,
        'a',
      );
    });

    test('🚨 대표번호(사무실)는 판정에 쓰지 않는다', () {
      // 같은 회사 사람 둘이 같은 대표번호를 갖고 있다. 이 번호로 사람을
      // 맞추면 서로 중복으로 잡힌다.
      final cards = [
        _card(id: 'a', phone: '010-1111-0001', officePhone: '02-500-0000'),
        _card(id: 'b', phone: '010-1111-0002', officePhone: '02-500-0000'),
      ];

      expect(ContactsRepository.matchIn(cards, phone: '02-500-0000'), isNull);
    });

    test('직통 번호도 판정에 쓰지 않는다', () {
      final cards = [
        _card(id: 'a', phone: '010-1111-0001', directPhone: '02-500-1234'),
      ];

      expect(ContactsRepository.matchIn(cards, phone: '02-500-1234'), isNull);
    });

    test('휴대폰이 비어 있으면 번호로는 아무것도 걸리지 않는다', () {
      final cards = [_card(id: 'a', phone: '010-1111-2222')];

      expect(ContactsRepository.matchIn(cards, phone: ''), isNull);
    });
  });

  group('이메일 — 완전 일치, 다만 공용 주소는 뺀다', () {
    test('대소문자·앞뒤 공백이 달라도 같은 주소로 본다', () {
      final cards = [
        _card(id: 'a', phone: '010-1111-2222', email: 'hong@example.invalid'),
      ];

      final hit = ContactsRepository.matchIn(
        cards,
        phone: '010-9999-8888',
        email: '  HONG@Example.invalid ',
      );

      expect(hit?.contact.id, 'a');
      expect(hit?.field, DuplicateMatchField.email);
    });

    test('🚨 이미 명함 둘 이상에 쓰인 이메일은 개인 주소로 보지 않는다', () {
      // info@ 같은 공용 주소. 번호와 같은 이유로, 이것으로 맞추면 남남이 걸린다.
      final cards = [
        _card(id: 'a', phone: '010-1111-0001', email: 'info@example.invalid'),
        _card(id: 'b', phone: '010-1111-0002', email: 'info@example.invalid'),
      ];

      expect(
        ContactsRepository.matchIn(
          cards,
          phone: '',
          email: 'info@example.invalid',
        ),
        isNull,
      );
    });

    test('한 건에만 있는 주소는 그대로 걸린다 — 진짜 중복은 한 건이다', () {
      final cards = [
        _card(id: 'a', phone: '010-1111-0001', email: 'hong@example.invalid'),
        _card(id: 'b', phone: '010-1111-0002', email: 'kim@example.invalid'),
      ];

      expect(
        ContactsRepository.matchIn(
          cards,
          phone: '',
          email: 'hong@example.invalid',
        )?.contact.id,
        'a',
      );
    });
  });

  group('이름+회사 — 번호가 양쪽 다 없을 때만 보는 보조 축', () {
    test('번호도 이메일도 없으면 이름과 회사로 걸러 준다', () {
      final cards = [_card(id: 'a', name: '홍길동', company: '가상상사')];

      final hit = ContactsRepository.matchIn(
        cards,
        phone: '',
        name: '홍 길동',
        company: '가상상사',
      );

      expect(hit?.contact.id, 'a');
      expect(hit?.field, DuplicateMatchField.nameAndCompany);
    });

    test('🚨 번호가 있는데 안 맞았다면 이름이 같아도 뒤집지 않는다', () {
      // 여기가 동명이인이 갈리는 자리다. 번호가 다르다는 것은 "다른 사람"이라는
      // 신호이므로, 이름이 같다고 그 신호를 덮으면 안 된다.
      final cards = [
        _card(
          id: 'a',
          name: '홍길동',
          company: '가상상사',
          phone: '010-1111-0001',
        ),
      ];

      final hit = ContactsRepository.matchIn(
        cards,
        phone: '010-2222-0002',
        name: '홍길동',
        company: '가상상사',
      );

      expect(hit, isNull);
    });

    test('회사가 다르면 이름이 같아도 걸리지 않는다', () {
      final cards = [_card(id: 'a', name: '홍길동', company: '가상상사')];

      expect(
        ContactsRepository.matchIn(
          cards,
          phone: '',
          name: '홍길동',
          company: '다른상사',
        ),
        isNull,
      );
    });
  });

  group('편집 중인 자기 자신은 제외한다', () {
    test('excludeId 를 주면 그 명함과는 부딪히지 않는다', () {
      final cards = [_card(id: 'a', phone: '010-1111-2222')];

      expect(
        ContactsRepository.matchIn(
          cards,
          phone: '010-1111-2222',
          excludeId: 'a',
        ),
        isNull,
      );
    });
  });
}
