/// **앱 잠금**(2026-08-28, 추가 568) — 세션 만료 대신 고른 보호 수단.
///
/// ## 왜 세션 만료가 아닌가
///
/// 처음 물음은 *"1개월 이상 안 쓰면 자동 로그아웃되던데 새 규정인가?"*였다.
/// **오히려 없어진 규정이었고**(구 개인정보 보호법 §39조의6, 2023-09-15 폐지)
/// **자동 로그아웃은 폐지 전에도 법적 의무가 아니었다.**
///
/// 🚨 그리고 이 앱에서 세션 만료는 **손해가 더 크다** — 재로그인 → 명함 복원
/// 대기 → *"데이터가 사라졌다"* 오해 → **로그인 방법을 잊고 새 계정.**
/// 2026-08-28에 그 흐름이 실제로 났다(추가 556·565·567).
///
/// ⭐ 앱 잠금은 **기기 잠금이 풀려도 앱은 잠기고, 재로그인이 없다.**
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/app_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('돌아왔을 때 잠글까', () {
    test('꺼져 있으면 안 잠근다', () {
      expect(
        shouldLockOnResume(enabled: false, awayFor: const Duration(days: 1)),
        isFalse,
      );
    });

    test('⭐ 앱을 새로 켠 것이면(떠난 기록 없음) 잠근다', () {
      expect(shouldLockOnResume(enabled: true, awayFor: null), isTrue);
    });

    test('🚨 잠깐 나갔다 오면 안 잠근다 — 촬영·갤러리·주소 검색이 그렇다', () {
      expect(
        shouldLockOnResume(enabled: true, awayFor: const Duration(seconds: 3)),
        isFalse,
        reason: '그때마다 잠그면 명함 한 장 등록에 인증을 세 번 하게 된다',
      );
    });

    test('오래 떠나 있었으면 잠근다', () {
      expect(
        shouldLockOnResume(enabled: true, awayFor: const Duration(minutes: 5)),
        isTrue,
      );
    });

    test('경계(30초)에서는 잠근다 — 애매하면 잠그는 쪽이다', () {
      expect(
        shouldLockOnResume(enabled: true, awayFor: const Duration(seconds: 30)),
        isTrue,
      );
    });
  });

  group('안전한 쪽으로 틀린다', () {
    final svc = File(
      'lib/core/services/app_lock_service.dart',
    ).readAsStringSync();

    test('🚨 설정을 못 읽으면 「꺼짐」으로 본다 — 켜진 것으로 틀리면 앱에 못 들어간다', () {
      final fn = svc.substring(svc.indexOf('Future<bool> isEnabled'));
      final body = fn.substring(0, fn.indexOf('Future<void> setEnabled'));
      expect(body.contains('return false;'), isTrue);
    });

    test('생체만 허용하지 않는다 — 기기 PIN·패턴으로도 열려야 한다', () {
      expect(svc.contains('biometricOnly: false'), isTrue);
    });

    test('인증이 실패·취소되면 잠긴 채로 둔다', () {
      final fn = svc.substring(svc.indexOf('Future<bool> authenticate'));
      expect(fn.contains('return false;'), isTrue);
    });
  });

  group('부르는 곳이 있나', () {
    test('앱 뿌리에 잠금 화면이 걸려 있다 — AuthGate 안쪽', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('AppLockGate'), isTrue);
      expect(
        main.indexOf('AuthGate') < main.indexOf('AppLockGate'),
        isTrue,
        reason: '로그인 전에는 지킬 것이 없고, 인증 창이 겹치면 화면이 뭉개진다',
      );
    });

    test('🚨 켜기 전에 이 기기가 할 수 있는지 확인한다 — 못 하면 앱에 영영 못 들어간다', () {
      final s = File(
        'lib/presentation/features/settings/views/settings_view.dart',
      ).readAsStringSync();
      expect(s.contains('_AppLockRow'), isTrue);
      expect(s.contains('isAvailable()'), isTrue);
    });

    test('잠금 화면에 다시 시도할 길이 있다 — 취소하면 갇힌다', () {
      final gate = File(
        'lib/presentation/common/app_lock_gate.dart',
      ).readAsStringSync();
      expect(gate.contains('잠금 해제'), isTrue);
    });

    test('iOS에 Face ID 안내 문구가 있다 — 없으면 앱이 죽는다', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist.contains('NSFaceIDUsageDescription'), isTrue);
    });
  });
}
