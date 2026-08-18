import 'package:connection_trace_ai_flutter/core/services/photo_improvement_consent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "명함 사진을 인식 기능 개선에 써도 된다"는 별도 동의의 **기본값과 초기화**를
/// 고정한다.
///
/// 여기서 지키려는 것은 하나다 — **동의는 명시적으로 켠 것만 동의다.** 저장된
/// 적이 없거나, 읽는 데 실패했거나, 다른 계정이 쓰던 기기라면 전부 "동의 안 함"
/// 이어야 한다. 반대 방향으로 틀리면(모르면 동의로 침) 동의 없는 이용이 된다.
///
/// 서버 왕복이 필요한 [PhotoImprovementConsentService.setConsent]·[sync]는
/// Firestore 인스턴스가 필요해 여기서 다루지 않는다 — 실서버 확인 항목이다
/// (docs/planning/cs-retention-spec-2026-08-15.md 6절).
void main() {
  group('사진 개선 동의', () {
    test('⭐ 저장된 적이 없으면 동의하지 않은 것으로 본다', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PhotoImprovementConsentService();
      expect(
        await service.load(),
        isFalse,
        reason: '기본값이 true면 "기본으로 켜 두고 끄게 하는" 방식이 된다 — '
            '자유로운 동의가 아니다',
      );
    });

    test('켜 둔 값은 그대로 읽힌다', () async {
      SharedPreferences.setMockInitialValues({
        'photo_improvement_consent_v1': true,
      });
      expect(await PhotoImprovementConsentService().load(), isTrue);
    });

    test('⭐ 초기화하면 다시 "동의 안 함"이 된다', () async {
      // 같은 기기에서 계정을 바꿨을 때 앞 사람의 동의를 물려받으면 안 된다.
      SharedPreferences.setMockInitialValues({
        'photo_improvement_consent_v1': true,
      });
      final service = PhotoImprovementConsentService();
      expect(await service.load(), isTrue);

      await service.clearLocal();

      expect(
        await service.load(),
        isFalse,
        reason: '로그아웃·계정 삭제 뒤에는 다음 계정이 동의를 물려받으면 안 된다',
      );
    });
  });
}
