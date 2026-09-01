import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/phone_verification_service.dart';

/// 번호 확인 게이트의 **범위 판정**(추가 645).
///
/// ## 무엇을 지키려는 검사인가
///
/// 예전에는 게이트가 `phoneVerifiedAt` 유무만 봤다. 그 필드는 **기존
/// 이용자에게 없으므로**, 스위치를 켜는 순간 **기존 회원 전원이 인증
/// 화면에 갇혔다** — 건너뛰기도 뒤로가기도 없어서 나갈 길이 없다.
///
/// 🚨 그런데 개인정보처리방침에는 *"기존 회원의 처리 내용은 달라지지
/// 않는다"*고 적혀 있었다. 방침 30조 3항은 **방침과 실제가 다르면
/// 정보주체에게 유리한 쪽을 적용한다**고 정하므로, 그대로 뒀으면 **켜는
/// 순간 방침 위반**이 됐다.
///
/// ⚠️ **이 층은 자동 테스트로 잘 안 보인다.** 규칙은 다 맞는데 *"누구에게
/// 무슨 일이 일어나는가"*가 문서와 달랐던 자리다(광고 동의 때와 같은 결).
/// 그래서 **여기만은 경계를 하나씩 못 박아 둔다.**
void main() {
  ({bool enforce, DateTime? enforceFrom}) on(DateTime? from) =>
      (enforce: true, enforceFrom: from);

  final cutoff = DateTime.utc(2026, 9, 9);

  group('막지 않는 쪽으로 기우는 경우 — 하나라도 모르면 안 막는다', () {
    test('스위치가 꺼져 있으면 대상이 아니다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: (enforce: false, enforceFrom: cutoff),
          accountCreatedAt: DateTime.utc(2026, 12, 25),
        ),
        isFalse,
      );
    });

    test('🚨 enforceFrom 이 없으면 대상이 아니다 — 범위를 모르기 때문', () {
      // 이것이 「enforce 만 만들고 enforceFrom 을 빠뜨리는 사고」의 안전망이다.
      // 없으면 아무도 안 막힌다 — 전원이 갇히는 것보다 낫다.
      expect(
        PhoneVerificationService.isInScope(
          settings: on(null),
          accountCreatedAt: DateTime.utc(2026, 12, 25),
        ),
        isFalse,
      );
    });

    test('계정 생성 시각을 모르면 대상이 아니다 — 옛 계정일 수 있다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: null,
        ),
        isFalse,
      );
    });
  });

  group('기준 시각을 사이에 둔 경계', () {
    test('기준보다 하루 앞서 만든 계정은 기존 회원이다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: cutoff.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    });

    test('1밀리초만 앞서도 기존 회원이다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: cutoff.subtract(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });

    test('📌 기준 시각과 정확히 같으면 신규다 — 경계는 이쪽에 붙인다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: cutoff,
        ),
        isTrue,
      );
    });

    test('기준보다 뒤에 만든 계정은 신규다', () {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: cutoff.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });

  test('⚠️ 표준시가 달라도 같은 순간이면 같게 판정한다', () {
    // Firebase Auth 의 creationTime 은 UTC 로 오지만, 콘솔에서 손으로 넣는
    // enforceFrom 은 현지 시각으로 들어올 수 있다. 두 값을 그냥 비교하면
    // 9시간이 어긋나 **하루치 가입자가 반대로 갈린다.**
    final utcMoment = DateTime.utc(2026, 9, 9, 0, 0);
    final sameMomentInKst = DateTime.parse('2026-09-09T09:00:00+09:00');

    expect(
      PhoneVerificationService.isInScope(
        settings: on(sameMomentInKst),
        accountCreatedAt: utcMoment,
      ),
      isTrue,
      reason: '같은 순간이므로 「기준과 같음」 → 신규',
    );
    expect(
      PhoneVerificationService.isInScope(
        settings: on(sameMomentInKst),
        accountCreatedAt: utcMoment.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
  });

  test('🚨 기존 테스터가 오늘 로그인해도 대상이 아니다', () {
    // 이 저장소의 테스터들은 2026-08 에 가입했다. 시행일을 9/9 로 두면
    // 스위치를 켜도 이분들은 인증 화면을 보지 않아야 한다 — 방침이
    // 「기존 회원의 처리는 달라지지 않는다」고 약속하기 때문이다.
    for (final joined in [
      DateTime.utc(2026, 8, 1),
      DateTime.utc(2026, 8, 24),
      DateTime.utc(2026, 9, 8, 23, 59, 59),
    ]) {
      expect(
        PhoneVerificationService.isInScope(
          settings: on(cutoff),
          accountCreatedAt: joined,
        ),
        isFalse,
        reason: '$joined 가입자는 기존 회원이다',
      );
    }
  });
}
