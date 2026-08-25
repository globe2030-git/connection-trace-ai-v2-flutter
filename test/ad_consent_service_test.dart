import 'package:connection_trace_ai_flutter/core/services/ad_consent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고 수신 동의(추가 472)의 **기본값과 상태 구분**을 고정한다.
///
/// 여기서 지키려는 것은 둘이다.
///
/// 1. **동의는 명시적으로 켠 것만 동의다.** 저장된 적이 없거나 읽는 데
///    실패했으면 "동의 안 함"이다. 반대로 틀리면 동의 없는 전송이 된다.
/// 2. 🚨 **"아직 안 물었다"와 "물었고 거부했다"는 다르다.** 둘을 같게 다루면
///    거부한 사람에게 로그인할 때마다 다시 묻게 된다.
///
/// 서버 왕복이 필요한 [AdConsentService.save]·[fetch]는 Firestore 인스턴스가
/// 필요해 여기서 다루지 않는다 — 실서버 확인 항목이다.
void main() {
  group('광고 수신 동의 — 기본값', () {
    test('⭐ 저장된 적이 없으면 동의하지 않은 것으로 본다', () async {
      SharedPreferences.setMockInitialValues({});
      final state = await AdConsentService().loadCached();
      expect(state.email, isFalse);
      expect(state.push, isFalse);
      expect(
        state.answered,
        isFalse,
        reason: '기본값이 true면 "기본으로 켜 두고 끄게 하는" 방식이 된다 — '
            '안내서가 금지하는 형태다',
      );
    });

    test('켜 둔 값은 그대로 읽힌다', () async {
      SharedPreferences.setMockInitialValues({
        'ad_consent_email_v1': true,
        'ad_consent_push_v1': false,
      });
      final state = await AdConsentService().loadCached();
      expect(state.email, isTrue);
      expect(state.push, isFalse);
      expect(state.anyEnabled, isTrue);
    });

    test('⭐ 캐시를 지우면 다시 "아직 안 물었다"가 된다', () async {
      // 같은 기기에서 계정을 바꿨을 때 앞 사람의 동의를 물려받으면 안 된다.
      SharedPreferences.setMockInitialValues({
        'ad_consent_email_v1': true,
        'ad_consent_push_v1': true,
      });
      final service = AdConsentService();
      await service.clearCache();
      final state = await service.loadCached();
      expect(state.anyEnabled, isFalse);
      expect(
        state.answered,
        isFalse,
        reason: '지운 뒤에도 "물었다"로 남으면 새 계정에게 동의를 안 묻는다',
      );
    });
  });

  group('🚨 "안 물었다"와 "거부했다"는 다르다', () {
    test('⭐ 둘 다 꺼져 있어도, 답한 적이 있으면 다시 묻지 않는다', () {
      const asked = AdConsentState.none;
      const notAsked = AdConsentState.unasked;

      expect(asked.anyEnabled, isFalse);
      expect(notAsked.anyEnabled, isFalse);
      expect(
        asked == notAsked,
        isFalse,
        reason: '수신 여부만 보면 둘이 같아 보인다. 그러나 앞은 "거부 의사를 '
            '받아 둔 것"이고 뒤는 "동의를 받은 적이 없는 것"이라 법적으로도 다르다',
      );
      expect(asked.answered, isTrue);
      expect(notAsked.answered, isFalse);
    });

    test('거부한 사람의 캐시는 "답했다"로 남는다', () async {
      // 화면에서 둘 다 끈 채 [시작하기]를 누른 상태를 흉내낸다.
      SharedPreferences.setMockInitialValues({
        'ad_consent_email_v1': false,
        'ad_consent_push_v1': false,
      });
      final state = await AdConsentService().loadCached();
      expect(state.anyEnabled, isFalse);
      expect(
        state.answered,
        isTrue,
        reason: '거부했는데 "안 물었다"로 읽히면 로그인할 때마다 다시 묻는다',
      );
    });
  });

  group('상태값 비교', () {
    test('같은 값이면 같다', () {
      expect(
        const AdConsentState(email: true, push: false, answered: true),
        const AdConsentState(email: true, push: false, answered: true),
      );
    });

    test('하나라도 다르면 다르다', () {
      expect(
        const AdConsentState(email: true, push: false, answered: true),
        isNot(const AdConsentState(email: true, push: true, answered: true)),
      );
    });
  });
}
