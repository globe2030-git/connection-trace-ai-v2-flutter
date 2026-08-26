// 그룹 기능(추가 427) 노출 스위치(kGroupsFeatureEnabled) 고정 테스트.
//
// 배경: 그룹 데이터 수집을 새로 고지하는 방침 v2.3의 시행일이 2026-08-30인데,
// 테스터 배포는 그보다 먼저(2026-08-24) 나간다. 시행일 전 빌드에서는 그룹
// UI가 보이면 안 된다(사용자 확정 ㉯안) — 그래서 이 스위치로 화면만 숨긴다.
//
// ⚠️ 데이터는 건드리지 않는다는 것이 이 작업의 핵심 제약이다. 그래서 여기서는
// 셋을 함께 고정한다.
//   1. 꺼짐이 기본이다(정의 없는 빌드에서 false) — 실수로 켜진 채 배포되면
//      안 된다.
//   2. 데이터·저장소 계층(GroupsRepository·ContactsRepository·
//      GroupsViewModel·DataBackupService)은 이 스위치를 **아예 모른다** —
//      소스에 참조가 없다는 것 자체를 테스트로 박아 둔다. 누군가 나중에
//      "화면도 숨겼으니 저장도 막자"는 생각으로 저장소 코드에 이 플래그를
//      끌어들이면, 꺼진 빌드에서 만든 그룹이 다음 빌드(플래그 켠 뒤)에서
//      복원되지 않는 사고로 이어진다 — 그 경로를 구조적으로 막는다.
//   3. 꺼진 상태에서도(= 지금 이 테스트 실행 환경 그대로) 그룹 생성·명함
//      지정·백업 직렬화가 평소와 동일하게 동작한다 — UI만 숨겼지 로직은
//      "켜짐 시 기존 동작"과 다르지 않다는 것을 보여준다.
import 'dart:io';

import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/models/group_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/groups_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('⚠️ 빌드 스위치 기본값', () {
    test('✅ 2026-08-26부터 기본으로 켜져 있다', () {
      // 종전에는 꺼짐이 기본이었고, 그 근거는 "방침 v2.3 시행일 전에 실수로
      // 켜진 채 배포되면 안 된다"였다.
      //
      // 사용자 확정(2026-08-26): 테스트 기간에는 열어 둔다. 게이트를 방침
      // 시행일에 묶어 두었더니 **이용자가 없는데 개발만 막혔다.** 시행일은
      // 일반 사용자 배포 시점에 맞춰 다시 잡았다.
      //
      // ⚠️ 아래 둘(저장소 계층이 이 스위치를 모른다 · 꺼져 있어도 로직은
      // 동일하다)은 그대로 유효하다 — 오히려 이제 그 성질 덕분에 켜도
      // 데이터가 안 흔들린다.
      expect(kGroupsFeatureEnabled, isTrue);
    });
  });

  group('⚠️ 데이터 계층은 이 스위치를 몰라야 한다(소스 참조 0건)', () {
    // 저장·복원·백업 코드에 kGroupsFeatureEnabled가 섞여 들어가면, 화면을
    // 숨긴 빌드에서 만든 그룹이 저장/복원 경로에서도 함께 막혀 데이터를 잃을
    // 위험이 생긴다. lib/presentation(화면) 바깥에서는 이 상수를 참조하지
    // 않는다는 것을 소스 검사로 고정한다.
    final dataLayerFiles = [
      'lib/data/repositories/groups_repository.dart',
      'lib/data/repositories/contacts_repository.dart',
      'lib/data/services/data_backup_service.dart',
      'lib/presentation/features/wallet/view_models/groups_view_model.dart',
      'lib/presentation/features/wallet/view_models/wallet_view_model.dart',
    ];

    for (final path in dataLayerFiles) {
      test('$path 는 kGroupsFeatureEnabled를 참조하지 않는다', () {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '경로가 바뀌었으면 이 목록도 갱신할 것');
        expect(file.readAsStringSync(), isNot(contains('kGroupsFeatureEnabled')));
      });
    }
  });

  group('꺼진 상태에서도 그룹 생성·명함 지정·백업 직렬화는 평소와 같다', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    ContactModel contact(String id, {List<String> groupIds = const []}) =>
        ContactModel(
          id: id,
          name: '인맥$id',
          company: '',
          title: '',
          phone: '010-0000-$id',
          email: '$id@test.com',
          tags: const [],
          talkingPoints: const [],
          groupIds: groupIds,
        );

    test('그룹 생성 → 명함 지정 → 그룹 삭제 시 참조만 걷힌다(UI 노출과 무관)', () async {
      final contactsRepo = ContactsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      contactsRepo.addContact(contact('1'));
      final groupsRepo = GroupsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final vm = GroupsViewModel(
        groupsRepository: groupsRepo,
        contactsRepository: contactsRepo,
      );

      final group = vm.createGroup('보험설계사');
      vm.setContactGroups('1', {group.id});
      expect(
        contactsRepo.contacts.single.groupIds,
        [group.id],
        reason: '화면 스위치는 조회·지정 로직에 관여하지 않는다',
      );

      vm.deleteGroup(group.id);
      expect(vm.groups, isEmpty);
      expect(
        contactsRepo.contacts.single.groupIds,
        isEmpty,
        reason: '명함 자체는 남고 참조만 지워져야 한다(브리프 인수 기준)',
      );
    });

    test('오늘 이미 만든 그룹은 백업 직렬화(toBackupJson)에 그대로 실린다', () async {
      final c = contact('1', groupIds: ['g_today']);
      final backup = c.toBackupJson();

      expect(
        backup['groupIds'],
        ['g_today'],
        reason:
            '스위치를 끈 빌드로 배포해도 오늘 실기기로 만든 그룹은 백업·복원 '
            '경로에 그대로 흘러야 한다(화면만 숨긴다는 이 작업의 제약)',
      );

      final restored = ContactModel.fromJson(backup);
      expect(restored.groupIds, ['g_today']);
    });

    test('GroupModel 자체의 직렬화도 스위치와 무관하다', () {
      final group = GroupModel(
        id: 'g1',
        name: '삼성전자 사람들',
        createdAt: DateTime(2026, 8, 23),
      );
      final restored = GroupModel.fromJson(group.toJson());
      expect(restored.name, '삼성전자 사람들');
      expect(restored.id, 'g1');
    });
  });
}
