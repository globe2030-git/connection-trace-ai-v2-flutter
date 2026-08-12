import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';

/// **명함 이미지 경로 일괄 재연결** 테스트(작업 #6).
///
/// 배경: `cardImagePath`는 서버 백업 JSON에 담기지 않는다(다른 기기에선
/// 무의미한 로컬 경로라서 — `contact_model.dart`가 좌표와 같은 `includeGeo`
/// 플래그를 재사용). 그래서 서버 복원/다기기 병합이 로컬 명함 목록을
/// 덮어쓰면 경로만 유실되고, 기기에 저장된 암호문 파일
/// (`contact_card_<id>.enc`)은 그대로 남는다 — 연결 고리만 끊긴다.
///
/// 실기기 파일시스템 없이 돌아야 하므로 [ContactImageService]는 가짜로
/// 주입한다(디렉터리 조회 1회를 흉내 내고 호출 횟수를 센다).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ContactModel contact({required String id, String? cardImagePath}) =>
      ContactModel(
        id: id,
        name: '테스트$id',
        company: '회사',
        title: '직함',
        phone: '010-0000-0000',
        email: 'a@b.c',
        tags: const [],
        talkingPoints: const [],
        cardImagePath: cardImagePath,
      );

  group('순수 매칭 로직 — ContactsRepository.relinkCardImagePaths', () {
    test('⭐ 경로 없는 명함 + 기기 파일 존재 → 연결된다', () {
      final result = ContactsRepository.relinkCardImagePaths(
        [contact(id: 'c1')],
        {'c1': '/docs/contact_card_c1.enc'},
      );
      expect(result.single.cardImagePath, '/docs/contact_card_c1.enc');
    });

    test('파일이 없는 명함은 null을 유지한다(이미지 없이 등록한 명함)', () {
      final result = ContactsRepository.relinkCardImagePaths(
        [contact(id: 'c1')],
        {'c2': '/docs/contact_card_c2.enc'},
      );
      expect(result.single.cardImagePath, isNull);
    });

    test('이미 경로가 있는 명함은 맵에 다른 값이 있어도 덮어쓰지 않는다', () {
      final result = ContactsRepository.relinkCardImagePaths(
        [contact(id: 'c1', cardImagePath: '/local/original.enc')],
        {'c1': '/docs/contact_card_c1.enc'},
      );
      expect(result.single.cardImagePath, '/local/original.enc');
    });

    test('여러 명함 중 매칭되는 것만 골라 연결한다', () {
      final result = ContactsRepository.relinkCardImagePaths(
        [contact(id: 'c1'), contact(id: 'c2'), contact(id: 'c3')],
        {'c1': '/docs/contact_card_c1.enc', 'c3': '/docs/contact_card_c3.enc'},
      );
      final byId = {for (final c in result) c.id: c.cardImagePath};
      expect(byId['c1'], '/docs/contact_card_c1.enc');
      expect(byId['c2'], isNull);
      expect(byId['c3'], '/docs/contact_card_c3.enc');
    });
  });

  group('ContactsRepository.relinkMissingCardImagePaths(로드 공통 지점에서 부르는 대상)', () {
    void seedLocalContacts(List<ContactModel> contacts) {
      SharedPreferences.setMockInitialValues({
        'saved_contacts_v2': '[${contacts.map(_json).join(',')}]',
      });
    }

    test('게스트(uid 없음)는 재연결을 시도하지 않는다', () async {
      // 명함 이미지는 저장 시점에 uid 기반 키가 있어야만 만들어지므로
      // (add_card_modal_view.dart), 게스트 상태에서 암호문 파일이 존재할
      // 수 없다 — 디렉터리 조회 자체를 건너뛰어야 한다.
      seedLocalContacts([contact(id: 'c1')]);
      final fakeImages = _FakeContactImageService({
        'c1': '/docs/contact_card_c1.enc',
      });
      final repo = ContactsRepository(contactImageService: fakeImages);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final changed = await repo.relinkMissingCardImagePaths();

      expect(changed, isFalse);
      expect(repo.contacts.single.cardImagePath, isNull);
      expect(fakeImages.callCount, 0);
    });

    test(
      '⭐ 로그인 상태에서 경로 없는 명함이 기기 파일과 재연결된다',
      () async {
        seedLocalContacts([contact(id: 'c1')]);
        final fakeImages = _FakeContactImageService({
          'c1': '/docs/contact_card_c1.enc',
        });
        final repo = ContactsRepository(contactImageService: fakeImages);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await repo.setCurrentUid('uid_test');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final changed = await repo.relinkMissingCardImagePaths();

        expect(changed, isTrue);
        expect(repo.contacts.single.cardImagePath, '/docs/contact_card_c1.enc');
      },
    );

    test('경로 없는 명함이 하나도 없으면 디렉터리 조회 자체를 건너뛴다(성능)', () async {
      seedLocalContacts([contact(id: 'c1', cardImagePath: '/local/a.enc')]);
      final fakeImages = _FakeContactImageService({});
      final repo = ContactsRepository(contactImageService: fakeImages);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final changed = await repo.relinkMissingCardImagePaths();

      expect(changed, isFalse);
      expect(fakeImages.callCount, 0);
    });

    test('기기에 파일이 하나도 없으면(빈 맵) 변경 없이 끝난다', () async {
      seedLocalContacts([contact(id: 'c1')]);
      final fakeImages = _FakeContactImageService({});
      final repo = ContactsRepository(contactImageService: fakeImages);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final changed = await repo.relinkMissingCardImagePaths();

      expect(changed, isFalse);
      expect(repo.contacts.single.cardImagePath, isNull);
    });
  });
}

/// 가짜 명함 이미지 서비스 — 실제 파일시스템 대신 미리 정해 둔
/// `contactId → 경로` 맵을 돌려주고, 조회가 몇 번 일어났는지 센다(성능
/// 회귀 방지: "경로 없는 명함이 없으면 조회 자체를 건너뛴다"를 검증하는 데 씀).
class _FakeContactImageService extends ContactImageService {
  _FakeContactImageService(this._existing);
  final Map<String, String> _existing;
  int callCount = 0;

  @override
  Future<Map<String, String>> findAllExistingCardImagePaths() async {
    callCount++;
    return _existing;
  }
}

/// 테스트용 최소 직렬화 — 레거시 평문 저장 형식을 흉내 낸다
/// (contacts_repository_wiring_test.dart와 동일한 패턴).
String _json(ContactModel c) {
  final json = c.toJson();
  final entries = json.entries.map((e) {
    final v = e.value;
    if (v == null) return '"${e.key}":null';
    if (v is num) return '"${e.key}":$v';
    if (v is bool) return '"${e.key}":$v';
    if (v is List) return '"${e.key}":[]';
    return '"${e.key}":"${v.toString().replaceAll('"', r'\"')}"';
  });
  return '{${entries.join(',')}}';
}
