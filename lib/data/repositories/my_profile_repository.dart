import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../models/my_profile_model.dart';
import '../services/data_backup_service.dart';

class MyProfileRepository extends ChangeNotifier {
  static const String _storageKey = 'my_profile_v1';

  MyProfileModel _profile = MyProfileModel.defaultProfile;
  String? _uid;
  bool _hasCustomProfile = false;

  // 내 프로필도 이름/전화/이메일/주소 등 개인정보라 명함과 동일하게
  // AES-256-GCM으로 암호화한다. uid별 키 발급/보관 로직은
  // [EncryptionKeyService] 참고 — uid가 없는(로그인 전) 상태에서는
  // 암호화를 걸 수 없어 평문으로 저장한다.
  final EncryptionKeyService _encryptionKeyService;

  // ContactsRepository와 동일한 지연 로드/마이그레이션 플래그. 자세한 설명은
  // contacts_repository.dart 참고.
  bool _pendingEncryptedLoad = false;
  bool _pendingPlaintextMigration = false;

  MyProfileRepository({EncryptionKeyService? encryptionKeyService})
    : _encryptionKeyService = encryptionKeyService ?? EncryptionKeyService() {
    _loadFromDisk();
  }

  MyProfileModel get profile => _profile;

  /// 로컬에 사용자가 직접 입력한 프로필이 있는지 — 계정 전환 안전장치
  /// (backlog #50)에서 "지울 로컬 데이터가 있는지" 판단할 때 쓴다.
  bool get hasCustomProfile => _hasCustomProfile;

  Future<void> setCurrentUid(String? uid) async {
    _uid = uid;
    if (uid == null) return;
    if (_pendingEncryptedLoad) {
      _pendingEncryptedLoad = false;
      await _loadFromDisk();
    } else if (_pendingPlaintextMigration) {
      _pendingPlaintextMigration = false;
      await _persistToDisk(_profile);
    }
  }

  /// 새 기기(또는 재설치)에서 로그인한 뒤, 로컬 프로필이 아직 사용자가 직접
  /// 입력한 적 없는 기본값 상태일 때만 서버 백업분을 내려받는다.
  Future<void> restoreFromServerIfEmpty(String uid) async {
    if (_hasCustomProfile) return;
    final restored = await DataBackupService.restoreProfile(uid);
    if (restored == null) return;
    _profile = restored;
    _hasCustomProfile = true;
    notifyListeners();
    await _persistToDisk(restored);
  }

  /// 계정 전환 안전장치(backlog #50)에서 사용자가 "현재 계정 데이터로
  /// 교체"를 선택했을 때 쓰는 강제 복원 — [restoreFromServerIfEmpty]와
  /// 달리 로컬 프로필이 이미 커스터마이즈됐어도 무시하고 서버 백업분으로
  /// 덮어쓴다(서버에 백업분이 없으면 기본 프로필로 되돌아간다). 호출 전에
  /// [clearLocal]로 먼저 이전 계정 데이터를 지우는 것을 전제로 한다.
  Future<void> forceRestoreFromServer(String uid) async {
    final restored = await DataBackupService.restoreProfile(uid);
    _profile = restored ?? MyProfileModel.defaultProfile;
    _hasCustomProfile = restored != null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (restored != null) {
        await _persistToDisk(restored);
      } else {
        await prefs.remove(_storageKey);
      }
    } catch (e) {
      debugPrint('강제 복원된 프로필 로컬 저장 실패: $e');
    }
  }

  /// 계정 삭제(backlog #49) 또는 계정 전환 시 로컬 프로필을 기본값으로
  /// 되돌린다. 서버 데이터는 건드리지 않는다 — 호출자가 필요하면 별도로
  /// `DataBackupService`를 통해 서버 쪽도 정리한다.
  Future<void> clearLocal() async {
    _profile = MyProfileModel.defaultProfile;
    _hasCustomProfile = false;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      // 🚨 **여기서 「못 읽었다」를 내린다 — 그리고 「지운 뒤에」여야 한다**
      // (2026-09-05).
      //
      // 이 플래그가 참이면 저장이 아무것도 쓰지 않는다(`localReadFailed`).
      // 열지 못한 암호문을 덮지 않기 위한 장치인데, **지운 뒤에는 덮을
      // 암호문 자체가 없다.** 그런데 플래그가 남아 있으면 그다음 저장이
      // 계속 막혀 **계정 전환의 「현재 계정 데이터로 교체」가 조용히
      // 실패한다** — 서버에서 받아온 것이 로컬에 안 남고, 앱을 껐다 켜면
      // 다시 비어 있다(`auth_gate.dart` 의 clearLocal → forceRestoreFromServer).
      //
      // ⚠️ **`remove` 앞이 아니라 뒤인 것이 요점이다.** 위 `remove` 가
      // 실패하면 암호문이 그대로 남는데, 그때 플래그를 내리면 **저장 차단이
      // 풀려 원본을 덮어쓴다** — 지금 막으려는 바로 그 사고다. 실패하면
      // 예외가 나 이 줄에 오지 않으므로, 플래그는 참으로 남아 계속 막는다.
      if (_localReadFailed) {
        _localReadFailed = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error clearing my profile: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      // 1) 레거시 평문 저장분(암호화 도입 이전에 저장된 프로필) 먼저 시도.
      Map<String, dynamic>? legacyJson;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) legacyJson = decoded;
      } catch (_) {
        legacyJson = null;
      }

      if (legacyJson != null) {
        _profile = MyProfileModel.fromJson(legacyJson);
        _hasCustomProfile = true;
        notifyListeners();
        if (_uid != null) {
          await _persistToDisk(_profile);
        } else {
          _pendingPlaintextMigration = true;
        }
        return;
      }

      // 2) 평문 JSON이 아니면 암호화된 payload로 간주.
      final uid = _uid;
      if (uid == null) {
        _pendingEncryptedLoad = true;
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(raw, key);
      _profile = MyProfileModel.fromJson(decoded);
      _hasCustomProfile = true;
      notifyListeners();
    } catch (e) {
      // 복호화 실패(위변조/키 불일치 등)를 포함해 어떤 이유로든 로드에
      // 실패하면 크래시하지 않고 기본 프로필로 시작한다.
      debugPrint('Error loading my profile: $e');
      // 🚨 **여기서 멈춰 있었다** (2026-09-05에 찾음).
      //
      // `debugPrint` 는 **릴리스에서 아무 데도 안 나온다.** 화면은 기본
      // 프로필을 보여주고 아무 말도 하지 않는다 — 이용자는 *"내 프로필이
      // 초기화됐다"* 고 읽는다.
      //
      // 🚨 **그리고 오해로 끝나지 않는다.** 기본 프로필인 채로 저장이 한 번
      // 돌면 [_persistToDisk]가 **못 읽은 암호문을 덮어쓴다.**
      //
      // ```
      // ① 재설치 등으로 기기의 키가 없다
      // ② 서버에서 키를 못 받는다(네트워크) → 새 키가 발급된다
      // ③ 기존 암호문이 안 열린다 → 기본 프로필
      // ④ 프로필을 한 글자라도 고친다 → 저장이 돌아 새 키로 덮어쓴다
      // ⑤ 🚨 원래 프로필이 진짜로 사라진다
      // ```
      //
      // 📌 **이 파일만의 이야기가 아니다.** `ContactsRepository` 가
      // 2026-09-04에 같은 자리를 먼저 막았는데(`localReadFailed`),
      // **셋 중 하나만 고쳐져 있었다.** 같은 모양으로 맞춘다 — 갈라지면
      // 다음에 또 한쪽만 고쳐진다.
      _localReadFailed = true;
      notifyListeners();
    }
  }

  // 로컬 저장분을 못 읽었다 — 위 catch 참고. 화면이 이 사실을 말해야 하고,
  // 그동안 저장이 원본을 덮어쓰면 안 된다.
  bool _localReadFailed = false;

  /// **기기에 저장된 프로필을 열지 못했다.**
  ///
  /// 🚨 참이면 **프로필이 비어 있는 것이 아니라 못 읽은 것**이다. 화면은
  /// 둘을 다르게 말해야 한다 — 기본 프로필과 같은 모양으로 보여주면 이용자는
  /// *"내 정보가 다 날아갔다"* 고 읽는다.
  ///
  /// 📌 이 상태에서는 [_persistToDisk]가 **아무것도 쓰지 않는다.** 암호문을
  /// 그대로 남겨 둬야 나중에 키가 돌아왔을 때 열 수 있다.
  ///
  /// ⚠️ `ContactsRepository.localReadFailed`·`GroupsRepository.localReadFailed`
  /// 와 **같은 계약**이다. 하나를 고치면 셋을 함께 본다.
  bool get localReadFailed => _localReadFailed;

  /// 프로필을 암호화(로그인 상태) 또는 평문(게스트)으로 저장한다. 저장
  /// 로직을 한 곳에 모아 [updateProfile]/마이그레이션/복원 경로가 모두
  /// 같은 암호화 정책을 따르게 한다.
  Future<void> _persistToDisk(MyProfileModel model) async {
    // 🚨 **못 읽은 상태에서는 쓰지 않는다** (2026-09-05, [localReadFailed]).
    //
    // 여기서 쓰면 **열지 못한 암호문을 덮어쓴다.** 지금 `model` 은 기본
    // 프로필이거나 그 위에 고친 몇 글자뿐이라, 덮는 순간 원래 프로필이
    // 사라진다. 못 읽은 채로 두면 다음에 키가 돌아왔을 때 열린다.
    //
    // ⚠️ **조용히 넘어가지 않는다** — 화면이 [localReadFailed]로 그 사실을
    // 말하고 있어야 한다. 안 그러면 "저장했는데 안 남는" 것으로 보인다.
    if (_localReadFailed) {
      debugPrint('로컬 프로필을 못 읽은 상태라 저장을 건너뛴다 — 덮어쓰기 방지');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _uid;
      if (uid == null) {
        await prefs.setString(_storageKey, jsonEncode(model.toJson()));
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encoded = await DataCryptoService.encryptJson(
        model.toJson(),
        key,
      );
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving my profile: $e');
    }
  }

  Future<void> updateProfile(MyProfileModel updated) async {
    _profile = updated;
    _hasCustomProfile = true;
    notifyListeners();
    await _persistToDisk(updated);
    final uid = _uid;
    if (uid != null) DataBackupService.backupProfile(uid, updated);
  }
}
