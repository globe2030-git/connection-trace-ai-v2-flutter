import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/my_profile_model.dart';
import '../services/data_backup_service.dart';

class MyProfileRepository extends ChangeNotifier {
  static const String _storageKey = 'my_profile_v1';

  MyProfileModel _profile = MyProfileModel.defaultProfile;
  String? _uid;
  bool _hasCustomProfile = false;

  MyProfileRepository() {
    _loadFromDisk();
  }

  MyProfileModel get profile => _profile;

  /// 로컬에 사용자가 직접 입력한 프로필이 있는지 — 계정 전환 안전장치
  /// (backlog #50)에서 "지울 로컬 데이터가 있는지" 판단할 때 쓴다.
  bool get hasCustomProfile => _hasCustomProfile;

  void setCurrentUid(String? uid) {
    _uid = uid;
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(restored.toJson()));
    } catch (e) {
      debugPrint('복원된 프로필 로컬 저장 실패: $e');
    }
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
        await prefs.setString(_storageKey, jsonEncode(restored.toJson()));
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
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _profile = MyProfileModel.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );
        _hasCustomProfile = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading my profile: $e');
    }
  }

  Future<void> updateProfile(MyProfileModel updated) async {
    _profile = updated;
    _hasCustomProfile = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(updated.toJson()));
    } catch (e) {
      debugPrint('Error saving my profile: $e');
    }
    final uid = _uid;
    if (uid != null) DataBackupService.backupProfile(uid, updated);
  }
}
