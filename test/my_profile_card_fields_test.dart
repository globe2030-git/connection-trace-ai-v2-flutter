// 내 명함이 명함 스캔 결과를 **버리지 않고 받는지** 검증.
//
// 2026-08-26 추가. 스캔 자체는 예전부터 돌고 있었는데, 내 명함 화면에
// 부서·사무실 전화·팩스·웹사이트·우편번호를 담을 칸이 없어서 **OCR이 읽고도
// 그대로 버려졌다**(사용자 지적). 화면을 봐서는 "스캔이 잘 안 되네"로 보이지
// 결함으로 보이지 않는 종류라, 모델이 그 값을 실제로 싣고 다니는지를 코드
// 레벨에 고정해 둔다.
//
// 함께 지키는 것: 이 다섯은 **나중에 생긴 칸**이라, 그 전에 저장된 프로필을
// 열었을 때 깨지지 않아야 한다(마이그레이션 없이 null로 읽힌다).
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/vcard_util.dart';
import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';

void main() {
  const full = MyProfileModel(
    name: '홍길동',
    title: '팀장',
    company: '커넥션하우스',
    phone: '010-1234-5678',
    email: 'hong@example.com',
    address: '서울특별시 강남구 테헤란로 123',
    department: '영업본부',
    officePhone: '02-1234-5678',
    fax: '02-1234-5679',
    website: 'https://example.com',
    addressDetail: '5층 501호',
    postalCode: '06134',
  );

  group('나중에 생긴 다섯 칸이 저장·복원을 왕복한다', () {
    test('toJson → fromJson 으로 값이 그대로 돌아온다', () {
      final restored = MyProfileModel.fromJson(full.toJson());

      expect(restored.department, '영업본부');
      expect(restored.officePhone, '02-1234-5678');
      expect(restored.fax, '02-1234-5679');
      expect(restored.website, 'https://example.com');
      expect(restored.postalCode, '06134');
    });

    test('그 전에 저장된 프로필(키가 아예 없음)은 null 로 읽힌다', () {
      // 마이그레이션을 두지 않은 근거다 — 없는 키를 읽어도 예외가 아니라
      // null 이어야 한다. 여기가 깨지면 예전 이용자의 프로필이 안 열린다.
      final old = MyProfileModel.fromJson({
        'name': '홍길동',
        'title': '팀장',
        'company': '커넥션하우스',
        'phone': '010-1234-5678',
        'email': 'hong@example.com',
        'address': '서울특별시 강남구 테헤란로 123',
      });

      expect(old.name, '홍길동');
      expect(old.department, isNull);
      expect(old.officePhone, isNull);
      expect(old.fax, isNull);
      expect(old.website, isNull);
      expect(old.postalCode, isNull);
    });

    test('copyWith 가 다섯을 흘리지 않는다', () {
      final changed = full.copyWith(title: '이사');

      expect(changed.title, '이사');
      expect(changed.department, '영업본부');
      expect(changed.officePhone, '02-1234-5678');
      expect(changed.fax, '02-1234-5679');
      expect(changed.website, 'https://example.com');
      expect(changed.postalCode, '06134');
    });
  });

  group('QR(vCard)로 내보낼 때도 함께 나간다', () {
    test('부서는 ORG 의 두 번째 성분으로 나간다', () {
      expect(VCardUtil.encodeProfile(full), contains('ORG:커넥션하우스;영업본부'));
    });

    test('부서가 없으면 ORG 에 세미콜론을 붙이지 않는다', () {
      final noDept = full.copyWith().toJson()..remove('department');
      final profile = MyProfileModel.fromJson(noDept);

      expect(VCardUtil.encodeProfile(profile), contains('ORG:커넥션하우스\n'));
    });

    test('사무실 전화·팩스·웹사이트가 각자 줄로 나간다', () {
      final vcard = VCardUtil.encodeProfile(full);

      expect(vcard, contains('TEL;TYPE=CELL:010-1234-5678'));
      expect(vcard, contains('TEL;TYPE=WORK:02-1234-5678'));
      expect(vcard, contains('TEL;TYPE=FAX:02-1234-5679'));
      expect(vcard, contains('URL:https://example.com'));
    });

    test('우편번호는 ADR 의 여섯째 성분 자리에 들어간다', () {
      // ADR 순서: 사서함;확장;거리;시;도;우편번호;국가.
      // 자리를 틀리면 상대 폰 연락처에 우편번호가 "도"로 들어간다.
      expect(
        VCardUtil.encodeProfile(full),
        contains('ADR;TYPE=WORK:;;서울특별시 강남구 테헤란로 123 5층 501호;;;06134;'),
      );
    });

    test('선택 항목이 비어 있으면 그 줄 자체를 만들지 않는다', () {
      const minimal = MyProfileModel(
        name: '홍길동',
        title: '팀장',
        company: '커넥션하우스',
        phone: '010-1234-5678',
        email: 'hong@example.com',
        address: '서울특별시 강남구 테헤란로 123',
      );
      final vcard = VCardUtil.encodeProfile(minimal);

      // ⚠️ `TYPE=WORK`만 보면 안 된다 — 주소 줄(`ADR;TYPE=WORK:`)이 같은
      // 표시를 쓴다. 전화 줄인지까지 봐야 한다.
      expect(vcard, isNot(contains('TEL;TYPE=WORK:')));
      expect(vcard, isNot(contains('TYPE=FAX')));
      expect(vcard, isNot(contains('URL:')));
    });
  });
}
