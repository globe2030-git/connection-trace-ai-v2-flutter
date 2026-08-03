import 'package:shared_preferences/shared_preferences.dart';

enum LocationConsentDecision { unknown, accepted, declined }

class LocationConsentRecord {
  final LocationConsentDecision decision;
  final DateTime? recordedAt;
  final int policyVersion;

  const LocationConsentRecord({
    required this.decision,
    required this.recordedAt,
    required this.policyVersion,
  });

  static const unknown = LocationConsentRecord(
    decision: LocationConsentDecision.unknown,
    recordedAt: null,
    policyVersion: LocationConsentService.currentPolicyVersion,
  );
}

abstract interface class LocationConsentStore {
  Future<LocationConsentRecord> loadRecord();
  Future<LocationConsentRecord> accept();
  Future<LocationConsentRecord> decline();
}

/// 앱 자체 위치 이용 동의 기록을 기기에 보관한다.
///
/// 운영체제의 위치 권한과 앱의 이용 동의는 서로 다른 상태다. 사용자가 앱의
/// 설명을 읽고 동의한 뒤에만 OS 권한을 요청하며, 정책 문구가 바뀌면
/// [currentPolicyVersion]을 올려 다시 동의를 받는다. GPS 좌표는 저장하지 않는다.
class LocationConsentService implements LocationConsentStore {
  static const int currentPolicyVersion = 1;
  static const String _decisionKey = 'location_consent_decision';
  static const String _recordedAtKey = 'location_consent_recorded_at';
  static const String _policyVersionKey = 'location_consent_policy_version';

  @override
  Future<LocationConsentRecord> loadRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt(_policyVersionKey);
    if (version != currentPolicyVersion) return LocationConsentRecord.unknown;

    final rawDecision = prefs.getString(_decisionKey);
    final decision = switch (rawDecision) {
      'accepted' => LocationConsentDecision.accepted,
      'declined' => LocationConsentDecision.declined,
      _ => LocationConsentDecision.unknown,
    };
    final rawRecordedAt = prefs.getString(_recordedAtKey);

    return LocationConsentRecord(
      decision: decision,
      recordedAt: rawRecordedAt == null
          ? null
          : DateTime.tryParse(rawRecordedAt),
      policyVersion: currentPolicyVersion,
    );
  }

  @override
  Future<LocationConsentRecord> accept() =>
      _save(LocationConsentDecision.accepted);

  @override
  Future<LocationConsentRecord> decline() =>
      _save(LocationConsentDecision.declined);

  Future<LocationConsentRecord> _save(LocationConsentDecision decision) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_decisionKey, decision.name),
      prefs.setString(_recordedAtKey, now.toIso8601String()),
      prefs.setInt(_policyVersionKey, currentPolicyVersion),
    ]);

    return LocationConsentRecord(
      decision: decision,
      recordedAt: now,
      policyVersion: currentPolicyVersion,
    );
  }
}
