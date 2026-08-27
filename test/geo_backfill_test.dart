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
  failureReason: GeoFailureReason.noResult,
  message: '위치를 찾을 수 없는 주소입니다.',
);

const _failComm = AddressValidationResult(
  isValid: false,
  originalAddress: 'x',
  failureReason: GeoFailureReason.communicationError,
  message: '위치를 찾을 수 없는 주소입니다.',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  _reuseTests();

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

    test(
      '⭐ 추가 435 — copyWith(geo:) → toJson → fromJson 왕복에서 좌표가 보존된다',
      () {
        // 추가 435 조사 대상 ①a: "백필이 성공했는데 결과가 사라지는 경로"의
        // 첫 용의선이 ContactModel의 저장 왕복이었다. 이 테스트는 정상임을
        // 못박는다 — 실제 원인은 저장 직렬화가 아니라 다기기 병합의 LWW
        // 동률 처리였다(contacts_repository_wiring_test.dart의 mergeSync
        // 회귀 테스트가 그쪽을 잠근다).
        final original = _contact(id: '1', address: '주소');
        final withGeo = original.copyWith(
          geo: const GeoPosition(lat: 37.1234, lng: 127.5678),
        );

        final restored = ContactModel.fromJson(withGeo.toJson());

        expect(restored.geo?.lat, 37.1234);
        expect(restored.geo?.lng, 127.5678);
      },
    );

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

    test('⭐ 통신 실패가 연속되면 남은 건을 건너뛰고 회차를 중단한다', () async {
      var calls = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          return _failComm;
        },
      );

      await service.backfill([
        for (var i = 0; i < 10; i++) _contact(id: 'c$i', address: '주소 $i'),
      ]);

      // 오프라인일 때 10건 × 10초 타임아웃을 다 기다리지 않기 위한 장치.
      expect(calls, GeoBackfillService.consecutiveFailuresToAbort);
    });

    test(
      '⭐ 주소가 안 풀리는 것(결과 없음)만 이어져도 중단하지 않는다(추가 434)',
      () async {
        // 회귀 방지: 예전엔 실패 사유를 안 가리고 다 세서, 목록 앞쪽에 안
        // 풀리는 주소가 3장만 몰려 있어도 회차가 거기서 죽어 뒤쪽 명함에
        // 영원히 도달하지 못했다(실기기 실측 — 진행 배너가 4~6/30에서 멈춤).
        var calls = 0;
        final service = GeoBackfillService(
          gapBetweenRequests: Duration.zero,
          geocode: (address) async {
            calls++;
            // 앞 5장은 결과 없음, 나머지는 성공 — 통신은 계속 살아 있다.
            return calls <= 5
                ? _fail
                : _ok(const GeoPosition(lat: 1, lng: 1));
          },
        );

        final resolved = await service.backfill([
          for (var i = 0; i < 10; i++) _contact(id: 'c$i', address: '주소 $i'),
        ]);

        expect(calls, 10, reason: '주소 문제로는 회차가 중단되면 안 된다');
        expect(resolved, hasLength(5), reason: '뒤쪽의 풀리는 명함까지 도달해야 한다');
      },
    );

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

    test(
      '⭐ onResolved가 회차 도중 한 건씩 즉시 불린다(추가 434 — 도중 저장 근거)',
      () async {
        // 회귀 방지: 예전엔 backfill()이 완전히 반환한 뒤에만 호출자가 결과를
        // 알 수 있었다 — 회차 도중 앱이 죽으면(실기기: am force-stop) 이미
        // 성공한 것까지 통째로 사라졌다. onResolved는 반환을 기다리지 않고
        // 성공하는 즉시 불려야 "도중에 죽어도 이미 성공한 것은 남는다"가
        // 성립한다.
        final resolvedInOrder = <String>[];
        final service = GeoBackfillService(
          gapBetweenRequests: Duration.zero,
          geocode: (address) async => _ok(const GeoPosition(lat: 1, lng: 1)),
        );

        final resolved = await service.backfill(
          [
            _contact(id: 'c1', address: '주소 1'),
            _contact(id: 'c2', address: '주소 2'),
          ],
          onResolved: (id, geo) {
            resolvedInOrder.add(id);
          },
        );

        expect(resolvedInOrder, ['c1', 'c2']);
        expect(resolved.keys, resolvedInOrder, reason: '최종 맵과도 내용이 같아야 한다');
      },
    );

    test(
      '⭐ 추가 435 계측 — 회차의 단계별 집계가 저장되고 다음 회차에 덮어써진다',
      () async {
        final service = GeoBackfillService(
          gapBetweenRequests: Duration.zero,
          geocode: (address) async => AddressValidationResult(
            isValid: true,
            originalAddress: address,
            geoPosition: const GeoPosition(lat: 1, lng: 1),
            stage: GeoStage.jusoSuccess,
          ),
        );
        final contacts = [
          _contact(id: 'c1', address: '주소 1'),
          _contact(id: 'c2', address: '주소 2'),
        ];

        await service.backfill(contacts);
        final stats = await GeoBackfillService.readStageStats();

        expect(stats['jusoSuccess'], 2);
      },
    );

    test('resetAttempts로 포기분을 다시 시도 대상으로 되돌릴 수 있다', () async {
      var calls = 0;
      final service = GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          return calls <= GeoBackfillService.maxAttemptsPerContact
              ? _fail
              : _ok(const GeoPosition(lat: 9, lng: 9));
        },
      );
      final contacts = [_contact(id: 'c1', address: '못 찾던 주소')];

      for (var i = 0; i < GeoBackfillService.maxAttemptsPerContact; i++) {
        await service.backfill(contacts);
      }
      expect(await service.hasGivenUpGeo(contacts.single), isTrue);

      final givenUp = await service.resolveGivenUpIds(contacts);
      await service.resetAttempts(givenUp);

      expect(await service.hasGivenUpGeo(contacts.single), isFalse);
      final resolved = await service.backfill(contacts);
      expect(resolved['c1']!.lat, 9, reason: '기록을 지우면 다시 지오코더를 부른다');
    });
  });
}

/// 🚨 **같은 주소는 다시 안 물어본다** (2026-08-28, globe2030님 지적).
///
/// > *"회사별 좌표는 한번만 확인되면 저장되서 명함의 회사 주소로 계속
/// > 검색할 이유가 없지않나?"*
///
/// 예전에는 명함 단위로 돌아서 같은 회사 명함 5장이면 **똑같은 주소를 5번**
/// 물어봤다. 그 헛호출이 한 회차 상한(30장)의 자리까지 차지했다.
///
/// ⚠️ 여기서 지키는 것 둘이다.
///
/// ```
/// ① 같은 주소면 통신하지 않는다        _geocode 호출 횟수를 센다
/// ② 다른 주소면 반드시 통신한다        빌려오기가 번지지 않게
/// ```
///
/// 📌 ②가 더 중요하다. **틀린 좌표가 붙는 유일한 경로**가 "같지 않은데
/// 같다고 본 것"이라, 그 경계를 테스트로 못 박는다.
void _reuseTests() {
  group('🚨 같은 주소는 좌표를 다시 안 물어본다', () {
    late int calls;
    late List<String> asked;

    GeoBackfillService service(Map<String, GeoPosition> answers) {
      calls = 0;
      asked = [];
      return GeoBackfillService(
        gapBetweenRequests: Duration.zero,
        geocode: (address) async {
          calls++;
          asked.add(address);
          final geo = answers[address];
          return geo == null ? _fail : _ok(geo);
        },
      );
    }

    test('⭐ 같은 주소 명함 셋이면 한 번만 물어본다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      const geo = GeoPosition(lat: 37.5, lng: 127.0);
      final s = service({addr: geo});

      final resolved = await s.backfill([
        _contact(id: 'a', address: addr),
        _contact(id: 'b', address: addr),
        _contact(id: 'c', address: addr),
      ]);

      expect(calls, 1, reason: '나머지 둘은 첫 답을 빌려 쓴다');
      expect(resolved.length, 3, reason: '셋 다 좌표를 얻는다');
      expect(resolved['b'], geo);
      expect(resolved['c'], geo);
    });

    test('⭐ 이미 좌표를 가진 명함의 주소면 아예 안 물어본다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      const geo = GeoPosition(lat: 37.5, lng: 127.0);
      // 답을 하나도 주지 않는다 — 통신하면 실패한다.
      final s = service(const {});

      final resolved = await s.backfill(
        [_contact(id: 'new', address: addr)],
        knownGeoByAddress: const {addr: geo},
      );

      expect(calls, 0, reason: '기존 명함이 이미 아는 주소다');
      expect(resolved['new'], geo);
    });

    test('🚨 주소가 조금이라도 다르면 반드시 물어본다', () async {
      const known = '서울특별시 강남구 테헤란로 1';
      const other = '서울 강남구 테헤란로 1'; // 사람 눈엔 같지만 글자가 다르다
      const geo = GeoPosition(lat: 37.5, lng: 127.0);
      final s = service(const {});

      await s.backfill(
        [_contact(id: 'x', address: other)],
        knownGeoByAddress: const {known: geo},
      );

      expect(
        calls,
        1,
        reason: '정규화하지 않는다 — 잘못 묶으면 엉뚱한 좌표가 붙는다. '
            '안 되는 쪽으로 안전하게 둔다',
      );
      expect(asked.single, other);
    });

    test('⭐ 빌려온 건도 단계별 집계에 남는다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      const geo = GeoPosition(lat: 37.5, lng: 127.0);
      final s = service(const {});

      await s.backfill(
        [_contact(id: 'a', address: addr), _contact(id: 'b', address: addr)],
        knownGeoByAddress: const {addr: geo},
      );

      final stats = await GeoBackfillService.readStageStats();
      expect(
        stats[GeoStage.reusedFromSameAddress.name],
        2,
        reason: '이 숫자가 곧 "주소가 얼마나 겹치는가"의 실측이다 — '
            '재지 않으면 "좋아졌겠지"만 남는다',
      );
    });

    test('⭐ 실패한 주소는 빌려주지 않는다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      final s = service(const {}); // 무조건 실패

      final resolved = await s.backfill([
        _contact(id: 'a', address: addr),
        _contact(id: 'b', address: addr),
      ]);

      expect(resolved, isEmpty);
      expect(
        calls,
        2,
        reason: '실패는 캐시하지 않는다 — 일시적 통신 문제일 수 있고, '
            '재시도 횟수는 명함마다 따로 센다',
      );
    });
  });
}
