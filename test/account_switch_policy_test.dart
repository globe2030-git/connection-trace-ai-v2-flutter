import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/account_switch_policy.dart';

/// ⚠️ 이 규칙이 무너지면 **남의 명함이 다른 계정 서버로 올라간다.**
///
/// 2026-08-21 실측: 구글 → 카카오 → 네이버로 연속 전환하니 같은 명함 95건이
/// **세 계정 서버에 전부** 존재하게 됐다. 명함은 제3자(명함 주인)의
/// 개인정보라, 두 계정이 다른 사람이면 근거 없는 제3자 제공이 된다.
void main() {
  group('계정 전환 뒤 서버로 올려도 되는가', () {
    test('전환이 아니면 올려도 된다 — 자기 데이터다', () {
      expect(
        mayMigrateToServer(
          lastUidKnown: true,
          isAccountSwitch: false,
          replaced: false,
        ),
        isTrue,
      );
    });

    test('⚠️ 전환 + "유지"는 올리면 안 된다 — 이전 계정 명함이다', () {
      // 이 한 줄이 결함의 핵심이었다.
      expect(
        mayMigrateToServer(
          lastUidKnown: true,
          isAccountSwitch: true,
          replaced: false,
        ),
        isFalse,
      );
    });

    test('전환 + "교체"는 올려도 된다 — 이미 이 계정 데이터로 갈아 끼운 뒤다', () {
      expect(
        mayMigrateToServer(
          lastUidKnown: true,
          isAccountSwitch: true,
          replaced: true,
        ),
        isTrue,
      );
    });

    test('⚠️ 이전 계정을 모르면 올리지 않는다 — 전환인지 아닌지 모른다', () {
      // 저장소 읽기에 실패하는 경로. 법무 회신에는 없던 자리인데,
      // 코드를 고치다 찾았다. 모를 때는 안전한 쪽으로 둔다.
      for (final replaced in [true, false]) {
        for (final isSwitch in [true, false]) {
          expect(
            mayMigrateToServer(
              lastUidKnown: false,
              isAccountSwitch: isSwitch,
              replaced: replaced,
            ),
            isFalse,
            reason: '마지막 계정을 모르면 어떤 조합에서도 올리지 않는다',
          );
        }
      }
    });

    test('⚠️ "유지"는 교체 여부만으로 갈린다 — 전환 자체는 허용 사유가 아니다', () {
      // 실측에서 세 계정에 사본이 생긴 것은 전환할 때마다 이 판정이
      // 없었기 때문이다. 전환이 반복돼도 "유지"인 한 계속 막혀야 한다.
      expect(
        mayMigrateToServer(
          lastUidKnown: true,
          isAccountSwitch: true,
          replaced: false,
        ),
        isFalse,
      );
    });
  });
}
