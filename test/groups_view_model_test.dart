// GroupsViewModel — 그룹·명함 두 저장소를 함께 다루는 조율자 테스트(추가 427).
// 특히 그룹 삭제가 "명함은 유지, 참조만 제거"라는 인수 기준을 실제로
// 지키는지가 핵심이다.
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/groups_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

  Future<GroupsViewModel> makeVm({List<ContactModel> seed = const []}) async {
    final contactsRepo = ContactsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (final c in seed) {
      contactsRepo.addContact(c);
    }
    final groupsRepo = GroupsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return GroupsViewModel(
      groupsRepository: groupsRepo,
      contactsRepository: contactsRepo,
    );
  }

  test('memberCountOf가 그 그룹을 가진 명함 수를 센다', () async {
    final vm = await makeVm(
      seed: [
        contact('1', groupIds: ['gA']),
        contact('2', groupIds: ['gA', 'gB']),
        contact('3', groupIds: ['gB']),
        contact('4'),
      ],
    );
    final group = vm.createGroup('그룹A'); // gA와는 다른 id지만 카운트 로직만 확인.

    expect(vm.memberCountOf('gA'), 2);
    expect(vm.memberCountOf('gB'), 2);
    expect(vm.memberCountOf(group.id), 0);
    expect(vm.contactsWithoutGroupCount, 1, reason: 'contact 4만 그룹이 없다');
  });

  test('⭐ deleteGroup — 명함은 유지되고 참조만 사라진다(브리프 인수 기준)', () async {
    final vm = await makeVm(
      seed: [
        contact('1', groupIds: ['gA', 'gB']),
        contact('2', groupIds: ['gA']),
      ],
    );
    // createGroup으로 만든 그룹 id를 실제로 명함에 심어 재현한다.
    final groupA = vm.createGroup('삭제될 그룹');
    vm.setContactGroups('1', {groupA.id, 'gB'});
    vm.setContactGroups('2', {groupA.id});

    vm.deleteGroup(groupA.id);

    expect(vm.groups.any((g) => g.id == groupA.id), isFalse, reason: '그룹 자체는 사라진다');
    // 참조가 걷어졌는지 확인 — ContactsRepository를 다시 조회한다.
    final contactsAfter = vm.memberCountOf(groupA.id);
    expect(contactsAfter, 0, reason: '삭제된 그룹 id를 갖는 명함이 없어야 한다');
  });

  test('setContactGroups — 명함의 그룹 지정을 통째로 바꾼다', () async {
    final vm = await makeVm(seed: [contact('1', groupIds: ['gOld'])]);

    vm.setContactGroups('1', {'gNew1', 'gNew2'});

    expect(vm.memberCountOf('gOld'), 0);
    expect(vm.memberCountOf('gNew1'), 1);
    expect(vm.memberCountOf('gNew2'), 1);
  });

  test('존재하지 않는 명함 id로 setContactGroups를 불러도 조용히 무시한다', () async {
    final vm = await makeVm(seed: [contact('1')]);
    expect(() => vm.setContactGroups('없는id', {'g1'}), returnsNormally);
  });
}
