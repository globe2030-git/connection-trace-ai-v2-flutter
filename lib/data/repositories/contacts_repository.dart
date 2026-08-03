import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact_model.dart';

class ContactsRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_contacts_v2';

  // 예전엔 여기에 가짜 인맥 3명(김민준/한소율/오현우)을 하드코딩해서 앱을
  // 처음 켜면 마치 실제 등록된 인맥인 것처럼 보여줬다 — 사용자가 "가짜
  // 데이터를 보여주지 말고 실제 연동되는 자료 기반으로 진행해"라고 요청해
  // 제거. 이제 실제로 명함을 스캔하거나 QR로 교환하기 전까지는 빈
  // 목록으로 시작한다.
  List<ContactModel> _contacts = [];

  ContactsRepository() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _contacts = jsonList.map((j) => ContactModel.fromJson(j as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading saved contacts: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _contacts.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('Error saving contacts to disk: $e');
    }
  }

  void addContact(ContactModel newContact) {
    _contacts = [newContact, ..._contacts];
    notifyListeners();
    _saveToDisk();
  }

  void updateContact(ContactModel updatedContact) {
    _contacts = _contacts.map((c) {
      if (c.id == updatedContact.id) {
        return updatedContact;
      }
      return c;
    }).toList();
    notifyListeners();
    _saveToDisk();
  }

  void deleteContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
    _saveToDisk();
  }
}
