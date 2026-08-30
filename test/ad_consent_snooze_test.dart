// 광고 동의를 미룬 뒤 언제 다시 묻나 (2026-08-30 globe2030님 확정: 30일).
//
// 🚨 **왜 생겼나**: 답하지 않고 넘어가면 **앱을 켤 때마다** 동의 화면이 떴다.
// 코드 주석은 *"다음 로그인에 다시 기회가 온다"* 고 했는데, 로그인이 유지돼
// 있어도 `auth_gate` 가 앱을 켤 때마다 판정하기 때문에 **답할 때까지 매번**
// 떴다. 실기기 실측으로 드러났다.
//
// ⚠️ 답할 때까지 계속 뜨면 이용자는 **필수라고 느낀다** — 「자유로운 동의」
// (시행령 §17①1호)에서 멀어진다. 이 파일이 그 거리를 지킨다.
import 'package:connection_trace_ai_flutter/core/services/ad_consent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('⭐ 미루는 기간은 30일이다 — 줄이려면 근거를 함께 적어라', () {
    expect(AdConsentService.snoozeDuration, const Duration(days: 30));
  });

  test('⭐ 미루면 기기에 시각이 남는다 — 서버가 아니다', () async {
    await AdConsentService().snooze('uid-A');
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.contains('snoozed'));
    expect(keys, hasLength(1));
    expect(prefs.getInt(keys.first), isA<int>());
  });

  test('🚨 미룸은 「답했다」가 아니다 — 동의·거부 값을 건드리지 않는다', () async {
    // 이것이 굳으면 30일 뒤에도 다시 안 묻고, 실수로 뒤로 누른 사람은
    // 영영 기회를 잃는다.
    await AdConsentService().snooze('uid-A');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ad_consent_email_v1'), isNull);
    expect(prefs.getBool('ad_consent_push_v1'), isNull);
  });

  test('미루기 전에는 기기에 아무 기록이 없다', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.contains('snoozed')), isEmpty);
  });

  test('🚨 계정마다 따로 적는다 — 다른 계정은 물어본 적이 없다', () async {
    // 키 하나로 두면 로그아웃하고 다른 계정으로 들어와도 안 묻는다.
    // 그 사람은 물어본 적이 없는데 미룬 것으로 취급된다.
    await AdConsentService().snooze('uid-A');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('ad_consent_snoozed_at_v1_uid-A'), isA<int>());
    expect(prefs.getInt('ad_consent_snoozed_at_v1_uid-B'), isNull);
  });
}
