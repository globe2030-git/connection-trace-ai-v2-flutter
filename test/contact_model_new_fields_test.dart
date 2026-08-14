// 명함 필드 추가(직통·팩스·웹사이트)의 **저장·복원·마이그레이션**을 고정한다.
//
// 이 세 필드는 서버 백업(toBackupJson)까지 흘러가므로(좌표·명함이미지와 달리
// 파생/기기종속이 아니라 동기화 대상), 저장 형태가 바뀌면 다기기에서 값이
// 사라질 수 있다. 아래 테스트가 그 계약을 코드로 박아 둔다.
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel _base({
  String? directPhone,
  String? fax,
  String? website,
}) => ContactModel(
  id: 'c1',
  name: '홍길동',
  company: '테스트',
  title: '담당자',
  phone: '010-1234-5678',
  email: 'a@b.com',
  tags: const ['신규'],
  talkingPoints: const [],
  directPhone: directPhone,
  fax: fax,
  website: website,
);

void main() {
  group('명함 필드 추가 — 직통·팩스·웹사이트', () {
    test('toJson(기기)에 세 필드가 들어간다', () {
      final j = _base(
        directPhone: '02-100-2000',
        fax: '02-100-2001',
        website: 'www.test.com',
      ).toJson();
      expect(j['directPhone'], '02-100-2000');
      expect(j['fax'], '02-100-2001');
      expect(j['website'], 'www.test.com');
    });

    test('⭐ toBackupJson(서버)에도 들어간다 — 좌표와 달리 동기화 대상', () {
      final j = _base(
        directPhone: '02-100-2000',
        fax: '02-100-2001',
        website: 'www.test.com',
      ).toBackupJson();
      expect(j['directPhone'], '02-100-2000');
      expect(j['fax'], '02-100-2001');
      expect(j['website'], 'www.test.com');
    });

    test('fromJson이 세 필드를 복원한다(라운드트립)', () {
      final original = _base(
        directPhone: '02-100-2000',
        fax: '02-100-2001',
        website: 'www.test.com',
      );
      final restored = ContactModel.fromJson(original.toJson());
      expect(restored.directPhone, '02-100-2000');
      expect(restored.fax, '02-100-2001');
      expect(restored.website, 'www.test.com');
    });

    test('⭐ 마이그레이션 — 세 키가 없는 예전 데이터는 null로(무손실)', () {
      final legacy = {
        'id': 'old',
        'name': '김철수',
        'company': '옛회사',
        'title': '부장',
        'phone': '010-0000-0000',
        'email': 'x@y.com',
        'tags': <String>[],
        'talkingPoints': <String>[],
        // directPhone/fax/website 없음 — 필드 추가 이전 저장분
      };
      final c = ContactModel.fromJson(legacy);
      expect(c.directPhone, isNull);
      expect(c.fax, isNull);
      expect(c.website, isNull);
      // 기존 필드는 멀쩡히 복원된다.
      expect(c.name, '김철수');
      expect(c.phone, '010-0000-0000');
    });

    test('copyWith가 세 필드를 전달·유지한다', () {
      final c = _base(directPhone: '02-1', fax: '02-2', website: 'w');
      final unchanged = c.copyWith(name: '이영희');
      expect(unchanged.directPhone, '02-1');
      expect(unchanged.fax, '02-2');
      expect(unchanged.website, 'w');

      final changed = c.copyWith(website: 'new.com');
      expect(changed.website, 'new.com');
      expect(changed.directPhone, '02-1');
    });
  });
}
