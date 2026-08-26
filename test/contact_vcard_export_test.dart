import 'package:connection_trace_ai_flutter/core/services/contact_export_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/vcard_util.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 명함을 폰 주소록으로 내보낼 때의 vCard(추가 492).
///
/// 여기서 지키려는 것 셋.
///
/// 1. 🚨 **메모는 나가지 않는다.** 이용자가 그 사람에 대해 적어 둔 사적인 글이고,
///    내보내기는 OS 공유 시트를 거쳐 **메신저로도 나간다.**
/// 2. 🚨 **값 안의 `;` `,` `\` 를 막는다.** 명함 값은 OCR 이 읽은 것이라 이 글자가
///    실제로 들어오고, 막지 않으면 연락처 앱에서 **회사명이 잘린다.**
/// 3. 내 명함 인코더와 **같은 구조**를 쓴다. 어긋나면 "내 걸 보낼 때와 남의 걸
///    보낼 때가 다른" 상태가 된다.
ContactModel makeContact({
  String name = '홍길동',
  String company = '가상상사',
  String title = '영업팀장',
  String? department,
  String phone = '010-0000-0001',
  String? officePhone,
  String? directPhone,
  String? fax,
  String email = 'example@example.invalid',
  String? website,
  String? address,
  String? addressDetail,
  String? postalCode,
  String? memo,
}) {
  return ContactModel(
    id: 'test-id',
    name: name,
    company: company,
    title: title,
    department: department,
    phone: phone,
    officePhone: officePhone,
    directPhone: directPhone,
    fax: fax,
    email: email,
    website: website,
    address: address,
    addressDetail: addressDetail,
    postalCode: postalCode,
    memo: memo,
    tags: const [],
    talkingPoints: const [],
  );
}

void main() {
  group('🚨 메모는 내보내지 않는다', () {
    test('⭐ memo 가 vCard 어디에도 안 들어간다', () {
      final v = VCardUtil.encodeContact(
        makeContact(memo: '골프 좋아함. 다음 주에 다시 연락할 것'),
      );
      expect(
        v.contains('골프'),
        isFalse,
        reason: '메모는 명함에 인쇄된 정보가 아니라 이용자가 만든 것이다. '
            '내보내기는 공유 시트를 거쳐 메신저로도 나가므로, 딸려 나가면 '
            '이용자가 의도하지 않은 것이 남에게 간다',
      );
      expect(v.contains('NOTE'), isFalse);
    });
  });

  group('🚨 값 안의 특수문자를 막는다', () {
    test('⭐ 회사명의 쉼표가 값 구분자로 읽히지 않는다', () {
      final v = VCardUtil.encodeContact(makeContact(company: '가나다, 주식회사'));
      expect(
        v,
        contains(r'ORG:가나다\, 주식회사'),
        reason: '막지 않으면 연락처 앱이 쉼표를 구분자로 읽어 회사명이 잘린다. '
            '명함 값은 OCR 이 읽은 것이라 쉼표가 실제로 들어온다',
      );
    });

    test('⭐ 세미콜론도 막는다', () {
      final v = VCardUtil.encodeContact(makeContact(title: '이사;대표'));
      expect(v, contains(r'TITLE:이사\;대표'));
    });

    test('⭐ 백슬래시를 먼저 막는다 — 나중에 하면 자기가 넣은 것을 또 막는다', () {
      final v = VCardUtil.encodeContact(makeContact(company: r'A\B'));
      expect(
        v,
        contains(r'ORG:A\\B'),
        reason: r'쉼표를 먼저 \, 로 바꾼 뒤 백슬래시를 막으면 \\, 가 되어 '
            '엉뚱한 값이 된다',
      );
    });

    test('줄바꿈은 vCard 의 \\n 으로 바꾼다', () {
      final v = VCardUtil.encodeContact(makeContact(company: '가상\n상사'));
      expect(v, contains(r'ORG:가상\n상사'));
      // 실제 줄바꿈이 값 안에 남으면 그 줄에서 vCard 가 끊긴다.
      expect(v.split('\n').where((l) => l.startsWith('ORG:')).length, 1);
    });
  });

  group('명함 항목이 제자리에 들어간다', () {
    test('직통·사무실 번호를 둘 다 담는다', () {
      final v = VCardUtil.encodeContact(
        makeContact(directPhone: '02-000-0001', officePhone: '02-000-0002'),
      );
      expect(v, contains('TEL;TYPE=WORK:02-000-0001'));
      expect(v, contains('TEL;TYPE=WORK:02-000-0002'));
    });

    test('부서는 ORG 의 두 번째 성분이다', () {
      final v = VCardUtil.encodeContact(makeContact(department: '영업본부'));
      expect(v, contains('ORG:가상상사;영업본부'));
    });

    test('우편번호는 ADR 의 여섯째 성분이다', () {
      final v = VCardUtil.encodeContact(
        makeContact(address: '서울시 강남구', addressDetail: '1층', postalCode: '06000'),
      );
      expect(v, contains('ADR;TYPE=WORK:;;서울시 강남구 1층;;;06000;'));
    });

    test('빈 항목은 줄 자체를 안 만든다', () {
      final v = VCardUtil.encodeContact(
        makeContact(company: '', title: '', email: ''),
      );
      expect(v.contains('ORG:'), isFalse);
      expect(v.contains('TITLE:'), isFalse);
      expect(v.contains('EMAIL:'), isFalse);
    });

    test('vCard 3.0 형식을 지킨다', () {
      final v = VCardUtil.encodeContact(makeContact());
      expect(v, startsWith('BEGIN:VCARD'));
      expect(v, contains('VERSION:3.0'));
      expect(v.trimRight(), endsWith('END:VCARD'));
    });
  });

  group('내보낸 vCard 를 다시 읽을 수 있다', () {
    test('⭐ 우리 파서가 우리 출력을 읽는다', () {
      final v = VCardUtil.encodeContact(makeContact());
      final parsed = VCardUtil.decode(v);
      expect(parsed, isNotNull);
      expect(parsed!['name'], '홍길동');
      expect(parsed['phone'], '010-0000-0001');
    });

    test('⭐ 쉼표 든 회사명이 왕복해도 원래대로 돌아온다', () {
      final v = VCardUtil.encodeContact(makeContact(company: '가나다, 주식회사'));
      expect(
        VCardUtil.decode(v)!['company'],
        '가나다, 주식회사',
        reason: '내 명함 QR 은 우리가 만들고 우리가 읽는다. 인코더에만 이스케이프를 '
            '넣고 디코더가 안 풀면 상대 기기에 백슬래시가 그대로 저장된다',
      );
    });

    test('⭐ 세미콜론 든 주소가 성분 구분자로 쪼개지지 않는다', () {
      final v = VCardUtil.encodeContact(makeContact(address: '서울시 강남구;1층'));
      expect(VCardUtil.decode(v)!['address'], contains('서울시 강남구;1층'));
    });

    test('백슬래시도 왕복한다', () {
      final v = VCardUtil.encodeContact(makeContact(company: r'A\B'));
      expect(VCardUtil.decode(v)!['company'], r'A\B');
    });

    test('직함의 쉼표도 왕복한다', () {
      final v = VCardUtil.encodeContact(makeContact(title: '이사, 대표'));
      expect(VCardUtil.decode(v)!['title'], '이사, 대표');
    });
  });

  group('파일 이름', () {
    test('이름을 그대로 쓴다 — 받는 사람이 무엇인지 알아야 한다', () {
      expect(vcardFileName('홍길동'), '홍길동.vcf');
    });

    test('⭐ 파일 이름으로 못 쓰는 글자를 걸러 낸다', () {
      expect(vcardFileName('홍/길:동*'), '홍길동.vcf');
    });

    test('⭐ 걸러 내고 비면 contact 로 떨어진다', () {
      expect(
        vcardFileName('///'),
        'contact.vcf',
        reason: '빈 파일 이름은 만들 수 없다. 이름이 전부 특수문자인 명함이 '
            '실제로 있을 수 있다',
      );
    });

    test('앞뒤 공백과 겹친 공백을 정리한다', () {
      expect(vcardFileName('  홍  길동  '), '홍 길동.vcf');
    });
  });
}
