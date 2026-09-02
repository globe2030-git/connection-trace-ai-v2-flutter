import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/terms_consent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('필수 동의 기록 — 무엇을 남기나 (P1-17)', () {
    test('동의 항목 셋을 남긴다 — 화면의 필수 항목과 같은 수', () {
      // ⑨ 통합 동의 화면의 필수 항목은 약관·방침·만 14세 셋이다.
      // 하나라도 빠지면 "무엇에 동의했나"의 답이 화면과 달라진다.
      expect(TermsConsentService.requiredItems, hasLength(3));
      expect(
        TermsConsentService.requiredItems,
        containsAll(['termsOfService', 'privacyPolicy', 'age14']),
      );
    });

    test('🚨 항목 키에 방침 버전이 섞이지 않는다', () {
      // 버전은 남기지 않기로 했다(2026-09-02 결정) — 시각으로 역추적한다.
      // 키에 'v2.7' 같은 것이 섞이면 그 순간 앱이 버전의 출처가 되고,
      // 웹에서 방침이 바뀌어도 앱은 모른 채 옛 값을 계속 남긴다.
      for (final item in TermsConsentService.requiredItems) {
        expect(
          RegExp(r'v?\d+\.\d+').hasMatch(item),
          isFalse,
          reason: '"$item" 에 버전으로 읽힐 숫자가 들어 있다',
        );
      }
    });
  });

  group('🚨 규칙이 배포되기 전에 가입한 사람을 잃지 않는다', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('처음에는 밀린 것이 없다', () async {
      expect(await TermsConsentService().pendingCount(), 0);
      expect(await TermsConsentService().pendingConsentedAt('uid-A'), isNull);
    });

    test('🚨 밀린 표시에 「그때의 시각」이 함께 담긴다', () async {
      // 시각을 안 담고 uid 만 담으면, 재시도가 성공한 시점의 시각이 남는다.
      // 그러면 "동의 시각은 처음 동의한 때"라는 원칙이 깨진다 — 사흘 뒤에
      // 규칙이 배포되면 동의 시각이 사흘 뒤로 기록된다.
      SharedPreferences.setMockInitialValues({
        'terms_consent_pending_v2':
            '{"uid-A":"2026-09-02T05:00:00.000Z"}',
      });
      final at = await TermsConsentService().pendingConsentedAt('uid-A');
      expect(at, isNotNull);
      expect(at!.toUtc().toIso8601String(), '2026-09-02T05:00:00.000Z');
    });

    test('⭐ 다른 계정으로 로그인해도 원래 계정의 몫을 지우지 않는다', () async {
      // 지워 버리면 그 계정으로 돌아와도 다시 못 쓴다 — 그 사람의 동의가
      // 영영 안 남는다.
      SharedPreferences.setMockInitialValues({
        'terms_consent_pending_v2':
            '{"uid-A":"2026-09-02T05:00:00.000Z"}',
      });
      final svc = TermsConsentService();
      await svc.retryPendingIfAny('uid-B'); // 서버를 부르지 않는다
      expect(
        await svc.pendingConsentedAt('uid-A'),
        isNotNull,
        reason: 'A 로 돌아왔을 때 다시 시도할 수 있어야 한다',
      );
    });

    test('밀린 것이 없으면 재시도는 아무 일도 하지 않는다', () async {
      // Firestore 를 부르지 않는다 — 부르면 테스트가 초기화 오류로 죽는다.
      await TermsConsentService().retryPendingIfAny('uid-A');
      expect(await TermsConsentService().pendingCount(), 0);
    });

    test('표시가 깨져 있어도 로그인을 막지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'terms_consent_pending_v2': '이건 JSON 이 아니다',
      });
      expect(await TermsConsentService().pendingCount(), 0);
      await TermsConsentService().retryPendingIfAny('uid-A');
    });
  });

  group('🚨 필드 이름이 firestore.rules 와 짝이 맞아야 한다 (소스 검사)', () {
    // 이 서비스는 클라이언트에서 users/{uid} 에 직접 쓴다. 규칙의
    // clientWritableUserFields() 에 필드가 없으면 **쓰기가 조용히 거부된다.**
    // accountSwitches 가 실제로 그렇게 빠져 있어 계정 전환 기록이 조용히
    // 실패하고 있던 전례가 이 저장소에 있다(firestore.rules 565~570행).
    //
    // ⚠️ 지금은 아직 규칙에 없다 — 코드와 규칙을 갈라 올리기로 했다
    // (2026-09-02 globe2030님 결정). 그래서 이 테스트는 "있어야 한다"가
    // 아니라 **"없으면 없다고 말한다"** 로 둔다. 규칙 PR 이 병합되면
    // isFalse 를 isTrue 로 바꾸고 이 주석을 지운다.

    test('현재 상태를 기록해 둔다 — 규칙에 아직 없다', () {
      final rules = File('firestore.rules').readAsStringSync();
      final start = rules.indexOf('clientWritableUserFields');
      expect(start, isNot(-1));
      final block = rules.substring(start, start + 2000);

      final has = [
        TermsConsentService.fieldConsentAt,
        TermsConsentService.fieldConsentItems,
        TermsConsentService.fieldConsentedAtDevice,
      ].every((f) => block.contains("'$f'"));
      expect(
        has,
        isFalse,
        reason:
            '규칙에 필드가 들어왔다 — 규칙 PR 이 병합된 것이다. '
            '이 테스트를 isTrue 로 뒤집고 위 주석을 지울 것',
      );
    });

    test('서비스가 쓰는 필드는 셋뿐이다', () {
      // 필드가 늘면 규칙도 함께 늘려야 한다. 늘어난 것을 여기서 알아챈다.
      final src = File(
        'lib/core/services/terms_consent_service.dart',
      ).readAsStringSync();
      final fields = RegExp(r"static const String field\w+ = '(\w+)'")
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(
        fields,
        ['termsConsentAt', 'termsConsentItems', 'termsConsentedAtDevice'],
        reason: '필드를 늘렸으면 firestore.rules 화이트리스트도 함께 늘려야 한다',
      );
    });
  });
}
