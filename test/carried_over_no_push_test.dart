/// 「유지」로 넘어온 명함을 **새 계정 서버로 올리지 않는다**(2026-08-28, 추가 556).
///
/// ## 무엇이 문제였나 — 보호 장치가 반쪽만 막고 있었다
///
/// 계정 전환에서 「유지」를 고르면 명함 본문을 새 계정 서버로 **일부러 안
/// 올린다**(`mayMigrateToServer`). 🚨 **그런데 그 보호는 일회성 마이그레이션
/// 하나에만 걸려 있었다.** 전환하는 그 실행에서는 안 올리지만, 그때 *"마지막
/// 로그인 계정"*이 새 계정으로 갱신되므로 **다음에 앱을 켜면 평범한 로그인
/// 동기화(`syncWithServer`)로 들어가고, 거기서 그대로 올라갔다.**
///
/// ✅ **실물로 확인**(서버 실물 조회 · 건수만): 폴드는 「유지」 전환 뒤 **새
/// 명함을 하나도 등록하지 않았는데**(사용자 확인) 같은 시간대에 서버 명함이
/// **103건**이 됐다. 아이폰은 「유지」 2회 뒤 195건.
///
/// ⚠️ **여기서 틀리면 제3자(명함 주인) 개인정보가 남의 계정 서버로 나간다.**
/// 되돌리기 어려운 방향이라 규칙을 자동 검사로 고정한다.
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/carried_over_contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

({String id}) row(String id) => (id: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('무엇을 올릴지 고르는 규칙', () {
    test('⭐ 넘어온 명함은 뺀다', () {
      final out = selectPushTargets(
        [row('a'), row('b'), row('c')],
        {'b'},
        idOf: (r) => r.id,
      );
      expect(out.map((r) => r.id), ['a', 'c']);
    });

    test('표시가 없으면 예전과 똑같이 전부 올린다', () {
      final out = selectPushTargets(
        [row('a'), row('b')],
        <String>{},
        idOf: (r) => r.id,
      );
      expect(out.length, 2);
    });

    test('🚨 전부 넘어온 것이면 한 건도 안 올린다 — 폴드가 이 경우였다', () {
      final out = selectPushTargets(
        [row('a'), row('b')],
        {'a', 'b'},
        idOf: (r) => r.id,
      );
      expect(out, isEmpty);
    });
  });

  group('표시를 기억한다', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('적고 읽는다', () async {
      final svc = CarriedOverContactsService();
      await svc.markAll(['a', 'b']);
      expect(await svc.load(), {'a', 'b'});
    });

    test('⚠️ 덧붙인다 — 전환을 두 번 하면 앞 표시가 사라지면 안 된다', () async {
      final svc = CarriedOverContactsService();
      await svc.markAll(['a']);
      await svc.markAll(['b']);
      expect(await svc.load(), {'a', 'b'});
    });

    test('비우면 없어진다 — 「교체」·탈퇴에서 부른다', () async {
      final svc = CarriedOverContactsService();
      await svc.markAll(['a']);
      await svc.clear();
      expect(await svc.load(), isEmpty);
    });

    test('빈 목록은 아무것도 안 적는다', () async {
      final svc = CarriedOverContactsService();
      await svc.markAll(const []);
      expect(await svc.load(), isEmpty);
    });
  });

  group('부르는 곳이 있나 — 규칙만 맞고 아무도 안 부르면 소용이 없다', () {
    test('🚨 동기화가 이 규칙을 거친다 — 여기가 실제로 샜던 자리다', () {
      final src = File(
        'lib/data/repositories/contacts_repository.dart',
      ).readAsStringSync();
      final fn = src.substring(src.indexOf('Future<void> syncWithServer'));
      final body = fn.substring(0, fn.indexOf('\n  /// 주소는 있는데'));
      expect(body.contains('selectPushTargets'), isTrue);
      // 거르지 않은 목록을 그대로 올리던 옛 모습이 남아 있으면 안 된다.
      expect(body.contains('for (final c in outcome.toPush)'), isFalse);
    });

    test('「유지」를 고르면 표시하고, 「교체」를 고르면 비운다', () {
      final src = File(
        'lib/presentation/common/auth_gate.dart',
      ).readAsStringSync();
      expect(src.contains('CarriedOverContactsService().markAll'), isTrue);
      expect(src.contains('CarriedOverContactsService().clear()'), isTrue);
    });

    test('탈퇴하면 비운다 — 다음 계정이 자기 명함을 못 올리면 안 된다', () {
      final src = File(
        'lib/presentation/features/settings/views/settings_view.dart',
      ).readAsStringSync();
      expect(src.contains('CarriedOverContactsService().clear()'), isTrue);
    });
  });
}
