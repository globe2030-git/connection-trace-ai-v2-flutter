// 관리자 회차 지급이 실패했을 때 **무슨 문구가 뜨나**(추가 338).
//
// ⚠️ 지급 자체는 여기서 못 본다 — 배포된 Cloud Functions를 부른다. 이 테스트가
// 지키는 것은 **관리자가 고칠 수 있는 실패와 그렇지 않은 실패를 갈라 보여
// 주는가**이다. 뭉뚱그리면 "탈퇴한 계정"과 "회차 한도 초과"가 같은 문구로 보여
// 응대가 막힌다(추가 178에서 조회 쪽이 같은 이유로 갈렸다).
import 'package:connection_trace_ai_flutter/core/services/ai_usage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('실패 갈래마다 다른 문구가 나온다', () {
    test('관리자가 아님', () {
      const e = AdminUsageException(AdminUsageError.notAdmin);
      expect(e.message, contains('관리자'));
    });

    test('계정 없음 — 탈퇴·이메일 다름을 함께 알려 준다', () {
      const e = AdminUsageException(AdminUsageError.accountNotFound);
      expect(e.message, contains('탈퇴'));
    });

    test('이메일 없음', () {
      const e = AdminUsageException(AdminUsageError.noEmail);
      expect(e.message, contains('이메일'));
    });

    test('네 갈래가 서로 다른 문구다', () {
      final all = AdminUsageError.values
          .map((r) => AdminUsageException(r).message)
          .toSet();
      expect(all, hasLength(AdminUsageError.values.length));
    });
  });

  group('⚠️ 지급 검사 실패는 서버 문구를 그대로 보여 준다', () {
    // 한도·사유는 **서버가 이유를 정확히 안다.** 앱이 문구를 다시 쓰면 두 벌이
    // 되어, 서버 한도를 바꿔도 앱은 옛 숫자를 말한다.
    test('서버가 준 문구가 있으면 그것을 쓴다', () {
      const e = AdminUsageException(
        AdminUsageError.invalidGrant,
        message: '1회 지급/회수는 100회를 넘을 수 없습니다.',
      );
      expect(e.message, '1회 지급/회수는 100회를 넘을 수 없습니다.');
    });

    test('서버 문구가 없으면 기본 안내로 물러난다', () {
      const e = AdminUsageException(AdminUsageError.invalidGrant);
      expect(e.message, isNotEmpty);
      expect(e.message, contains('확인'));
    });

    test('다른 갈래는 서버 문구를 받아도 무시한다 — 개인정보가 섞일 수 있다', () {
      const e = AdminUsageException(
        AdminUsageError.accountNotFound,
        message: 'user@example.com not found',
      );
      expect(e.message, isNot(contains('example.com')));
    });
  });
}
