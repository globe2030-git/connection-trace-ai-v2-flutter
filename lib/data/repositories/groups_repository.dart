import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../models/group_model.dart';
import '../services/data_backup_service.dart';

/// 명함 그룹 목록(id·이름·생성일)을 관리한다(추가 427).
///
/// **명함별로 어느 그룹에 속하는지는 여기서 모른다** — 그건
/// `ContactModel.groupIds`에 있다(태그와 같은 취급, 명함 백업 경로에 자연히
/// 실린다). 이 저장소는 "그룹이라는 실체가 무엇인지"(이름·생성일)만 책임진다.
///
/// 저장·암호화·복원 패턴은 [MyProfileRepository]를 그대로 따른다 — 그룹명이
/// 제3자를 특정할 수 있는 자유 입력값이라 프로필과 같은 취급을 받는다(법무
/// 스팟 확인, `docs/planning/group-feature-legal-note-2026-08-23.md` 질문 2).
///
/// ⚠️ 서버 저장 위치는 `users/{uid}` 문서의 암호화 필드다(하위 컬렉션이
/// 아니다) — 같은 문서의 `deleteAllUserData`가 탈퇴 시 통째로 지우므로
/// 별도 파기 코드 없이 자연히 사라진다(법무 검토 질문 3, `deletedContacts`가
/// 이미 겪은 하위 컬렉션 함정을 반복하지 않기 위함).
class GroupsRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_groups_v1';

  List<GroupModel> _groups = [];
  String? _uid;

  final EncryptionKeyService _encryptionKeyService;

  // ⚠️ 로드-쓰기 경합 방지용 세대 번호(추가 510).
  //
  // 생성자가 `_loadFromDisk()`를 **await 없이** 띄우고, `setCurrentUid()`도
  // 실제 호출부(`auth_gate.dart` `_syncUidAndRestore`)에서 **await 없이**
  // 불린다. 그 로드가 끝나기 전에 `clearLocal()`·`forceRestoreFromServer()`
  // 같은 "지금 상태가 곧 정답"인 조작이 먼저 끝나면, 늦게 끝난 로드가 그
  // 결과를 디스크(또는 앞 계정) 내용으로 덮어쓸 수 있다 — 그 로드는 그
  // 조작이 있었다는 것을 모르기 때문이다.
  //
  // `_groups`를 바꾸는 모든 지점에서 이 번호를 올리고, `_loadFromDisk()`는
  // 시작할 때 번호를 기억해 뒀다가 반영 직전에 번호가 그대로인지 확인한다
  // — 그사이 누가 끼어들었으면(번호가 바뀌었으면) 이 로드 결과는 **낡은
  // 것**이므로 버린다.
  int _generation = 0;

  // ContactsRepository/MyProfileRepository와 동일한 지연 로드/마이그레이션
  // 플래그. 로그인 전(uid 없음)에는 암호화 키를 만들 수 없어 평문으로 두고,
  // 로그인 시점에 재로드/재암호화한다.
  bool _pendingEncryptedLoad = false;
  bool _pendingPlaintextMigration = false;

  GroupsRepository({EncryptionKeyService? encryptionKeyService})
    : _encryptionKeyService = encryptionKeyService ?? EncryptionKeyService() {
    _loadFromDisk();
  }

  List<GroupModel> get groups => List.unmodifiable(_groups);

  Future<void> setCurrentUid(String? uid) async {
    _uid = uid;
    if (uid == null) return;
    if (_pendingEncryptedLoad) {
      _pendingEncryptedLoad = false;
      await _loadFromDisk();
    } else if (_pendingPlaintextMigration) {
      _pendingPlaintextMigration = false;
      await _saveToDisk();
    }
  }

  /// 새 기기(또는 재설치)에서 로그인한 뒤, 로컬 그룹이 아직 없을 때만 서버
  /// 백업분을 내려받는다([ContactsRepository.restoreFromServerIfEmpty]와
  /// 같은 규칙 — 이미 로컬에 데이터가 있으면 덮어쓰지 않는다).
  Future<void> restoreFromServerIfEmpty(String uid) async {
    if (_groups.isNotEmpty) return;
    final restored = await DataBackupService.restoreGroups(uid);
    if (restored == null || restored.isEmpty) return;
    _groups = restored;
    _generation++;
    notifyListeners();
    await _saveToDisk();
  }

  /// 계정 전환 안전장치(backlog #50)에서 "현재 계정 데이터로 교체"를 선택했을
  /// 때 쓰는 강제 복원 — 로컬에 그룹이 있어도 무시하고 서버 백업분으로
  /// 덮어쓴다(서버에 없으면 빈 목록).
  Future<void> forceRestoreFromServer(String uid) async {
    final restored = await DataBackupService.restoreGroups(uid);
    _groups = restored ?? [];
    _generation++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_groups.isNotEmpty) {
        await _saveToDisk();
      } else {
        await prefs.remove(_storageKey);
      }
    } catch (e) {
      debugPrint('강제 복원된 그룹 로컬 저장 실패: $e');
    }
  }

  /// 계정 삭제 또는 계정 전환 시 로컬 그룹 목록을 비운다. 서버 데이터는
  /// 건드리지 않는다(호출자가 필요하면 별도로 처리).
  Future<void> clearLocal() async {
    _groups = [];
    _generation++;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing groups: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    // 시작 시점의 세대 번호를 기억해 둔다. 이 로드가 끝나기 전에 다른 곳에서
    // `_groups`를 바꾸면(클리어·강제 복원 등) 번호가 올라가고, 그러면 아래
    // 반영 시점에 "낡은 로드"로 판정해 버린다(추가 510).
    final startGeneration = _generation;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      // 1) 평문 저장분(게스트 상태에서 만든 그룹)인지 먼저 시도한다.
      List<dynamic>? legacyList;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) legacyList = decoded;
      } catch (_) {
        legacyList = null;
      }

      if (legacyList != null) {
        final parsed = legacyList
            .map((j) => GroupModel.fromJson(j as Map<String, dynamic>))
            .toList();
        if (_generation != startGeneration) return; // 낡은 로드 — 버린다.
        _groups = parsed;
        _generation++;
        notifyListeners();
        if (_uid != null) {
          await _saveToDisk();
        } else {
          _pendingPlaintextMigration = true;
        }
        return;
      }

      // 2) 평문 JSON이 아니면 암호화된 payload로 간주한다.
      final uid = _uid;
      if (uid == null) {
        _pendingEncryptedLoad = true;
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(raw, key);
      final jsonList = decoded['groups'] as List<dynamic>? ?? const [];
      final parsed = jsonList
          .map((j) => GroupModel.fromJson(j as Map<String, dynamic>))
          .toList();
      if (_generation != startGeneration) return; // 낡은 로드 — 버린다.
      _groups = parsed;
      _generation++;
      notifyListeners();
    } catch (e) {
      // 복호화 실패(위변조/키 불일치 등)를 포함해 어떤 이유로든 로드에
      // 실패하면 크래시하지 않고 빈 목록으로 시작한다.
      debugPrint('Error loading groups: $e');
      // 🚨 **여기서 멈춰 있었다** (2026-09-05에 찾음).
      //
      // `debugPrint` 는 **릴리스에서 아무 데도 안 나온다.** 화면은 그냥 그룹이
      // 없는 것처럼 보이고 아무 말도 하지 않는다.
      //
      // 🚨 **그리고 오해로 끝나지 않는다.** 빈 목록인 채로 저장이 한 번 돌면
      // [_saveToDisk]가 **못 읽은 암호문을 덮어쓴다.**
      //
      // ```
      // ① 재설치 등으로 기기의 키가 없다
      // ② 서버에서 키를 못 받는다(네트워크) → 새 키가 발급된다
      // ③ 기존 암호문이 안 열린다 → 빈 목록
      // ④ 그룹을 하나 만든다 → 저장이 돌아 새 키로 덮어쓴다
      // ⑤ 🚨 그룹이 진짜로 사라진다
      // ```
      //
      // 📌 **그룹명은 「작은 데이터」가 아니다.** 이용자가 자유롭게 적는 값이라
      // **제3자를 특정할 수 있고**, 그래서 이 파일 머리말이 프로필과 같은
      // 취급을 받는다고 적어 뒀다(법무 스팟 확인).
      //
      // 📌 `ContactsRepository` 가 2026-09-04에 같은 자리를 먼저 막았는데
      // (`localReadFailed`) **셋 중 하나만 고쳐져 있었다.** 같은 모양으로
      // 맞춘다 — 갈라지면 다음에 또 한쪽만 고쳐진다.
      _localReadFailed = true;
      notifyListeners();
    }
  }

  // 로컬 저장분을 못 읽었다 — 위 catch 참고. 화면이 이 사실을 말해야 하고,
  // 그동안 저장이 원본을 덮어쓰면 안 된다.
  bool _localReadFailed = false;

  /// **기기에 저장된 그룹을 열지 못했다.**
  ///
  /// 🚨 참이면 **그룹이 없는 것이 아니라 못 읽은 것**이다. 화면은 둘을
  /// 다르게 말해야 한다.
  ///
  /// 📌 이 상태에서는 [_saveToDisk]가 **아무것도 쓰지 않는다.** 암호문을
  /// 그대로 남겨 둬야 나중에 키가 돌아왔을 때 열 수 있다.
  ///
  /// ⚠️ `ContactsRepository.localReadFailed`·`MyProfileRepository.localReadFailed`
  /// 와 **같은 계약**이다. 하나를 고치면 셋을 함께 본다.
  bool get localReadFailed => _localReadFailed;

  Future<void> _saveToDisk() async {
    // 🚨 **못 읽은 상태에서는 쓰지 않는다** (2026-09-05, [localReadFailed]).
    //
    // 여기서 쓰면 **열지 못한 암호문을 덮어쓴다.** 지금 `_groups` 는 빈
    // 목록이거나 그 뒤에 더한 몇 개뿐이라, 덮는 순간 원래 그룹이 사라진다.
    // 못 읽은 채로 두면 다음에 키가 돌아왔을 때 열린다.
    //
    // ⚠️ **조용히 넘어가지 않는다** — 화면이 [localReadFailed]로 그 사실을
    // 말하고 있어야 한다. 안 그러면 "저장했는데 안 남는" 것으로 보인다.
    if (_localReadFailed) {
      debugPrint('로컬 그룹을 못 읽은 상태라 저장을 건너뛴다 — 덮어쓰기 방지');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _groups.map((g) => g.toJson()).toList();
      final uid = _uid;
      if (uid == null) {
        await prefs.setString(_storageKey, jsonEncode(jsonList));
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encoded = await DataCryptoService.encryptJson({
        'groups': jsonList,
      }, key);
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving groups: $e');
    }
  }

  /// 새 그룹을 만든다. 같은 이름(대소문자·앞뒤공백 무시)이 이미 있으면 새로
  /// 만들지 않고 기존 그룹을 그대로 돌려준다 — 검색창이 "새 그룹 만들기"를
  /// 겸하는 UI에서 같은 이름 그룹이 중복 생성되는 것을 막는다.
  GroupModel createGroup(String name) {
    final trimmed = name.trim();
    final matches = _groups.where(
      (g) => g.name.trim().toLowerCase() == trimmed.toLowerCase(),
    );
    if (matches.isNotEmpty) return matches.first;
    final group = GroupModel(
      id: _generateId(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    _groups = [..._groups, group];
    _generation++;
    notifyListeners();
    _persist();
    return group;
  }

  void renameGroup(String id, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _groups = _groups
        .map((g) => g.id == id ? g.copyWith(name: trimmed) : g)
        .toList();
    _generation++;
    notifyListeners();
    _persist();
  }

  /// 그룹 자체를 지운다. **명함별 참조를 걷어내는 것은 이 저장소의 일이
  /// 아니다** — 여기는 ContactsRepository를 모른다. 참조 정리는
  /// `GroupsViewModel.deleteGroup`이 두 저장소를 함께 보며 처리한다.
  void deleteGroup(String id) {
    _groups = _groups.where((g) => g.id != id).toList();
    _generation++;
    notifyListeners();
    _persist();
  }

  void _persist() {
    unawaited(_saveToDisk());
    final uid = _uid;
    if (uid != null) DataBackupService.backupGroups(uid, _groups);
  }

  int _idSeq = 0;

  /// 그룹 id — UUID 라이브러리 없이도 충돌 없는 고유 값이면 충분하다(법무
  /// 검토가 요구하는 것은 "이름이 아니라 불투명한 id"이지 RFC4122 형식이
  /// 아니다). 같은 밀리초에 여러 그룹이 만들어질 일은 거의 없지만, 시퀀스를
  /// 덧붙여 그 경우도 안전하게 한다.
  String _generateId() =>
      'g_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';
}
