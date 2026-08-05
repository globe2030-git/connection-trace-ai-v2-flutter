import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../../core/services/geo_backfill_service.dart';
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

  // 좌표는 서버에 백업하지 않는다(backlog 추가 75, C안). 기기를 바꾸거나
  // 계정을 다시 연결해 서버에서 복원하면 좌표가 빈 채로 내려오므로, 주소로
  // 다시 계산해 채워 넣는 역할을 이 서비스가 맡는다.
  final GeoBackfillService _geoBackfillService;

  // 좌표 재계산 진행 상태 — 복원 직후에는 거리 계산이 안 되는 구간이
  // 생기므로 화면에서 "준비 중"을 보여줄 수 있게 노출한다.
  bool _isBackfillingGeo = false;
  int _geoBackfillDone = 0;
  int _geoBackfillTotal = 0;

  // 서버 백업에서 좌표를 걷어내는 1회성 마이그레이션이 진행 중인지.
  bool _strippingGeoBackups = false;

  // 앱 시작 직후(uid를 아직 모를 때) 로드를 시도했는데 저장된 값이
  // 암호화된 형태라 열지 못한 경우 true. 이후 [setCurrentUid]로 실제
  // uid가 들어오면 그 시점에 다시 로드를 시도한다.
  bool _pendingEncryptedLoad = false;

  // 레거시 평문 데이터를 uid 없이(게스트 상태로) 읽어들인 경우 true.
  // 로그인 완료 후 uid가 생기면 그 시점에 즉시 암호화해서 재저장한다.
  bool _pendingPlaintextMigration = false;

  ContactsRepository({
    EncryptionKeyService? encryptionKeyService,
    GeoBackfillService? geoBackfillService,
  }) : _encryptionKeyService = encryptionKeyService ?? EncryptionKeyService(),
       _geoBackfillService = geoBackfillService ?? GeoBackfillService() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  /// 좌표 재계산이 진행 중인지. 복원 직후 주변 인맥 목록이 비어 보이는 구간을
  /// 화면에서 설명하기 위해 쓴다.
  bool get isBackfillingGeo => _isBackfillingGeo;
  int get geoBackfillDone => _geoBackfillDone;
  int get geoBackfillTotal => _geoBackfillTotal;

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
    // 좌표를 서버에서 빼기 전에 올라간 문서에는 암호문 안에 좌표가 남아
    // 있다. 계정당 한 번 전체를 다시 올려 지운다(기다리지 않는다 — 실패해도
    // 다음 로그인에 다시 시도된다).
    unawaited(_stripGeoFromServerBackupsOnce(uid));
    // 복원 때 지오코딩에 실패한 명함이 남아 있을 수 있다(일시적 네트워크
    // 오류, 지오코더 호출 제한 등). 복원 경로에서만 재시도하면 복원이 다시
    // 일어나지 않는 한 영영 재시도되지 않고, 그 명함은 좌표가 없어 주변
    // 인맥 목록에서 조용히 빠진 채로 남는다(실기기에서 확인 — 추가 79).
    // 그래서 로그인할 때마다 미완료분을 이어서 처리한다. 남은 게 없으면
    // 즉시 반환하므로 비용은 거의 없다.
    unawaited(backfillMissingGeo());
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
    // 복원 시점에는 서버 문서에 좌표가 남아 있을 수 있다 — 여기서 한 번 더
    // 정리 기회를 준다(setCurrentUid 시점에는 로컬이 비어 있어 건너뛴다).
    unawaited(_stripGeoFromServerBackupsOnce(uid));
    // 서버에서 내려온 명함에는 좌표가 없다 — 주소로 다시 계산해 채운다.
    // 지오코딩은 건당 최대 10초라 로그인 흐름을 막지 않도록 기다리지 않는다.
    unawaited(backfillMissingGeo());
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
    unawaited(_stripGeoFromServerBackupsOnce(uid));
    unawaited(backfillMissingGeo());
  }

  /// 주소는 있는데 좌표가 없는 명함들의 좌표를 주소로부터 다시 계산해 채운다.
  ///
  /// 좌표를 서버에 백업하지 않기로 했기 때문에(backlog 추가 75, C안) 기기를
  /// 바꾸거나 계정을 다시 연결해 복원하면 좌표가 빈 상태로 내려온다. 이
  /// 메서드가 그 빈자리를 메운다. 채운 결과는 **기기에만 저장**한다 — 좌표는
  /// 애초에 서버로 보내지 않으므로 재백업할 이유가 없다.
  ///
  /// 실패한 건은 다음 호출에서 다시 시도되며, 반복 실패하면
  /// [GeoBackfillService]가 알아서 포기한다. 호출자는 결과를 기다릴 필요가
  /// 없다(진행 상황은 [isBackfillingGeo]로 관찰).
  Future<void> backfillMissingGeo() async {
    if (_isBackfillingGeo) return;

    final pending = await _geoBackfillService.pendingContacts(_contacts);
    if (pending.isEmpty) return;

    _isBackfillingGeo = true;
    _geoBackfillDone = 0;
    _geoBackfillTotal = pending.length;
    notifyListeners();

    try {
      final resolved = await _geoBackfillService.backfill(
        pending,
        onProgress: (done, total) {
          _geoBackfillDone = done;
          _geoBackfillTotal = total;
          notifyListeners();
        },
      );
      if (resolved.isNotEmpty) {
        _contacts = _contacts
            .map(
              (c) => resolved.containsKey(c.id)
                  ? c.copyWith(geo: resolved[c.id])
                  : c,
            )
            .toList();
        await _saveToDisk();
      }
    } catch (e) {
      debugPrint('좌표 재계산 중 오류: $e');
    } finally {
      _isBackfillingGeo = false;
      _geoBackfillDone = 0;
      _geoBackfillTotal = 0;
      notifyListeners();
    }
  }

  /// 좌표를 서버에서 빼기로 하기 전에 올라간 백업 문서에는 암호문 안에
  /// 좌표가 들어 있다. 암호문이라 서버 쪽에서 필드만 지울 수 없으므로,
  /// 좌표가 빠진 페이로드로 전체를 한 번 덮어쓴다. 계정당 1회.
  Future<void> _stripGeoFromServerBackupsOnce(String uid) async {
    // setCurrentUid와 복원 양쪽에서 호출되므로 동시에 두 번 돌 수 있다.
    // 같은 내용을 두 번 올리는 게 위험하진 않지만(set은 멱등) 굳이 쓰기를
    // 두 배로 낼 이유가 없다.
    if (_strippingGeoBackups) return;
    _strippingGeoBackups = true;
    try {
      final flagKey = 'geo_stripped_from_backup_v1_$uid';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flagKey) ?? false) return;
      if (_contacts.isEmpty) {
        // 아직 로컬에 명함이 없으면(복원 전) 지울 대상도 판단할 수 없다.
        // 플래그를 세우지 않고 다음 로그인에 다시 시도한다.
        return;
      }
      final ok = await DataBackupService.rebackupAllContacts(uid, _contacts);
      if (ok) await prefs.setBool(flagKey, true);
    } catch (e) {
      debugPrint('서버 백업 좌표 제거 실패: $e');
    } finally {
      _strippingGeoBackups = false;
    }
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
