import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
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
}
