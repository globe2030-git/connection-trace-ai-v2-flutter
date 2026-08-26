// GroupsRepository — 그룹 CRUD + 로컬 저장(암호화/평문) 왕복(추가 427).
//
// 서버 백업 호출(DataBackupService.backupGroups/restoreGroups)은 Firestore를
// 부르는데, 테스트 환경엔 Firebase가 초기화돼 있지 않다 — 하지만 그 호출은
// try/catch로 감싸여 있어(data_backup_service.dart) 실패해도 조용히
// 삼켜진다. `data_encryption_test.dart`의 ContactsRepository 테스트가 이미
// 같은 전제로 uid를 넣어 테스트하고 있어 같은 패턴을 따른다.
//
// ---
//
// 🚨 2026-08-26 — 이 파일이 main 을 여섯 시간 빨갛게 세웠다. 두 가지가 겹쳤다.
//
// **① 바인딩을 안 켰다.** `main()` 첫 줄에
// `TestWidgetsFlutterBinding.ensureInitialized()` 가 없었다. 이 파일은
// `testWidgets` 를 하나도 안 쓰므로 자동으로도 안 켜진다. 그래서 CI 로그에
// *"Binding has not yet been initialized"* 가 반복해서 찍혔고, 기기 보안
// 저장소(암호화 키) 접근이 조용히 실패했다.
//
// **② 저장이 끝나기를 시간으로 기다렸다.** `await Future.delayed(20~30ms)`.
// 추가 481(#540)에서 **암호화를 `compute()` 아이솔레이트로 옮기면서**
// 아이솔레이트를 띄우는 비용이 붙어 저장이 느려졌다. 30ms 로는 모자랐다.
//
// 📌 그래서 **개발용 맥에서는 통과하고 CI(ubuntu)에서만 실패**했다. 로컬
// 전체 1401건은 그동안 내내 초록이었다. 실패한 것이 하필
// *"그룹명이 평문으로 노출되지 않는다"* 여서 더 나빴다 — 저장 자체가 안 돼
// `raw` 가 null 이었으므로, **평문인지 아닌지는 확인된 바가 없는 상태**로
// 여섯 시간이 지났다. 「빨간불」이 아니라 「모르는 상태」였다.
//
// ⚠️ **고정 대기는 "얼마나 걸리는지 안다"고 가정한다.** 그 가정이 다른
// 커밋의 성능 개선으로 깨졌고, 깨진 것이 느린 기계에서만 보였다.
// → [_waitUntil] 로 **조건이 만족될 때까지** 기다린다.
import 'dart:convert';

import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [condition] 이 참이 될 때까지 기다린다. 고정 대기를 대신한다.
///
/// 시간이 다 되어도 **여기서 실패를 던지지 않는다** — 뒤따르는 `expect` 가
/// 무엇이 틀렸는지 훨씬 잘 설명하기 때문이다. 여기서 던지면 "시간이 지났다"
/// 만 남는다.
Future<void> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 로컬에 저장된 원문(암호화됐으면 암호문)을 읽는다.
Future<String?> _savedRaw() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('saved_groups_v1');
}

/// 「그대로 비어 있다」처럼 **조건으로 기다릴 수 없는 자리**에서만 쓴다.
///
/// ⚠️ 여유를 크게 둔다. 원래 20ms 였다가 아이솔레이트 도입으로 깨졌다.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 600));

void main() {
  // 🚨 이 줄이 없어서 main 이 여섯 시간 빨갰다(위 주석). 지우지 말 것.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('그룹 CRUD', () {
    test('createGroup으로 그룹이 생기고 이름이 그대로 저장된다', () {
      final repo = GroupsRepository();
      final group = repo.createGroup('삼성전자 사람들');

      expect(group.name, '삼성전자 사람들');
      expect(repo.groups, hasLength(1));
      expect(repo.groups.first.id, group.id);
    });

    test('⭐ 같은 이름(대소문자·공백 무시)으로 두 번 만들면 새로 안 만들고 기존 것을 돌려준다', () {
      final repo = GroupsRepository();
      final first = repo.createGroup('보험설계사');
      final second = repo.createGroup('  보험설계사  ');
      final third = repo.createGroup('보험설계사'.toUpperCase());

      expect(repo.groups, hasLength(1));
      expect(second.id, first.id);
      expect(third.id, first.id);
    });

    test('이름이 다르면 별개 그룹이 생긴다', () {
      final repo = GroupsRepository();
      repo.createGroup('그룹A');
      repo.createGroup('그룹B');

      expect(repo.groups, hasLength(2));
      expect(repo.groups.map((g) => g.name), containsAll(['그룹A', '그룹B']));
    });

    test('renameGroup으로 이름을 바꾼다', () {
      final repo = GroupsRepository();
      final group = repo.createGroup('옛 이름');

      repo.renameGroup(group.id, '새 이름');

      expect(repo.groups.single.name, '새 이름');
      expect(repo.groups.single.id, group.id, reason: 'id는 바뀌지 않는다');
    });

    test('renameGroup에 빈 이름을 주면 무시한다', () {
      final repo = GroupsRepository();
      final group = repo.createGroup('원래 이름');

      repo.renameGroup(group.id, '   ');

      expect(repo.groups.single.name, '원래 이름');
    });

    test('deleteGroup으로 그룹 자체가 사라진다', () {
      final repo = GroupsRepository();
      final a = repo.createGroup('그룹A');
      repo.createGroup('그룹B');

      repo.deleteGroup(a.id);

      expect(repo.groups, hasLength(1));
      expect(repo.groups.single.name, '그룹B');
    });
  });

  group('로컬 저장 왕복', () {
    test('게스트(uid 없음)로 만든 그룹은 평문으로 저장되고 새 인스턴스에서 그대로 읽힌다', () async {
      final repo = GroupsRepository();
      repo.createGroup('그룹A');
      await _waitUntil(() async => await _savedRaw() != null);

      final raw = await _savedRaw();
      expect(raw, isNotNull);
      expect(raw, contains('그룹A'));

      final reloaded = GroupsRepository();
      await _waitUntil(() async => reloaded.groups.isNotEmpty);
      expect(reloaded.groups.map((g) => g.name), ['그룹A']);
    });

    test('⭐ 로그인 상태(uid 있음)로 저장하면 그룹명이 평문으로 노출되지 않는다', () async {
      final repo = GroupsRepository();
      await repo.setCurrentUid('owner-uid');
      repo.createGroup('민감한그룹이름');
      // 저장이 끝나기를 기다린다. 평문으로 한 번 썼다가 암호문으로 덮는
      // 구현일 수도 있으므로 **평문이 사라질 때까지** 기다린 뒤에 본다.
      // 끝내 평문이면 시간이 다 되고, 그때 아래 expect 가 제대로 실패한다.
      await _waitUntil(() async {
        final v = await _savedRaw();
        return v != null && !v.contains('민감한그룹이름');
      });

      final raw = await _savedRaw();
      expect(raw, isNotNull);
      expect(
        raw,
        isNot(contains('민감한그룹이름')),
        reason: '그룹명은 메모·프로필과 같은 취급 — 암호화돼야 한다(법무 검토 질문 2)',
      );
    });

    test('레거시 평문 저장분은 uid 없이도 읽히고, 로그인 후 자동 암호화된다', () async {
      final legacyJson = jsonEncode([
        {
          'id': 'g_legacy',
          'name': '옛그룹',
          'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
        },
      ]);
      SharedPreferences.setMockInitialValues({
        'flutter.saved_groups_v1': legacyJson,
      });

      final repo = GroupsRepository();
      await _waitUntil(() async => repo.groups.isNotEmpty);
      expect(repo.groups, hasLength(1));
      expect(repo.groups.first.name, '옛그룹');

      expect(await _savedRaw(), contains('옛그룹'));

      await repo.setCurrentUid('new-uid');
      await _waitUntil(() async {
        final v = await _savedRaw();
        return v != null && !v.contains('옛그룹');
      });

      expect(await _savedRaw(), isNot(contains('옛그룹')));
      // 메모리 값은 그대로 유지된다.
      expect(repo.groups.first.name, '옛그룹');
    });

    test('손상된 저장분은 크래시 없이 빈 목록으로 시작한다', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.saved_groups_v1': 'not-json-not-base64-garbage!!!',
      });
      final repo = GroupsRepository();
      // ⚠️ 「그대로 비어 있다」는 조건으로 기다릴 수 없다 — 고정 대기를 쓰되
      //    여유를 크게 둔다.
      await _settle();
      expect(repo.groups, isEmpty);

      await repo.setCurrentUid('some-uid');
      await _settle();
      expect(repo.groups, isEmpty);
    });
  });

  group('clearLocal', () {
    test('로컬 그룹 목록을 비운다', () async {
      final repo = GroupsRepository();
      // ⚠️ 생성자가 띄운 첫 로드가 끝나기를 먼저 기다린다.
      //
      // 🚨 안 기다리면 **실제 경합에 걸린다** — `clearLocal()` 이 메모리를
      //    비운 뒤에 그 로드가 끝나면서 `_groups` 를 디스크 내용으로 다시
      //    덮어쓴다(`groups_repository.dart` 40행이 띄우고 101행이 덮는다).
      //    2026-08-26 에 바인딩을 켜면서 로드가 느려지자 드러났다.
      //    **추가 510 으로 따로 잡는다 — 이 파일에서 고치지 않는다.**
      await _settle();

      repo.createGroup('그룹A');
      await _waitUntil(() async => await _savedRaw() != null);

      await repo.clearLocal();

      expect(repo.groups, isEmpty);
      expect(await _savedRaw(), isNull);
    });
  });
}
