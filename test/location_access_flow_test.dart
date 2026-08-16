import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/location_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/view_models/radar_view_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/views/location_access_flow.dart';

/// 연속 탭 방어 회귀 테스트(테스터 피드백, 2026-08-12).
///
/// 증상은 "지도를 연속으로 여러 번 터치하면 앱이 멈춘다(강제종료함)"였다.
/// 원인은 크래시가 아니라 **위치 접근 흐름에 재진입 가드가 없어서** 탭할 때마다
/// 동의 시트가 새로 쌓인 것이다 — 화면이 시트로 겹겹이 덮여 멈춘 것처럼 보였다.
/// GPS 요청은 이미 단일화돼 있었지만 시트·설정 열기 같은 UI 경로는 무방비였다.
class _FakeLocationGateway implements LocationGateway {
  /// E-12: 위치 품질. 검사에서는 기본적으로 "모름"이고, 필요한 검사만
  /// 이 값을 바꿔 쓴다.
  @override
  LocationFixQuality lastFixQuality = LocationFixQuality.unknown;

  DeviceLocationAccess checkResult = DeviceLocationAccess.denied;
  DeviceLocationAccess requestResult = DeviceLocationAccess.denied;
  GeoPosition? position;
  int openSettingsCalls = 0;
  int positionCalls = 0;

  @override
  Future<DeviceLocationAccess> checkAccess() async => checkResult;

  @override
  Future<DeviceLocationAccess> requestPermission() async => requestResult;

  @override
  Future<GeoPosition?> getCurrentPosition() async {
    positionCalls++;
    return position;
  }

  @override
  Future<bool> openAppPermissionSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openDeviceLocationSettings() async {
    openSettingsCalls++;
    return true;
  }
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
      recordedAt: DateTime(2026, 8, 12),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }

  @override
  Future<LocationConsentRecord> decline() async {
    record = LocationConsentRecord(
      decision: LocationConsentDecision.declined,
      recordedAt: DateTime(2026, 8, 12),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }
}

/// 동의 시트 안에만 있는 문구 — 시트가 몇 장 떠 있는지 세는 기준.
const _sheetHeadline = '주변 인맥을 찾기 위해\n현재 위치가 필요해요';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 가드는 흐름 단위(파일 스코프)라 앞 테스트가 시트를 연 채 끝나면 그대로
    // 잠긴 채 넘어온다 — 테스트마다 초기화한다.
    resetLocationAccessActionGuard();
  });

  Future<RadarViewModel> consentRequiredModel() async {
    final model = RadarViewModel(
      contactsRepository: ContactsRepository(),
      locationService: _FakeLocationGateway(),
      locationConsentService: _FakeConsentStore(LocationConsentRecord.unknown),
    );
    await model.initialization;
    return model;
  }

  testWidgets('⭐ 흐름이 진행 중이면 다시 호출해도 동의 시트가 겹쳐 열리지 않는다', (tester) async {
    final model = await consentRequiredModel();
    expect(model.locationAccessState, LocationAccessState.consentRequired);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    // 첫 탭 — 시트가 열린다.
    unawaited(handleLocationAccessAction(ctx, model));
    await tester.pumpAndSettle();
    expect(find.text(_sheetHeadline), findsOneWidget);

    // 아직 안 닫힌 상태에서 또 눌린 경우(연속 터치). 가드가 없으면 여기서
    // 시트가 한 장 더 쌓이고, 그렇게 겹겹이 쌓인 화면이 "앱이 멈춘 것"처럼
    // 보였다 — 이 테스트가 고정하는 것이 바로 그 지점이다.
    unawaited(handleLocationAccessAction(ctx, model));
    await tester.pumpAndSettle();
    expect(find.text(_sheetHeadline), findsOneWidget);

    model.dispose();
  });

  testWidgets('⭐ 한 번 끝난 뒤에는 다시 동작한다(가드가 영구히 잠기지 않는다)', (tester) async {
    // 모달이 끼지 않는 경로(ready → 위치 새로고침)로 확인한다. 시트가 열리는
    // 경로는 닫히는 애니메이션과 흐름 종료 시점이 얽혀 판정이 흔들리는데,
    // 여기서 확인하려는 것은 "가드가 풀리는가" 하나뿐이다.
    final gateway = _FakeLocationGateway()
      ..checkResult = DeviceLocationAccess.granted
      ..requestResult = DeviceLocationAccess.granted
      ..position = const GeoPosition(lat: 37.5665, lng: 126.9780);
    final model = RadarViewModel(
      contactsRepository: ContactsRepository(),
      locationService: gateway,
      locationConsentService: _FakeConsentStore(
        LocationConsentRecord(
          decision: LocationConsentDecision.accepted,
          recordedAt: DateTime(2026, 8, 12),
          policyVersion: LocationConsentService.currentPolicyVersion,
        ),
      ),
    );
    await model.initialization;
    expect(model.locationAccessState, LocationAccessState.ready);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    final before = gateway.positionCalls;
    await handleLocationAccessAction(ctx, model);
    final afterFirst = gateway.positionCalls;
    expect(afterFirst, before + 1, reason: '첫 호출은 위치를 새로 읽어야 한다');

    // 가드가 안 풀렸다면 두 번째 호출은 아무 일도 하지 않는다.
    await handleLocationAccessAction(ctx, model);
    expect(
      gateway.positionCalls,
      afterFirst + 1,
      reason: '앞 흐름이 끝났으면 다음 탭은 정상 동작해야 한다',
    );

    model.dispose();
  });
}
