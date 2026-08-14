import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/ai_usage_service.dart';

/// `AiUsage`의 잔여 횟수 계산 규칙을 검증한다. 특히 `bonusCredits`(관리자가
/// 지급하는, 만료 없는 보너스 회차)가 `exhausted`/`totalRemaining`/
/// `lowBalance` 판정에 올바르게 반영되는지가 핵심이다 — 이 값이 틀리면
/// 실제로는 서버가 요청을 허용하는데도 화면이 "한도 소진"이라고 잘못 보여준다.
void main() {
  group('AiUsage', () {
    test('보너스가 없으면 기존 무료 한도 로직과 동일하다', () {
      const usage = AiUsage(dailyUsed: 20, monthlyUsed: 5);
      expect(usage.remaining, 0);
      expect(usage.totalRemaining, 0);
      expect(usage.exhausted, isTrue);
      expect(usage.lowBalance, isFalse);
    });

    test('무료 한도를 다 썼어도 보너스가 있으면 exhausted가 아니다', () {
      const usage = AiUsage(dailyUsed: 20, monthlyUsed: 5, bonusCredits: 3);
      expect(usage.remaining, 0);
      expect(usage.totalRemaining, 3);
      expect(usage.exhausted, isFalse);
      expect(usage.lowBalance, isTrue);
    });

    test('무료 잔여와 보너스를 합산한 값이 5 미만이면 lowBalance', () {
      const usage = AiUsage(dailyUsed: 18, monthlyUsed: 0, bonusCredits: 0);
      expect(usage.remaining, 2);
      expect(usage.totalRemaining, 2);
      expect(usage.lowBalance, isTrue);
      expect(usage.exhausted, isFalse);
    });

    test('무료 잔여가 넉넉하면 보너스가 있어도 lowBalance가 아니다', () {
      const usage = AiUsage(dailyUsed: 0, monthlyUsed: 0, bonusCredits: 10);
      expect(usage.remaining, 20);
      expect(usage.totalRemaining, 30);
      expect(usage.lowBalance, isFalse);
      expect(usage.exhausted, isFalse);
    });

    test('보너스와 무료 잔여가 모두 0이면 exhausted이고 lowBalance는 아니다', () {
      const usage = AiUsage(dailyUsed: 20, monthlyUsed: 100, bonusCredits: 0);
      expect(usage.totalRemaining, 0);
      expect(usage.exhausted, isTrue);
      expect(usage.lowBalance, isFalse);
    });
  });

  // wallet 모드(2026-08-14, U4): `config/billing.model == 'wallet'`일 때의
  // 계산 규칙. dailyUsed/monthlyUsed/bonusCredits는 이 모드에서 화면 표시에
  // 쓰이지 않지만(오늘 사용 횟수 표시에는 dailyUsed를 그대로 쓴다),
  // totalRemaining/exhausted/lowBalance 판정에는 전혀 관여하지 않는다는
  // 것도 함께 검증한다 — freeBalance/paidBalance만으로 결정돼야 한다.
  group('AiUsage — wallet 모드', () {
    test('무료체험 잔액 + 충전 잔액을 합산한다', () {
      const usage = AiUsage(
        dailyUsed: 3,
        monthlyUsed: 3,
        isWalletMode: true,
        freeBalance: 4,
        paidBalance: 10,
      );
      expect(usage.totalRemaining, 14);
      expect(usage.exhausted, isFalse);
      expect(usage.lowBalance, isFalse);
    });

    test('합산 잔액이 5 미만이면 lowBalance', () {
      const usage = AiUsage(
        dailyUsed: 0,
        monthlyUsed: 0,
        isWalletMode: true,
        freeBalance: 2,
        paidBalance: 1,
      );
      expect(usage.totalRemaining, 3);
      expect(usage.lowBalance, isTrue);
      expect(usage.exhausted, isFalse);
    });

    test('합산 잔액이 0이면 exhausted이고 lowBalance는 아니다', () {
      const usage = AiUsage(
        dailyUsed: 0,
        monthlyUsed: 0,
        isWalletMode: true,
        freeBalance: 0,
        paidBalance: 0,
      );
      expect(usage.totalRemaining, 0);
      expect(usage.exhausted, isTrue);
      expect(usage.lowBalance, isFalse);
    });

    test(
      'reset 모드 전용 필드(dailyUsed/monthlyUsed/bonusCredits)는 '
      'wallet 모드 판정에 영향을 주지 않는다',
      () {
        // dailyUsed/monthlyUsed가 한도를 넘겨 reset 모드였다면 exhausted가
        // 됐을 값이지만, isWalletMode가 참이면 freeBalance/paidBalance만
        // 본다 — 두 값 다 넉넉하므로 exhausted가 아니어야 한다.
        const usage = AiUsage(
          dailyUsed: 999,
          monthlyUsed: 999,
          bonusCredits: 0,
          isWalletMode: true,
          freeBalance: 5,
          paidBalance: 5,
        );
        expect(usage.totalRemaining, 10);
        expect(usage.exhausted, isFalse);
        expect(usage.lowBalance, isFalse);
      },
    );

    test('wallet 모드 기본값(필드 생략)은 잔액 0 → exhausted', () {
      const usage = AiUsage(dailyUsed: 0, monthlyUsed: 0, isWalletMode: true);
      expect(usage.totalRemaining, 0);
      expect(usage.exhausted, isTrue);
    });

    test('isWalletMode 기본값은 false(reset)다', () {
      const usage = AiUsage(dailyUsed: 0, monthlyUsed: 0);
      expect(usage.isWalletMode, isFalse);
    });
  });
}
