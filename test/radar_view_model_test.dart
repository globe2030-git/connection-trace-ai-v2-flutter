import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/view_models/radar_view_model.dart';

class _FakeLocationGateway implements LocationGateway {
  DeviceLocationAccess checkResult = DeviceLocationAccess.denied;
  DeviceLocationAccess requestResult = DeviceLocationAccess.denied;
  GeoPosition? position;
  int checkCalls = 0;
  int requestCalls = 0;
  int positionCalls = 0;

  @override
  Future<DeviceLocationAccess> checkAccess() async {
    checkCalls++;
    return checkResult;
  }

  @override
  Future<DeviceLocationAccess> requestPermission() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<GeoPosition?> getCurrentPosition() async {
    positionCalls++;
    return position;
  }

  @override
  Future<bool> openAppPermissionSettings() async => true;

  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

class _FakeConsentStore implements LocationConsentStore {
  _FakeConsentStore(this.record);

  LocationConsentRecord record;

  @override
  Future<LocationConsentRecord> loadRecord() async => record;

  @override
  Future<LocationConsentRecord> accept() async {
    record = LocationConsentRecord(
      decision: LocationConsentDecision.accepted,
      recordedAt: DateTime(2026, 8, 3),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }

  @override
  Future<LocationConsentRecord> decline() async {
    record = LocationConsentRecord(
      decision: LocationConsentDecision.declined,
      recordedAt: DateTime(2026, 8, 3),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }
}

/// 서울시청 — 이 테스트에서 "내 위치" 역할.
const _seoulCityHall = GeoPosition(lat: 37.5665, lng: 126.9780);

/// 강남역 — 시청에서 약 8km. "내일 갈 동네" 역할.
const _gangnamStation = GeoPosition(lat: 37.4979, lng: 127.0276);

ContactModel _contactAt(String id, String name, GeoPosition geo) => ContactModel(
  id: id,
  name: name,
  company: '',
  title: '',
  phone: '',
  email: '',
  tags: const [],
  talkingPoints: const [],
  geo: geo,
);

_FakeConsentStore _acceptedConsent() => _FakeConsentStore(
  LocationConsentRecord(
    decision: LocationConsentDecision.accepted,
    recordedAt: DateTime(2026, 8, 16),
    policyVersion: LocationConsentService.currentPolicyVersion,
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('앱 동의 전에는 OS 위치 권한을 확인하거나 요청하지 않는다', () async {
    final gateway = _FakeLocationGateway();
    final model = RadarViewModel(
      contactsRepository: ContactsRepository(),
      locationService: gateway,
      locationConsentService: _FakeConsentStore(LocationConsentRecord.unknown),
    );

    await model.initialization;

    expect(model.locationAccessState, LocationAccessState.consentRequired);
    expect(gateway.checkCalls, 0);
    expect(gateway.requestCalls, 0);
    expect(gateway.positionCalls, 0);
    model.dispose();
  });

  test('앱 동의 후에만 OS 권한을 요청하고 실제 위치를 사용한다', () async {
    final gateway = _FakeLocationGateway()
      ..requestResult = DeviceLocationAccess.granted
      ..position = const GeoPosition(lat: 37.5665, lng: 126.9780);
    final model = RadarViewModel(
      contactsRepository: ContactsRepository(),
      locationService: gateway,
      locationConsentService: _FakeConsentStore(LocationConsentRecord.unknown),
    );
    await model.initialization;

    await model.acceptLocationConsent();

    expect(gateway.requestCalls, 1);
    expect(gateway.positionCalls, 1);
    expect(model.locationAccessState, LocationAccessState.ready);
    expect(model.currentPosition, same(gateway.position));
    model.dispose();
  });

  test('권한을 거부하면 가짜 좌표 없이 거리 결과를 비운다', () async {
    final gateway = _FakeLocationGateway()
      ..requestResult = DeviceLocationAccess.denied;
    final model = RadarViewModel(
      contactsRepository: ContactsRepository(),
      locationService: gateway,
      locationConsentService: _FakeConsentStore(LocationConsentRecord.unknown),
    );
    await model.initialization;

    await model.acceptLocationConsent();

    expect(model.locationAccessState, LocationAccessState.permissionDenied);
    expect(model.currentPosition, isNull);
    expect(model.filteredContacts, isEmpty);
    expect(gateway.positionCalls, 0);
    model.dispose();
  });

  // --- F-13 지도 기준 위치 직접 지정 ------------------------------------

  group('지도에서 지정한 기준점(F-13)', () {
    late _FakeLocationGateway gateway;
    late ContactsRepository repository;

    Future<RadarViewModel> readyModel() async {
      final model = RadarViewModel(
        contactsRepository: repository,
        locationService: gateway,
        locationConsentService: _acceptedConsent(),
      );
      await model.initialization;
      // 반경은 기기에 저장된 값을 되살리므로, 기본값에 기대지 않고 못 박는다.
      model.updateRadius(1000);
      return model;
    }

    setUp(() {
      gateway = _FakeLocationGateway()
        ..checkResult = DeviceLocationAccess.granted
        ..position = _seoulCityHall;
      repository = ContactsRepository()
        ..addContact(_contactAt('near-me', '시청 근처', _seoulCityHall))
        ..addContact(_contactAt('near-anchor', '강남 근처', _gangnamStation));
    });

    test('기준점을 지정하면 그 지점 기준으로 목록이 다시 걸러진다', () async {
      final model = await readyModel();

      expect(model.isUsingCustomAnchor, isFalse);
      expect(model.filteredContacts.map((c) => c.id), ['near-me']);

      model.setAnchor(_gangnamStation);

      expect(model.isUsingCustomAnchor, isTrue);
      expect(model.filteredContacts.map((c) => c.id), ['near-anchor']);
      // 내 위치는 그대로다 — 기준점을 옮긴 것이지 내가 옮겨간 것이 아니다.
      expect(model.currentPosition, same(_seoulCityHall));
      expect(model.usingRealGps, isTrue);

      model.clearAnchor();
      expect(model.filteredContacts.map((c) => c.id), ['near-me']);
      model.dispose();
    });

    test('근접 알림은 기준점이 아니라 내 실제 위치를 기준으로 한다', () async {
      // 이 구분이 없으면 서울에 있는 사용자가 지도에서 부산을 찍은 순간
      // "근처에 OO님이 있습니다"가 뜬다 — 실제로는 400km 떨어져 있다.
      final model = await readyModel();

      model.setAnchor(_gangnamStation);

      expect(model.filteredContacts.map((c) => c.id), ['near-anchor']);
      expect(model.nearbyAlertContact?.id, 'near-me');
      model.dispose();
    });

    test('기준점은 기기에 저장하지 않는다 — 앱을 다시 켜면 내 위치로 돌아온다', () async {
      final model = await readyModel();
      model.setAnchor(_gangnamStation);
      expect(model.isUsingCustomAnchor, isTrue);
      model.dispose();

      // 같은 저장소를 그대로 두고 새로 켠 상황.
      final restarted = await readyModel();

      expect(restarted.anchorPosition, isNull);
      expect(restarted.referencePosition, same(_seoulCityHall));
      expect(restarted.filteredContacts.map((c) => c.id), ['near-me']);
      restarted.dispose();
    });

    test('위치 접근을 잃으면 기준점도 함께 풀린다', () async {
      // 기준점만 남으면 지도를 열 수 없어(내 위치가 없으면 지도가 안 뜬다)
      // 되돌릴 방법이 없는데 목록 거리만 엉뚱해진다.
      final model = await readyModel();
      model.setAnchor(_gangnamStation);

      gateway
        ..checkResult = DeviceLocationAccess.denied
        ..position = null;
      await model.refreshLocation();

      expect(model.anchorPosition, isNull);
      expect(model.referencePosition, isNull);
      expect(model.filteredContacts, isEmpty);
      model.dispose();
    });
  });
}
