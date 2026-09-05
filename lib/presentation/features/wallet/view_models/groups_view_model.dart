import 'package:flutter/foundation.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../data/repositories/groups_repository.dart';

/// 명함 그룹(추가 427) — 그룹 목록과 "어느 명함이 어느 그룹인지"를 함께
/// 다루는 조율자.
///
/// [GroupsRepository]는 그룹이 무엇인지(이름·생성일)만 알고, 소속 명함은
/// `ContactModel.groupIds`(ContactsRepository 쪽)에 있다 — 그래서 두
/// 저장소를 같이 보는 자리가 필요하다. 특히 그룹 삭제는 **참조까지 지워야**
/// 한다(브리프 인수 기준: "삭제 시 명함은 유지, 참조만 제거").
class GroupsViewModel extends ChangeNotifier {
  final GroupsRepository _groupsRepository;
  final ContactsRepository _contactsRepository;
  bool _isDisposed = false;

  // 초기화 형식 인자(this._groupsRepository 등)로 바꾸면 생성자의 공개
  // 매개변수 이름이 `_groupsRepository`/`_contactsRepository`가 되어 버려
  // main.dart 등 호출부의 named-argument 이름(groupsRepository,
  // contactsRepository)이 깨진다 — 이 저장소의 기존 관례를 그대로 따른다
  // (card_photo_backup_service.dart도 같은 이유로 이 lint를 무시한다).
  // `ignore:` 주석은 바로 다음 줄에만
  // 적용되므로 초기화 목록 각 줄마다 붙인다.
  GroupsViewModel({
    required GroupsRepository groupsRepository,
    required ContactsRepository contactsRepository,
    // ignore: prefer_initializing_formals
  }) : _groupsRepository = groupsRepository,
       // ignore: prefer_initializing_formals
       _contactsRepository = contactsRepository {
    _groupsRepository.addListener(_safeNotify);
    _contactsRepository.addListener(_safeNotify);
  }

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _groupsRepository.removeListener(_safeNotify);
    _contactsRepository.removeListener(_safeNotify);
    super.dispose();
  }

  /// 이름 가나다순으로 정렬해 돌려준다 — 만든 순서 그대로면 칩 순서가
  /// 매번 바뀌어(최근 만든 게 뒤에 붙음) 찾기 어렵다.
  List<GroupModel> get groups {
    final list = [..._groupsRepository.groups];
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// 그룹 id → 소속 명함 수.
  int memberCountOf(String groupId) => _contactsRepository.contacts
      .where((c) => c.groupIds.contains(groupId))
      .length;

  /// 그룹이 하나도 지정되지 않은 명함 수 — "전체에서만 보인다"는 안내에 쓴다.
  int get contactsWithoutGroupCount =>
      _contactsRepository.contacts.where((c) => c.groupIds.isEmpty).length;

  GroupModel createGroup(String name) => _groupsRepository.createGroup(name);

  void renameGroup(String id, String newName) =>
      _groupsRepository.renameGroup(id, newName);

  /// 그룹을 지우고, 이 그룹을 참조하던 모든 명함에서 그 참조만 걷어낸다.
  /// 명함 자체와 다른 정보는 그대로 둔다(브리프 인수 기준).
  void deleteGroup(String id) {
    _groupsRepository.deleteGroup(id);
    for (final c in _contactsRepository.contacts) {
      if (!c.groupIds.contains(id)) continue;
      _contactsRepository.updateContact(
        c.copyWith(groupIds: c.groupIds.where((g) => g != id).toList()),
      );
    }
  }

  /// 한 명함의 그룹 지정을 통째로 바꾼다(그룹 지정 바텀시트에서 "확인"을
  /// 눌렀을 때). 새 명함 등록 중(아직 저장소에 없는 id)이면 아무 일도 하지
  /// 않는다 — 그 경우는 호출부(등록 폼)가 로컬 상태로만 들고 있다가 저장
  /// 시점에 [ContactModel.groupIds]에 함께 실어 보낸다.
  void setContactGroups(String contactId, Set<String> groupIds) {
    final matches = _contactsRepository.contacts.where(
      (c) => c.id == contactId,
    );
    if (matches.isEmpty) return;
    _contactsRepository.updateContact(
      matches.first.copyWith(groupIds: groupIds.toList()),
    );
  }
}
