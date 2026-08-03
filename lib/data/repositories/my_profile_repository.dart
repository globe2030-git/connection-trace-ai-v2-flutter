import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/my_profile_model.dart';

class MyProfileRepository extends ChangeNotifier {
  static const String _storageKey = 'my_profile_v1';

  MyProfileModel _profile = MyProfileModel.defaultProfile;

  MyProfileRepository() {
    _loadFromDisk();
  }

  MyProfileModel get profile => _profile;

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        _profile = MyProfileModel.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading my profile: $e');
    }
  }

  Future<void> updateProfile(MyProfileModel updated) async {
    _profile = updated;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(updated.toJson()));
    } catch (e) {
      debugPrint('Error saving my profile: $e');
    }
  }
}
