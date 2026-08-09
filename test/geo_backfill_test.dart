import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/core/services/address_geocoding_service.dart';
import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';

/// 좌표를 서버에 백업하지 않기로 한 결정(backlog 추가 75, C안)이 실제로
/// 지켜지는지, 그리고 그 대가로 필요해진 "복원 후 주소로 좌표 재계산"이
/// 제대로 도는지 확인한다.

ContactModel _contact({
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

AddressValidationResult _ok(GeoPosition geo) => AddressValidationResult(
  isValid: true,
  originalAddress: 'x',
  geoPosition: geo,
);

const _fail = AddressValidationResult(
  isValid: false,
  originalAddress: 'x',
  message: '위치를 찾을 수 없는 주소입니다.',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ContactModel 백업 페이로드', () {
    test('서버 백업에는 좌표(lat/lng)가 들어가지 않는다', () {
      final json = _contact(
        id: '1',
        address: '서울시 영등포구 양평로21가길 19',
        geo: const GeoPosition(lat: 37.52, lng: 126.89),
      ).toBackupJson();

      expect(json.containsKey('lat'), isFalse);
      expect(json.containsKey('lng'), isFalse);
      // 좌표를 다시 만들 근거인 주소는 남아 있어야 복원이 가능하다.
      expect(json['address'], '서울시 영등포구 양평로21가길 19');
    });

    test('기기 저장용에는 좌표가 그대로 들어간다', () {
      final json = _contact(
        id: '1',
        address: '서울시 영등포구 양평로21가길 19',
        geo: const GeoPosition(lat: 37.52, lng: 126.89),
      ).toJson();

      expect(json['lat'], 37.52);
      expect(json['lng'], 126.89);
    });

    test('좌표 없이 왕복해도 나머지 필드가 보존된다', () {
      final restored = ContactModel.fromJson(
        _contact(
          id: '1',
          address: '서울시 영등포구 양평로21가길 19',
          geo: const GeoPosition(lat: 37.52, lng: 126.89),
        ).toBackupJson(),
      );

      expect(restored.geo, isNull, reason: '서버에서 내려온 명함은 좌표가 비어 있다');
      expect(restored.address, '서울시 영등포구 양평로21가길 19');
      expect(restored.name, '테스트1');
    });
  });

  group('GeoBackfillService', () {
    test('주소가 있고 좌표가 없는 명함만 채운다', () async {
      final calls = <String>[];
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls.add(address);
          return _ok(const GeoPosition(lat: 1, lng: 2));
        },
      );

      final resolved = await service.backfill([
        _contact(id: 'needs', address: '주소 A'),
        _contact(
          id: 'hasGeo',
          address: '주소 B',
          geo: const GeoPosition(lat: 9, lng: 9),
        ),
        _contact(id: 'noAddress'),
      ]);

      expect(resolved.keys, ['needs']);
      expect(resolved['needs']!.lat, 1);
      expect(calls, ['주소 A'], reason: '이미 좌표가 있거나 주소가 없으면 지오코딩하지 않는다');
    });

    test('실패한 건은 결과에 담기지 않고 다음 실행에서 다시 시도된다', () async {
      var attempt = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          attempt++;
          return attempt == 1 ? _fail : _ok(const GeoPosition(lat: 3, lng: 4));
        },
      );
      final contacts = [_contact(id: 'c1', address: '주소')];

      expect(await service.backfill(contacts), isEmpty);
      expect(await service.pendingContacts(contacts), hasLength(1));

      final second = await service.backfill(contacts);
      expect(second['c1']!.lat, 3);
    });

    test('반복 실패하면 포기하고 더 이상 시도하지 않는다', () async {
      var calls = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          return _fail;
        },
      );
      final contacts = [_contact(id: 'c1', address: '못 찾는 주소')];

      for (var i = 0; i < GeoBackfillService.maxAttemptsPerContact; i++) {
        await service.backfill(contacts);
      }
      final callsAfterGivingUp = calls;

      await service.backfill(contacts);
      expect(calls, callsAfterGivingUp, reason: '포기한 뒤에는 지오코더를 호출하지 않는다');
      expect(await service.pendingContacts(contacts), isEmpty);
    });

    test('⭐ 포기한 명함은 hasGivenUpGeo가 true (P1-25 안내 근거)', () async {
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async => _fail,
      );
      final c = _contact(id: 'c1', address: '못 찾는 주소');

      // 아직 시도 전에는 포기 상태가 아니다.
      expect(await service.hasGivenUpGeo(c), isFalse);

      for (var i = 0; i < GeoBackfillService.maxAttemptsPerContact; i++) {
        await service.backfill([c]);
      }
      // 3회 실패로 포기된 뒤에는 true → 화면에서 "주소 확인" 안내를 띄운다.
      expect(await service.hasGivenUpGeo(c), isTrue);

      // 좌표가 이미 있거나 주소가 없으면 애초에 판별 대상이 아니다.
      expect(
        await service.hasGivenUpGeo(
          _contact(id: 'c1', address: '못 찾는 주소', geo: const GeoPosition(lat: 1, lng: 2)),
        ),
        isFalse,
      );
      expect(await service.hasGivenUpGeo(_contact(id: 'c1')), isFalse);
    });

    test('주소가 바뀌면 포기했던 명함도 다시 시도한다', () async {
      var shouldFail = true;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async =>
            shouldFail ? _fail : _ok(const GeoPosition(lat: 5, lng: 6)),
      );

      final oldAddress = [_contact(id: 'c1', address: '틀린 주소')];
      for (var i = 0; i < GeoBackfillService.maxAttemptsPerContact; i++) {
        await service.backfill(oldAddress);
      }
      expect(await service.pendingContacts(oldAddress), isEmpty);

      // 사용자가 주소를 고쳤다.
      shouldFail = false;
      final newAddress = [_contact(id: 'c1', address: '고친 주소')];
      expect(await service.pendingContacts(newAddress), hasLength(1));
      final resolved = await service.backfill(newAddress);
      expect(resolved['c1']!.lat, 5);
    });

    test('연속 실패가 이어지면 남은 건을 건너뛰고 회차를 중단한다', () async {
      var calls = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          return _fail;
        },
      );

      await service.backfill([
        for (var i = 0; i < 10; i++) _contact(id: 'c$i', address: '주소 $i'),
      ]);

      // 오프라인일 때 10건 × 10초 타임아웃을 다 기다리지 않기 위한 장치.
      expect(calls, GeoBackfillService.consecutiveFailuresToAbort);
    });

    test('지오코더가 예외를 던져도 회차 전체가 죽지 않는다', () async {
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          if (address == '폭탄') throw StateError('boom');
          return _ok(const GeoPosition(lat: 7, lng: 8));
        },
      );

      final resolved = await service.backfill([
        _contact(id: 'bad', address: '폭탄'),
        _contact(id: 'good', address: '정상 주소'),
      ]);

      expect(resolved.keys, ['good']);
    });

    test('한 회차에서 처리할 건수에 상한이 있다', () async {
      var calls = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          return _ok(const GeoPosition(lat: 1, lng: 1));
        },
      );

      final many = [
        for (var i = 0; i < GeoBackfillService.maxContactsPerRun + 5; i++)
          _contact(id: 'c$i', address: '주소 $i'),
      ];
      await service.backfill(many);

      expect(calls, GeoBackfillService.maxContactsPerRun);
    });
  });
}
