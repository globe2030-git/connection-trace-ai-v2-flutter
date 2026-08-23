// GroupsRepository — 그룹 CRUD + 로컬 저장(암호화/평문) 왕복(추가 427).
//
// 서버 백업 호출(DataBackupService.backupGroups/restoreGroups)은 Firestore를
// 부르는데, 테스트 환경엔 Firebase가 초기화돼 있지 않다 — 하지만 그 호출은
// try/catch로 감싸여 있어(data_backup_service.dart) 실패해도 조용히
// 삼켜진다. `data_encryption_test.dart`의 ContactsRepository 테스트가 이미
// 같은 전제로 uid를 넣어 테스트하고 있어 같은 패턴을 따른다.
import 'dart:convert';

import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_groups_v1');
      expect(raw, isNotNull);
      expect(raw, contains('그룹A'));

      final reloaded = GroupsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reloaded.groups.map((g) => g.name), ['그룹A']);
    });

    test('⭐ 로그인 상태(uid 있음)로 저장하면 그룹명이 평문으로 노출되지 않는다', () async {
      final repo = GroupsRepository();
      await repo.setCurrentUid('owner-uid');
      repo.createGroup('민감한그룹이름');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_groups_v1');
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
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.groups, hasLength(1));
      expect(repo.groups.first.name, '옛그룹');

      final prefsBefore = await SharedPreferences.getInstance();
      expect(prefsBefore.getString('saved_groups_v1'), contains('옛그룹'));

      await repo.setCurrentUid('new-uid');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final prefsAfter = await SharedPreferences.getInstance();
      expect(prefsAfter.getString('saved_groups_v1'), isNot(contains('옛그룹')));
      // 메모리 값은 그대로 유지된다.
      expect(repo.groups.first.name, '옛그룹');
    });

    test('손상된 저장분은 크래시 없이 빈 목록으로 시작한다', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.saved_groups_v1': 'not-json-not-base64-garbage!!!',
      });
      final repo = GroupsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.groups, isEmpty);

      await repo.setCurrentUid('some-uid');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.groups, isEmpty);
    });
  });

  group('clearLocal', () {
    test('로컬 그룹 목록을 비운다', () async {
      final repo = GroupsRepository();
      repo.createGroup('그룹A');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await repo.clearLocal();

      expect(repo.groups, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_groups_v1'), isNull);
    });
  });
}
