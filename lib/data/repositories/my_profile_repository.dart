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
