import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/core/services/address_geocoding_service.dart';
import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';

/// **배선 테스트** — "A가 B를 실제로 부르는가"를 확인한다.
///
/// 왜 필요한가(backlog 추가 79, P1-28): `GeoBackfillService`에 "명함별 3회까지
/// 재시도" 장치를 만들고 단위 테스트 10건으로 고정했는데, 정작 그것을 **부르는
/// 쪽**이 복원 경로에만 있었다. 복원은 로컬이 비어 있을 때만 일어나므로, 한 번
/// 실패한 명함은 영영 재시도되지 않고 주변 인맥 목록에서 조용히 빠진 채 남았다.
///
/// 서비스 단위 테스트는 전부 초록불이었다. 서비스의 계약은 맞았고 그것을 부르는
/// 쪽이 없었을 뿐이다. **그 구멍이 이 파일이 메우는 자리다.**
///
/// 실기기·서버 없이 돌아야 하므로 지오코딩은 가짜 함수로 주입한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 호출 여부를 셀 수 있는 가짜 지오코더.
  ({GeoBackfillService service, List<String> calls}) fakeBackfill({
    bool succeed = true,
  }) {
    final calls = <String>[];
    final service = GeoBackfillService(
      gapBetweenRequests: Duration.zero,
      geocode: (address) async {
        calls.add(address);
        return succeed
            ? const AddressValidationResult(
                isValid: true,
                originalAddress: 'x',
                geoPosition: GeoPosition(lat: 37.5, lng: 127.0),
              )
            : const AddressValidationResult(
                isValid: false,
                originalAddress: 'x',
                message: '위치를 찾을 수 없는 주소입니다.',
              );
      },
    );
    return (service: service, calls: calls);
  }

  ContactModel contact({required String id, String? address, GeoPosition? geo}) =>
      ContactModel(
        id: id,
        name: '테스트$id',
        company: '회사',
        title: '직함',
        phone: '010-0000-0000',
        email: 'a@b.c',
        address: address,
        geo: geo,
        tags: const [],
        talkingPoints: const [],
      );

  /// 로그인 전(uid 없음) 상태로 평문 명함을 심어 둔다. 리포지토리가 이걸
  /// 읽어들이므로, 로그인 시점의 동작을 서버 없이 확인할 수 있다.
  void seedLocalContacts(List<ContactModel> contacts) {
    SharedPreferences.setMockInitialValues({
      'saved_contacts_v2':
          '[${contacts.map((c) => _json(c)).join(',')}]',
    });
  }

  group('좌표 재계산이 실제로 호출되는가', () {
    test('⭐ 로그인하면 좌표가 빈 명함의 재계산이 시작된다', () async {
      // 추가 79의 회귀 방지. 예전에는 복원 경로에서만 불러서, 복원이 다시
      // 일어나지 않으면 재시도가 영영 돌지 않았다.
      seedLocalContacts([contact(id: 'c1', address: '서울 중구 세종대로 110')]);
      final fake = fakeBackfill();
      final repo = ContactsRepository(geoBackfillService: fake.service);
      await Future<void>.delayed(Duration.zero);

      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        fake.calls,
        ['서울 중구 세종대로 110'],
        reason: 'setCurrentUid가 backfillMissingGeo를 불러야 한다',
      );
    });

    test('좌표가 이미 있으면 지오코딩하지 않는다', () async {
      seedLocalContacts([
        contact(
          id: 'c1',
          address: '서울 중구 세종대로 110',
          geo: const GeoPosition(lat: 1, lng: 2),
        ),
      ]);
      final fake = fakeBackfill();
      final repo = ContactsRepository(geoBackfillService: fake.service);
      await Future<void>.delayed(Duration.zero);

      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.calls, isEmpty, reason: '불필요한 지오코딩은 하지 않아야 한다');
    });

    test('재계산에 성공하면 명함에 좌표가 채워진다', () async {
      seedLocalContacts([contact(id: 'c1', address: '서울 중구 세종대로 110')]);
      final fake = fakeBackfill();
      final repo = ContactsRepository(geoBackfillService: fake.service);
      await Future<void>.delayed(Duration.zero);

      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updated = repo.contacts.firstWhere((c) => c.id == 'c1');
      expect(updated.geo, isNotNull);
      expect(updated.geo!.lat, 37.5);
    });

    test('실패해도 명함이 사라지거나 주소가 지워지지 않는다', () async {
      seedLocalContacts([contact(id: 'c1', address: '못 찾는 주소')]);
      final fake = fakeBackfill(succeed: false);
      final repo = ContactsRepository(geoBackfillService: fake.service);
      await Future<void>.delayed(Duration.zero);

      await repo.setCurrentUid('uid_test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.contacts, hasLength(1));
      expect(repo.contacts.single.address, '못 찾는 주소');
      expect(repo.contacts.single.geo, isNull);
    });

    test('로그아웃(uid null)에는 아무 일도 하지 않는다', () async {
      seedLocalContacts([contact(id: 'c1', address: '서울 중구 세종대로 110')]);
      final fake = fakeBackfill();
      final repo = ContactsRepository(geoBackfillService: fake.service);
      await Future<void>.delayed(Duration.zero);

      await repo.setCurrentUid(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.calls, isEmpty);
    });
  });

  group('전화번호 중복 검사(P1-40)', () {
    ContactModel withPhone(String id, String phone) => ContactModel(
          id: id,
          name: '이름$id',
          company: '회사',
          title: '직함',
          phone: phone,
          email: 'a@b.c',
          tags: const [],
          talkingPoints: const [],
        );

    Future<ContactsRepository> repoWith(List<ContactModel> seed) async {
      seedLocalContacts(seed);
      final repo = ContactsRepository(geoBackfillService: fakeBackfill().service);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return repo;
    }

    test('⭐ 하이픈·공백 표기가 달라도 같은 번호로 인식한다', () async {
      final repo = await repoWith([withPhone('c1', '010-1234-5678')]);
      expect(repo.findByPhone('010 1234 5678')?.id, 'c1');
      expect(repo.findByPhone('01012345678')?.id, 'c1');
    });

    test('없는 번호면 null', () async {
      final repo = await repoWith([withPhone('c1', '010-1234-5678')]);
      expect(repo.findByPhone('010-9999-9999'), isNull);
    });

    test('빈 번호는 중복으로 보지 않는다', () async {
      final repo = await repoWith([withPhone('c1', '')]);
      expect(repo.findByPhone(''), isNull);
      expect(repo.findByPhone('   '), isNull);
    });

    test('excludeId로 자기 자신은 제외한다(편집 시)', () async {
      final repo = await repoWith([withPhone('c1', '010-1234-5678')]);
      expect(repo.findByPhone('010-1234-5678', excludeId: 'c1'), isNull);
    });
  });

  group('다기기 결정적 병합(P1-39 A안 mergeSync)', () {
    ContactModel c(String id, {DateTime? updatedAt, String company = '회사'}) =>
        ContactModel(
          id: id,
          name: '이름$id',
          company: company,
          title: '직함',
          phone: '010-0000-0000',
          email: 'a@b.c',
          tags: const [],
          talkingPoints: const [],
          updatedAt: updatedAt,
        );
    final t1 = DateTime(2026, 8, 2);
    final t2 = DateTime(2026, 8, 3);

    test('⭐ 추가 전파 — 서버에만 있는 건 merged에 들어온다', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t1)],
        server: [c('1', updatedAt: t1), c('2', updatedAt: t1)],
        tombstones: {},
      );
      expect(r.merged.map((x) => x.id).toSet(), {'1', '2'});
    });

    test('⭐ 편집 전파(LWW) — 서버가 최신이면 서버 내용 채택, push 없음', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t1, company: '옛회사')],
        server: [c('1', updatedAt: t2, company: '새회사')],
        tombstones: {},
      );
      expect(r.merged.single.company, '새회사');
      expect(r.toPush, isEmpty);
    });

    test('로컬이 더 최신이면 로컬 채택 + 서버로 push', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t2, company: '새회사')],
        server: [c('1', updatedAt: t1, company: '옛회사')],
        tombstones: {},
      );
      expect(r.merged.single.company, '새회사');
      expect(r.toPush.single.id, '1');
    });

    test('⭐ 삭제 전파 — tombstone이 최신이면 제거', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t1)],
        server: [c('1', updatedAt: t1)],
        tombstones: {'1': t2},
      );
      expect(r.merged, isEmpty);
    });

    test('부활 — 삭제 후 편집(updatedAt이 삭제보다 최신)이면 살아남고 push', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t2)],
        server: const [],
        tombstones: {'1': t1},
      );
      expect(r.merged.single.id, '1');
      expect(r.toPush.single.id, '1');
    });

    test('로컬 온리(오프라인 추가)는 유지 + 서버로 올라감(손실 방지)', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', updatedAt: t1)],
        server: const [],
        tombstones: {},
      );
      expect(r.merged.single.id, '1');
      expect(r.toPush.single.id, '1');
    });

    test('updatedAt 없는 예전 데이터는 실제 편집에 진다', () {
      final r = ContactsRepository.mergeSync(
        local: [c('1', company: '옛')],
        server: [c('1', updatedAt: t1, company: '편집됨')],
        tombstones: {},
      );
      expect(r.merged.single.company, '편집됨');
    });
  });

  group('서버 백업 페이로드', () {
    test('⭐ 서버로 보내는 형태에는 좌표가 들어가지 않는다', () {
      // 추가 76의 핵심 계약. 이 테스트가 깨지면 좌표가 다시 서버로 나간다.
      final json = contact(
        id: 'c1',
        address: '서울 중구 세종대로 110',
        geo: const GeoPosition(lat: 37.5, lng: 127.0),
      ).toBackupJson();

      expect(json.containsKey('lat'), isFalse);
      expect(json.containsKey('lng'), isFalse);
      expect(json['address'], '서울 중구 세종대로 110',
          reason: '좌표를 다시 만들 근거인 주소는 남아 있어야 한다');
    });
  });
}

/// 테스트용 최소 직렬화 — 레거시 평문 저장 형식을 흉내 낸다.
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
