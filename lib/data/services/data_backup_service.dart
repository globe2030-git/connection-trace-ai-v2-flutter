import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../models/card_source_model.dart';
import '../models/contact_model.dart';
import '../models/group_model.dart';
import '../models/my_profile_model.dart';
import '../../core/utils/account_paths.dart';

/// 명함/프로필 데이터를 Cloud Firestore에 백업·복원한다.
///
/// 2026-08-04 결정(backlog 추가 66): 실시간 동기화가 아니라 **백업/복원**
/// 방식 — 로컬(`shared_preferences`)이 계속 소스 오브 트루스이고, 저장 시점에
/// 서버로도 같은 내용을 올려두었다가, 새 기기에서 로그인했는데 로컬이
/// 비어있으면 서버에서 통째로 내려받는다. 명함 원본 사진은 이번 범위에
/// 포함하지 않는다(Firebase Storage가 유료 요금제 전환 없이는 활성화되지
/// 않아 사용자가 사진은 나중으로 미루기로 결정 — backlog 추가 66 후속).
///
/// 2026-08-04 추가(backlog 추가 72): 서버에 저장되는 명함/프로필 필드도
/// AES-256-GCM으로 암호화한다. 이미 암호화된 내용이라 구조화된 필드로
/// 나눠 저장할 이유가 없으므로, 문서 형태를 `{'encrypted': '<암호문>',
/// 'schemaVersion': 2}` 하나로 단순화한다. 암호화 키 자체도 이 계정의
/// Firestore 문서(`users/{uid}.encryptionKeyB64`)에 함께 저장되므로(새
/// 기기 복원을 위해 필요), 이 설계는 완전한 제로-지식 암호화는 아니다 —
/// 자세한 내용/한계는 [EncryptionKeyService] 문서 주석 참고.
class DataBackupService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // 백업 전용 static 헬퍼 클래스라 인스턴스를 만들 수 없다 — 이 서비스가
  // 쓰는 EncryptionKeyService도 static으로 하나만 두고 재사용한다(uid별
  // 메모리 캐시를 가지고 있어 반복 호출 시 Firestore/보안 저장소 왕복을
  // 줄여준다).
  static final EncryptionKeyService _encryptionKeyService =
      EncryptionKeyService();

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      AccountPaths.account(_db, uid);

  static CollectionReference<Map<String, dynamic>> _contactsCollection(
    String uid,
  ) => AccountPaths.contacts(_db, uid);

  /// 명함 1건을 암호화해서 서버에 백업한다. 실패해도 로컬 저장은 이미 끝난
  /// 뒤라 사용자 작업을 막지 않는다 — 조용히 실패하고 다음 저장 때 다시
  /// 시도된다.
  ///
  /// 페이로드는 [ContactModel.toBackupJson]으로 만든다 — **좌표(lat/lng)를
  /// 제외한 형태**다(backlog 추가 75, C안). `toJson()`으로 바꾸면 좌표가
  /// 다시 서버에 올라가므로 주의.
  static Future<void> backupContact(String uid, ContactModel contact) async {
    try {
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptJson(
        contact.toBackupJson(),
        key,
      );
      await _contactsCollection(uid).doc(contact.id).set({
        'encrypted': encrypted,
        'schemaVersion': 2,
      });
    } catch (e) {
      debugPrint('명함 서버 백업 실패(${contact.id}): $e');
    }
  }

  static CollectionReference<Map<String, dynamic>> _cardSourcesCollection(
    String uid,
  ) => AccountPaths.cardSources(_db, uid);

  /// **파싱 원본**을 암호화해 남긴다 (2026-09-05, globe2030님 지적).
  ///
  /// 파서를 고쳐도 이미 등록된 명함은 그대로였다 — 원본이 안 남았기 때문이다.
  /// 이걸 남기면 **사진 없이 파싱만 다시 돌릴 수 있다**(설계 §2-3-3).
  ///
  /// 🚨 **미루면 되살릴 수 없는 데이터가 쌓인다.** 원본은 저장하는 순간에만
  /// 남길 수 있다 — 그래서 「사람」 레이어(people)로 옮기기 전에 먼저 넣는다.
  /// ⚠️ 지금은 `users/{uid}` 아래에 둔다. **명함 본문과 같은 곳이므로 나중에
  /// 함께 옮겨 간다** — 따로 챙길 것이 늘지 않는다.
  ///
  /// 📌 **본문과 다른 문서에 둔다.** 같은 문서에 넣으면 평소 명함첩을 열
  /// 때마다 안 쓰는 원본이 딸려온다.
  ///
  /// 실패해도 조용히 넘어간다 — [backupContact]와 같은 판단이고, 여기서는
  /// 더 그렇다. **원본이 없다고 명함 등록이 막히면 안 된다.**
  static Future<void> backupCardSource(
    String uid,
    CardSourceModel source,
  ) async {
    try {
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptJson(
        source.toJson(),
        key,
      );
      await _cardSourcesCollection(uid).doc(source.cardId).set({
        'encrypted': encrypted,
        'schemaVersion': 1,
      });
    } catch (e) {
      // 🚨 rawText 는 제3자 개인정보다. 내용은 절대 안 찍는다.
      debugPrint('파싱 원본 백업 실패(${source.cardId}): ${e.runtimeType}');
    }
  }

  /// 명함을 지울 때 그 원본도 함께 지운다.
  ///
  /// 🚨 **이걸 빠뜨리면 지운 명함의 개인정보 원문이 서버에 남는다.** 이용자는
  /// 지웠다고 알고 있는데 이름·전화·주소가 그대로 있는 상태가 된다.
  static Future<void> deleteCardSource(String uid, String cardId) async {
    try {
      await _cardSourcesCollection(uid).doc(cardId).delete();
    } catch (e) {
      debugPrint('파싱 원본 삭제 실패($cardId): ${e.runtimeType}');
    }
  }

  /// 명함 전체를 현재 백업 포맷으로 다시 올린다.
  ///
  /// 좌표를 서버에서 빼기로 한 뒤(backlog 추가 75, C안) **이미 서버에 올라가
  /// 있는 문서에는 좌표가 암호문 안에 들어 있다.** 암호문이라 서버 쪽에서
  /// 필드만 골라 지울 수 없으므로, 좌표가 빠진 페이로드로 문서를 통째로
  /// 덮어써야 한다(`set()`은 전체 교체라 이전 암호문이 남지 않는다).
  ///
  /// 계정당 한 번만 돌면 되는 작업이라 호출자가 완료 플래그를 관리한다.
  /// 한 건이라도 실패하면 `false`를 반환해 다음 기회에 다시 시도하게 한다.
  static Future<bool> rebackupAllContacts(
    String uid,
    List<ContactModel> contacts,
  ) async {
    if (contacts.isEmpty) return true;
    try {
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final collection = _contactsCollection(uid);
      const chunkSize = 450; // Firestore batch 상한(500)보다 여유 있게.
      for (var i = 0; i < contacts.length; i += chunkSize) {
        final batch = _db.batch();
        for (final contact in contacts.skip(i).take(chunkSize)) {
          final encrypted = await DataCryptoService.encryptJson(
            contact.toBackupJson(),
            key,
          );
          batch.set(collection.doc(contact.id), {
            'encrypted': encrypted,
            'schemaVersion': 2,
          });
        }
        await batch.commit();
      }
      return true;
    } catch (e) {
      debugPrint('명함 전체 재백업 실패: $e');
      return false;
    }
  }

  static Future<void> deleteContactBackup(String uid, String contactId) async {
    try {
      await _contactsCollection(uid).doc(contactId).delete();
    } catch (e) {
      debugPrint('명함 서버 백업 삭제 실패($contactId): $e');
    }
  }

  /// 삭제 기록(tombstone). 다기기 동기화(P1-39 A안)에서 "다른 기기에서 지운
  /// 명함"을 이 기기에도 반영하기 위한 것 — 삭제는 "없음"이라 그냥 두면 병합이
  /// 다시 살려낸다. 그래서 삭제 시각을 남긴다. 개인정보는 없고 id·시각만 남긴다.
  /// 시각은 클라이언트 시계(ISO)로 남겨 명함의 updatedAt(같은 클라이언트 시계)과
  /// 같은 기준으로 비교한다.
  static Future<void> writeTombstone(String uid, String contactId) async {
    try {
      await AccountPaths.deletedContacts(_db, uid).doc(contactId).set({
        'deletedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('삭제 기록(tombstone) 저장 실패($contactId): $e');
    }
  }

  /// 서버의 삭제 기록 전체를 `{contactId: deletedAt}`로 내려받는다.
  static Future<Map<String, DateTime>> fetchTombstones(String uid) async {
    try {
      final snap = await AccountPaths.deletedContacts(_db, uid).get();
      final result = <String, DateTime>{};
      for (final doc in snap.docs) {
        final raw = doc.data()['deletedAt'];
        final dt = raw is String ? DateTime.tryParse(raw) : null;
        if (dt != null) result[doc.id] = dt;
      }
      return result;
    } catch (e) {
      debugPrint('삭제 기록(tombstone) 조회 실패: $e');
      return {};
    }
  }

  static Future<void> backupProfile(String uid, MyProfileModel profile) async {
    try {
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptJson(
        profile.toJson(),
        key,
      );
      await _userDoc(uid).set({
        'profile': {'encrypted': encrypted, 'schemaVersion': 2},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('프로필 서버 백업 실패: $e');
    }
  }

  /// 그룹 목록(id·이름·생성일)을 암호화해서 `users/{uid}` 문서의 `groups`
  /// 필드에 저장한다(추가 427).
  ///
  /// ⚠️ **하위 컬렉션이 아니라 문서 필드**로 두는 것이 법무 검토의 핵심
  /// 결론이다(`docs/planning/group-feature-legal-note-2026-08-23.md` 질문 3).
  /// `deleteAllUserData`가 `users/{uid}` 문서를 통째로 지우므로, 여기 두면
  /// 탈퇴 파기 경로에 **별도 코드 없이 자연히 포함**된다 — 하위 컬렉션으로
  /// 두면 `deletedContacts`가 이미 겪은 함정(문서를 지워도 하위 컬렉션은
  /// 남는다)이 그대로 재발한다.
  ///
  /// 그룹명이 제3자를 특정할 수 있는 자유 입력값이라 프로필과 동일하게
  /// `{'encrypted': ..., 'schemaVersion': 1}` 형태로 암호화해 넣는다(평문
  /// Map으로 넣지 않는다).
  static Future<void> backupGroups(String uid, List<GroupModel> groups) async {
    try {
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptJson({
        'groups': groups.map((g) => g.toJson()).toList(),
      }, key);
      await _userDoc(uid).set({
        'groups': {'encrypted': encrypted, 'schemaVersion': 1},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('그룹 서버 백업 실패: $e');
    }
  }

  /// 그룹 목록을 서버에서 내려받는다. 필드가 없거나(신규 계정) 복호화에
  /// 실패하면 `null`을 돌려준다 — 호출자가 "받은 게 없다"와 "빈 목록"을
  /// 구분해 로컬을 함부로 덮어쓰지 않게 하기 위함([restoreProfile]과 동일한
  /// 계약).
  static Future<List<GroupModel>?> restoreGroups(String uid) async {
    try {
      final doc = await _userDoc(uid).get();
      final field = doc.data()?['groups'];
      if (field is! Map<String, dynamic>) return null;
      final encrypted = field['encrypted'] as String?;
      // 그룹 기능은 암호화 도입 이후에 생겼으므로 레거시 평문 문서가 있을
      // 수 없다 — 없으면 그냥 복원할 것이 없는 것으로 본다.
      if (encrypted == null) return null;
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(encrypted, key);
      final list = decoded['groups'] as List<dynamic>? ?? const [];
      return list
          .map((j) => GroupModel.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('그룹 서버 복원 실패: $e');
      return null;
    }
  }

  /// 계정 전환 때 이용자가 **무엇을 골랐는지**를 남긴다.
  ///
  /// ## 왜 남기나
  ///
  /// 계정 전환 "유지"는 이 기기의 명함이 **지금 로그인한 계정의 데이터가
  /// 되는** 동작이다. 나중에 *"이 명함들이 왜 이 계정에 있느냐"* 는 물음이
  /// 생기면, **두 계정이 같은 사람이었다는 것을 회사가 보여야 한다**
  /// (개인정보 보호법 §16① — 최소수집의 입증책임이 처리자에게 있다).
  /// 지금 설계는 그 증거를 하나도 남기지 않는다.
  ///
  /// ## ⚠️ 무엇을 남기고 무엇을 안 남기나
  ///
  /// ```
  /// 남긴다     시각 · 이전 계정 식별자 · 무엇을 골랐는지
  /// 안 남긴다  ⚠️ 명함 내용 · 이름 · 전화번호 — 어떤 개인정보도 넣지 않는다
  /// ```
  ///
  /// ## ⚠️ 기기 원장(deviceLedger)과 혼동하지 말 것
  ///
  /// 법무 회신(질문 5·6)은 *"uid 목록을 탈퇴 후에도 남기지 말라"* 고 했는데
  /// **그것과 충돌하지 않는다.** 그쪽은 **탈퇴 후에도 무기한 남는** 기기
  /// 원장이었고, 이것은 **계정이 살아 있는 동안의 처리 이력**이다.
  ///
  /// 📌 `users/{uid}` **문서 안의 필드**로 둔 것이 그 때문이다. 탈퇴하면
  /// `deleteAllUserData`가 그 문서를 지우므로 **함께 사라진다** — 하위
  /// 컬렉션으로 두면 문서를 지워도 남아서 따로 지우는 코드가 필요하다
  /// (이 저장소에서 실제로 겪은 함정이다 — deletedContacts).
  ///
  /// 최근 [_switchLogCap]건만 남긴다. 계정 전환은 드문 일이라 이 정도면
  /// 충분하고, 무한히 쌓아 둘 이유가 없다(§21① 최소보유).
  /// 이 계정으로 갈아타면서 **「유지」를 고른 가장 최근 시각**. 없으면 null.
  ///
  /// 🚨 **이미 기기에 있던 명함이 「넘어온 것」인지 가리는 데 쓴다**(추가 556).
  /// 표시는 전환하는 순간에 붙이는데, **그 코드가 생기기 전에 전환한 기기에는
  /// 표시가 없다.** 그 기기들이 바로 이번에 샌 기기들이라, 소급해서 가릴
  /// 기준이 필요하다.
  ///
  /// 📌 기준을 **시각**으로 잡는 이유: 전환보다 오래된 명함은 앞 계정에서
  /// 넘어온 것이고, 전환 뒤에 손댄 명함은 **이 계정에서 만든 것**이다.
  /// "전부 넘어온 것으로 친다"로 하면 **자기 명함까지 백업이 조용히 멈춘다.**
  static Future<DateTime?> lastKeepSwitchAt(String uid) async {
    try {
      final snap = await _userDoc(uid).get();
      final raw = (snap.data()?['accountSwitches'] as List<dynamic>?) ?? const [];
      DateTime? latest;
      for (final e in raw.whereType<Map<String, dynamic>>()) {
        if (e['choice'] != 'keep') continue;
        final at = DateTime.tryParse(e['at'] as String? ?? '');
        if (at == null) continue;
        if (latest == null || at.isAfter(latest)) latest = at;
      }
      return latest;
    } catch (e) {
      // 못 읽으면 소급 표시를 하지 않는다 — 잘못 표시하면 자기 명함의
      // 백업이 멈추는 쪽으로 틀린다.
      debugPrint('계정 전환 기록 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  static Future<void> recordAccountSwitch(
    String uid, {
    required String previousUid,
    required bool replaced,
  }) async {
    try {
      final doc = _userDoc(uid);
      final snap = await doc.get();
      final raw = (snap.data()?['accountSwitches'] as List<dynamic>?) ?? const [];
      final entries = raw.whereType<Map<String, dynamic>>().toList();
      entries.add({
        // ⚠️ serverTimestamp()는 배열 안에서 못 쓴다 — 기기 시각을 쓴다.
        'at': DateTime.now().toUtc().toIso8601String(),
        'previousUid': previousUid,
        'choice': replaced ? 'replace' : 'keep',
      });
      final trimmed = entries.length > _switchLogCap
          ? entries.sublist(entries.length - _switchLogCap)
          : entries;
      await doc.set({'accountSwitches': trimmed}, SetOptions(merge: true));
    } catch (e) {
      // 실패해도 전환 자체는 막지 않는다 — 기록은 곁다리다.
      debugPrint('계정 전환 기록 실패: $e');
    }
  }

  static const int _switchLogCap = 20;

  /// 이 계정으로 서버에 백업된 명함 전체를 내려받는다. 새 기기에서 로그인
  /// 직후, 로컬 명함 목록이 비어있을 때만 호출된다(기존 데이터를 덮어쓰지
  /// 않기 위함).
  ///
  /// 문서에 `encrypted` 필드가 있으면 복호화하고, 없으면(암호화 도입 전에
  /// 저장된 레거시 평문 문서) 그대로 구조화된 필드로 파싱한다 — 기존 서버
  /// 데이터(예: 이미 등록된 "문정순" 명함)가 깨지거나 사라지지 않게 하기
  /// 위함. 레거시 문서는 다음에 그 명함이 로컬에서 저장될 때
  /// [backupContact]를 통해 자동으로 암호화된 형태로 재백업된다.
  static Future<List<ContactModel>> restoreContacts(String uid) async {
    try {
      final snapshot = await _contactsCollection(uid).get();
      if (snapshot.docs.isEmpty) return [];

      // 문서마다 매번 키를 새로 조회하지 않도록 첫 암호화 문서를 만났을
      // 때 한 번만 가져와 재사용한다(EncryptionKeyService 자체도 내부
      // 메모리 캐시가 있어 중복 호출이 비싸진 않지만, 굳이 반복할 이유가
      // 없다).
      SecretKey? key;
      final contacts = <ContactModel>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final encrypted = data['encrypted'] as String?;
        if (encrypted == null) {
          // 레거시 평문 문서.
          try {
            contacts.add(ContactModel.fromJson(data));
          } catch (e) {
            debugPrint('레거시 명함 파싱 실패(${doc.id}): $e');
          }
          continue;
        }
        try {
          key ??= await _encryptionKeyService.getOrCreateUserKey(uid);
          final decoded = await DataCryptoService.decryptJson(
            encrypted,
            key,
          );
          contacts.add(ContactModel.fromJson(decoded));
        } catch (e) {
          // 위변조/키 불일치 등으로 이 한 건만 복호화에 실패해도 나머지
          // 명함 복원은 계속 진행한다 — 한 건 때문에 전체 복원이 막히면
          // 안 되기 때문.
          debugPrint('명함 복호화 실패(${doc.id}): $e');
        }
      }
      return contacts;
    } catch (e) {
      debugPrint('명함 서버 복원 실패: $e');
      return [];
    }
  }

  static Future<MyProfileModel?> restoreProfile(String uid) async {
    try {
      final doc = await _userDoc(uid).get();
      final profileField = doc.data()?['profile'];
      if (profileField is! Map<String, dynamic>) return null;

      final encrypted = profileField['encrypted'] as String?;
      if (encrypted == null) {
        // 레거시 평문 프로필 — 암호화 도입 전에 저장된 구조화된 필드 그대로.
        return MyProfileModel.fromJson(profileField);
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(encrypted, key);
      return MyProfileModel.fromJson(decoded);
    } catch (e) {
      debugPrint('프로필 서버 복원 실패: $e');
      return null;
    }
  }

  /// 계정 삭제(backlog #49)용: 이 uid로 서버에 백업된 데이터를 전부 지운다
  /// — `users/{uid}/contacts` 하위 문서 전체와 `users/{uid}` 문서 자체.
  /// `users/{uid}` 문서를 통째로 지우므로 그 안의 `encryptionKeyB64`
  /// 필드(backlog 추가 72)도 함께 삭제된다 — 별도 처리 불필요.
  ///
  /// 다른 백업 메서드들과 달리 실패를 조용히 삼키지 않고 그대로 던진다.
  /// 계정 삭제는 "사용자가 삭제됐다고 믿는데 실제로는 서버에 데이터가
  /// 남아있는" 상황이 절대 있어서는 안 되는 액션이라, 호출자(설정 화면)가
  /// 반드시 실패를 알아채고 사용자에게 알려야 한다.
  ///
  /// Firestore SDK에는 컬렉션을 통째로 지우는 API가 없어 문서를 모두 읽어와
  /// batch로 지운다. batch는 500건 제한이 있어 청크로 나눠 처리한다.
  static Future<void> deleteAllUserData(String uid) async {
    final contactsCollection = _contactsCollection(uid);
    final snapshot = await contactsCollection.get();
    const chunkSize = 450;
    for (var i = 0; i < snapshot.docs.length; i += chunkSize) {
      final chunk = snapshot.docs.skip(i).take(chunkSize);
      final batch = _db.batch();
      for (final doc in chunk) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _userDoc(uid).delete();
  }
}
