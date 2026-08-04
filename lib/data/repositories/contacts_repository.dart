import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact_model.dart';
import '../services/data_backup_service.dart';

class ContactsRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_contacts_v2';

  // 예전엔 여기에 가짜 인맥 3명(김민준/한소율/오현우)을 하드코딩해서 앱을
  // 처음 켜면 마치 실제 등록된 인맥인 것처럼 보여줬다 — 사용자가 "가짜
  // 데이터를 보여주지 말고 실제 연동되는 자료 기반으로 진행해"라고 요청해
  // 제거. 이제 실제로 명함을 스캔하거나 QR로 교환하기 전까지는 빈
  // 목록으로 시작한다.
  List<ContactModel> _contacts = [];

  // 로그인된 사용자의 Firebase uid — 서버 백업 대상 식별용. AuthGate가
  // 로그인/로그아웃 시점에 설정한다. null이면 서버 백업을 시도하지 않는다
  // (게스트 QA 로그인, 또는 Firebase Auth 연동이 실패한 경우).
  String? _uid;

  ContactsRepository() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  void setCurrentUid(String? uid) {
    _uid = uid;
  }

  /// 새 기기(또는 재설치)에서 로그인한 뒤 로컬 명함 목록이 비어있을 때만
  /// 서버 백업분을 통째로 내려받는다 — 이미 로컬에 데이터가 있으면 덮어쓰지
  /// 않는다(사용자가 계속 쓰던 기기에서 실수로 서버 데이터로 갈아치우는
  /// 사고 방지).
  Future<void> restoreFromServerIfEmpty(String uid) async {
    if (_contacts.isNotEmpty) return;
    final restored = await DataBackupService.restoreContacts(uid);
    if (restored.isEmpty) return;
    _contacts = restored;
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _contacts = jsonList
            .map((j) => ContactModel.fromJson(j as Map<String, dynamic>))
            .toList();
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
    _backup(newContact);
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
    _backup(updatedContact);
  }

  void deleteContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
    _saveToDisk();
    final uid = _uid;
    if (uid != null) DataBackupService.deleteContactBackup(uid, id);
  }

  void _backup(ContactModel contact) {
    final uid = _uid;
    if (uid != null) DataBackupService.backupContact(uid, contact);
  }
}
