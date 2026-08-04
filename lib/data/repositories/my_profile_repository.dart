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
      debugPrint('Error loading my profile: $e');
    }
  }

  /// 프로필을 암호화(로그인 상태) 또는 평문(게스트)으로 저장한다. 저장
  /// 로직을 한 곳에 모아 [updateProfile]/마이그레이션/복원 경로가 모두
  /// 같은 암호화 정책을 따르게 한다.
  Future<void> _persistToDisk(MyProfileModel model) async {
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
