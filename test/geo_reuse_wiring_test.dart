/// **배선 테스트** — 같은 주소 좌표 재사용을 **실제로 부르는가**(2026-08-28).
///
/// 🚨 이 저장소는 같은 자리에서 이미 한 번 데었다. CLAUDE.md 4절 표의
/// *"재시도 로직이 죽어 있음 — 서비스는 정상, **부르는 쪽이 없음**"* 이다.
///
/// `geo_backfill_test.dart` 는 서비스가 빌려 쓰는 것을 확인한다. 그런데
/// **저장소가 그 map 을 안 넘기면** 서비스 테스트는 전부 초록인 채로
/// 아무 일도 안 일어난다 — 명함마다 계속 물어보고, 아무도 모른다.
///
/// 📌 그래서 여기서는 **넘겼는가**만 본다.
library;

import 'dart:async';

import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 무엇을 넘겨받았는지만 적어 두는 가짜. 진짜 통신은 하지 않는다.
class _SpyBackfill extends GeoBackfillService {
  Map<String, GeoPosition>? received;

  @override
  Future<List<ContactModel>> pendingContacts(List<ContactModel> contacts) async =>
      contacts.where((c) => c.geo == null).toList();

  @override
  Future<Map<String, GeoPosition>> backfill(
    List<ContactModel> contacts, {
    Map<String, GeoPosition>? knownGeoByAddress,
    void Function(int done, int total)? onProgress,
    FutureOr<void> Function(String contactId, GeoPosition geo)? onResolved,
  }) async {
    received = knownGeoByAddress;
    return const {};
  }
}

ContactModel _card({
  required String id,
  String? address,
  GeoPosition? geo,
}) => ContactModel(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const addr = '서울특별시 강남구 테헤란로 1';
  const geo = GeoPosition(lat: 37.5, lng: 127.0);

  test('🚨 저장소가 「이미 아는 주소」를 실제로 넘긴다', () async {
    final spy = _SpyBackfill();
    final repo = ContactsRepository(geoBackfillService: spy);
    repo.addContact(_card(id: 'old', address: addr, geo: geo));
    repo.addContact(_card(id: 'new', address: addr));

    await repo.backfillMissingGeo();

    expect(
      spy.received,
      isNotNull,
      reason: '안 넘기면 서비스 테스트는 전부 초록인데 실제로는 명함마다 '
          '계속 물어본다 — 아무도 모른다',
    );
    expect(spy.received![addr], geo);
  });

  test('⭐ 좌표가 없는 명함의 주소는 안 넘긴다', () async {
    final spy = _SpyBackfill();
    final repo = ContactsRepository(geoBackfillService: spy);
    repo.addContact(_card(id: 'a', address: addr));

    await repo.backfillMissingGeo();

    expect(
      spy.received,
      isEmpty,
      reason: '아는 것이 없는데 있다고 넘기면 빈 좌표를 빌려 쓰게 된다',
    );
  });

  test('⭐ 주소가 없는 명함은 안 넘긴다', () async {
    final spy = _SpyBackfill();
    final repo = ContactsRepository(geoBackfillService: spy);
    repo.addContact(_card(id: 'a', address: null, geo: geo));
    repo.addContact(_card(id: 'b', address: '  ', geo: geo));
    repo.addContact(_card(id: 'c', address: addr));

    await repo.backfillMissingGeo();

    expect(spy.received, isEmpty, reason: '빈 주소를 키로 쓰면 전부 한 덩어리가 된다');
  });
}
