import 'package:connection_trace_ai_flutter/core/utils/contact_export_name.dart';
import 'package:connection_trace_ai_flutter/core/utils/vcard_util.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 주소록 이름 칸 형식(추가 494).
///
/// 리멤버 설정 실물(2026-08-26, 사용자 촬영본 43프레임 전수 확인)에서 구분에
/// 실제로 쓰이는 장치가 이것이었다 — 이름 칸에 직책·회사를 함께 넣어
/// **동명이인을 가르고, 내가 넣은 것인지 이름만 보고 알게** 한다.
///
/// 여기서 지키는 것은 **빈 값이 껍데기를 남기지 않는 것**이다. 주소록에 한 번
/// 들어가면 이용자가 손으로 고쳐야 한다.
ContactModel c({
  String name = '홍길동',
  String title = '부장',
  String company = '가상상사',
}) =>
    ContactModel(
      id: 'id',
      name: name,
      company: company,
      title: title,
      phone: '010-0000-0001',
      email: 'example@example.invalid',
      tags: const [],
      talkingPoints: const [],
    );

void main() {
  const only = ContactExportNameFormat.nameOnly;
  const withTitle = ContactExportNameFormat.nameTitle;
  const withBoth = ContactExportNameFormat.nameTitleCompany;
  const withCompany = ContactExportNameFormat.nameCompany;

  group('형식대로 만든다', () {
    test('네 형식', () {
      expect(buildExportName(c(), only), '홍길동');
      expect(buildExportName(c(), withTitle), '홍길동 부장');
      expect(buildExportName(c(), withBoth), '홍길동 부장(가상상사)');
      expect(buildExportName(c(), withCompany), '홍길동(가상상사)');
    });
  });

  group('🚨 빈 값이 껍데기를 남기지 않는다', () {
    test('⭐ 직책이 없으면 그 자리째 뺀다 — 공백이 둘 남지 않는다', () {
      expect(
        buildExportName(c(title: ''), withBoth),
        '홍길동(가상상사)',
        reason: '"홍길동  (가상상사)" 처럼 공백이 둘 남으면 주소록에 그대로 '
            '들어가고, 이용자가 손으로 고쳐야 한다',
      );
      expect(buildExportName(c(title: ''), withTitle), '홍길동');
    });

    test('⭐ 회사명이 없으면 괄호를 안 붙인다', () {
      expect(
        buildExportName(c(company: ''), withBoth),
        '홍길동 부장',
        reason: '"홍길동 부장()" 이 되면 안 된다',
      );
      expect(buildExportName(c(company: ''), withCompany), '홍길동');
    });

    test('⭐ 직책도 회사도 없으면 이름만 남는다', () {
      expect(buildExportName(c(title: '', company: ''), withBoth), '홍길동');
    });

    test('공백뿐인 값도 없는 것으로 본다', () {
      expect(buildExportName(c(title: '   '), withBoth), '홍길동(가상상사)');
      expect(buildExportName(c(company: '  '), withCompany), '홍길동');
    });

    test('이름이 없으면 아무것도 붙이지 않는다', () {
      expect(
        buildExportName(c(name: ''), withBoth),
        '',
        reason: '이름이 없는데 "(가상상사)" 만 있는 연락처가 생기면 안 된다',
      );
    });
  });

  group('🚨 기본값은 이름만', () {
    test('⭐ enum 의 첫 값이 이름만이다', () {
      expect(
        ContactExportNameFormat.values.first,
        ContactExportNameFormat.nameOnly,
        reason: '주소록은 이용자의 것이고, 이름을 건드리는 쪽이 더 큰 개입이다',
      );
    });

    test('⭐ 저장된 값이 없으면 이름만으로 떨어진다', () {
      expect(ContactExportNameFormat.fromStorage(null), only);
    });

    test('⭐ 모르는 값이어도 이름만으로 떨어진다', () {
      expect(ContactExportNameFormat.fromStorage('알 수 없는 값'), only);
    });

    test('vCard 도 형식을 안 넘기면 이름만이다', () {
      expect(VCardUtil.encodeContact(c()), contains('FN:홍길동\n'));
    });
  });

  group('기기에 적는 값', () {
    test('⭐ enum 이름이 아니라 고정 문자열을 쓴다 — 왕복한다', () {
      for (final f in ContactExportNameFormat.values) {
        expect(ContactExportNameFormat.fromStorage(f.storageKey), f);
      }
    });

    test('저장 문자열은 이 목록에서 바뀌면 안 된다', () {
      expect(
        ContactExportNameFormat.values.map((f) => f.storageKey).toList(),
        ['name_only', 'name_title', 'name_title_company', 'name_company'],
        reason: '바꾸면 이미 저장된 설정이 이름만으로 떨어진다',
      );
    });
  });

  group('vCard 에 실린다', () {
    test('⭐ FN 과 N 둘 다에 넣는다 — 표시 필드가 앱마다 다르다', () {
      final v = VCardUtil.encodeContact(c(), nameFormat: withBoth);
      expect(v, contains('FN:홍길동 부장(가상상사)'));
      expect(v, contains('N:;홍길동 부장(가상상사);;;'));
    });

    test('⭐ TITLE·ORG 는 그대로 남는다 — 이름 칸에 합친 것과 별개다', () {
      final v = VCardUtil.encodeContact(c(), nameFormat: withBoth);
      expect(v, contains('TITLE:부장'));
      expect(v, contains('ORG:가상상사'));
    });

    test('⭐ 이름에 든 쉼표가 이름 칸 합치기 뒤에도 막힌다', () {
      final v = VCardUtil.encodeContact(
        c(company: '가나다, 주식회사'),
        nameFormat: withCompany,
      );
      expect(v, contains(r'FN:홍길동(가나다\, 주식회사)'));
      // 왕복해도 원래대로 돌아온다.
      expect(VCardUtil.decode(v)!['name'], '홍길동(가나다, 주식회사)');
    });
  });

  group('미리보기', () {
    test('네 형식이 모두 다르게 보인다 — 무엇을 고르는지 알 수 있어야 한다', () {
      final previews =
          ContactExportNameFormat.values.map(previewOf).toSet();
      expect(previews.length, ContactExportNameFormat.values.length);
    });

    test('⭐ 미리보기는 가상값이다', () {
      for (final f in ContactExportNameFormat.values) {
        expect(previewOf(f), startsWith('홍길동'));
      }
    });
  });
}
