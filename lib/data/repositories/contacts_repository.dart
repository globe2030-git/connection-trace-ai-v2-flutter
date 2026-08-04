import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
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

  // 명함 데이터(제3자 개인정보)는 로컬 저장 시와 서버 백업 시 모두
  // AES-256-GCM으로 암호화한다(사용자 요청 — adb로 shared_preferences를
  // 직접 열어보면 평문이 그대로 읽히는 문제가 확인됨). 암호화 키는 uid별로
  // 발급되므로 로그인 전(uid == null)에는 암호화를 걸 수 없다 — 이 경우
  // 게스트 상태로 간주해 평문으로 저장한다(로그인 전에는 서버 백업도 되지
  // 않는 상태라 상대적으로 노출 범위가 좁고, 로그인하는 즉시 아래
  // 마이그레이션 로직으로 자동 암호화된다).
  final EncryptionKeyService _encryptionKeyService;

  // 앱 시작 직후(uid를 아직 모를 때) 로드를 시도했는데 저장된 값이
  // 암호화된 형태라 열지 못한 경우 true. 이후 [setCurrentUid]로 실제
  // uid가 들어오면 그 시점에 다시 로드를 시도한다.
  bool _pendingEncryptedLoad = false;

  // 레거시 평문 데이터를 uid 없이(게스트 상태로) 읽어들인 경우 true.
  // 로그인 완료 후 uid가 생기면 그 시점에 즉시 암호화해서 재저장한다.
  bool _pendingPlaintextMigration = false;

  ContactsRepository({EncryptionKeyService? encryptionKeyService})
    : _encryptionKeyService = encryptionKeyService ?? EncryptionKeyService() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

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

  /// 계정 전환 안전장치(backlog #50)에서 사용자가 "현재 계정 데이터로
  /// 교체"를 선택했을 때 쓰는 강제 복원 — [restoreFromServerIfEmpty]와
  /// 달리 로컬에 데이터가 있어도 무시하고 서버 백업분으로 덮어쓴다(서버에
  /// 백업분이 없으면 빈 목록이 된다). 호출 전에 [clearLocal]로 먼저 이전
  /// 계정 데이터를 지우는 것을 전제로 한다.
  Future<void> forceRestoreFromServer(String uid) async {
    final restored = await DataBackupService.restoreContacts(uid);
    _contacts = restored;
    notifyListeners();
    await _saveToDisk();
  }

  /// 계정 삭제(backlog #49) 또는 계정 전환 시 로컬 명함 데이터를 전부
  /// 지운다. 서버 데이터는 건드리지 않는다 — 호출자가 필요하면 별도로
  /// `DataBackupService`를 통해 서버 쪽도 정리한다.
  Future<void> clearLocal() async {
    _contacts = [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing saved contacts: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      // 1) 레거시 평문 저장분인지 먼저 시도한다 — 암호화를 도입하기 전에
      // 저장된 데이터(예: 기존 "문정순" 명함)는 순수 JSON 배열 문자열이라
      // 여기서 바로 파싱에 성공한다.
      List<dynamic>? legacyList;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) legacyList = decoded;
      } catch (_) {
        legacyList = null;
      }

      if (legacyList != null) {
        _contacts = legacyList
            .map((j) => ContactModel.fromJson(j as Map<String, dynamic>))
            .toList();
        notifyListeners();
        // 로그인된 상태라면 즉시 암호화해서 재저장(1회성 투명 마이그레이션).
        // 아직 로그인 전이면 로그인 시점([setCurrentUid])에 마이그레이션한다.
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
        // 로그인 전이라 키를 만들 수 없다 — setCurrentUid()가 로그인 완료
        // 후 다시 이 메서드를 호출해 복호화를 재시도한다.
        _pendingEncryptedLoad = true;
        return;
      }

      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(raw, key);
      final jsonList = decoded['contacts'] as List<dynamic>? ?? const [];
      _contacts = jsonList
          .map((j) => ContactModel.fromJson(j as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      // 복호화 실패(위변조/키 불일치 등)를 포함해 어떤 이유로든 로드에
      // 실패하면 크래시하지 않고 빈 목록으로 시작한다.
      debugPrint('Error loading saved contacts: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _contacts.map((c) => c.toJson()).toList();
      final uid = _uid;
      if (uid == null) {
        // 로그인 전(게스트) — 암호화 키를 만들 수 없으므로 평문으로 저장.
        await prefs.setString(_storageKey, jsonEncode(jsonList));
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encoded = await DataCryptoService.encryptJson({
        'contacts': jsonList,
      }, key);
      await prefs.setString(_storageKey, encoded);
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
