import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('위치 동의는 초기에 알 수 없음이며 동의 시간을 기기에 기록한다', () async {
    final service = LocationConsentService();
    final initial = await service.loadRecord();
    expect(initial.decision, LocationConsentDecision.unknown);
    expect(initial.recordedAt, isNull);

    final accepted = await service.accept();
    final persisted = await service.loadRecord();
    expect(accepted.decision, LocationConsentDecision.accepted);
    expect(accepted.recordedAt, isNotNull);
    expect(persisted.decision, LocationConsentDecision.accepted);
    expect(
      persisted.policyVersion,
      LocationConsentService.currentPolicyVersion,
    );
  });

  test('위치 이용 거부도 현재 정책 버전과 함께 기록한다', () async {
    final service = LocationConsentService();
    await service.decline();

    final persisted = await service.loadRecord();
    expect(persisted.decision, LocationConsentDecision.declined);
    expect(persisted.recordedAt, isNotNull);
  });
}
