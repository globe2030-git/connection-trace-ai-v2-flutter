import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../models/contact_model.dart';
import '../models/my_profile_model.dart';

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
      _db.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> _contactsCollection(
    String uid,
  ) => _userDoc(uid).collection('contacts');

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
      await _userDoc(uid).collection('deletedContacts').doc(contactId).set({
        'deletedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('삭제 기록(tombstone) 저장 실패($contactId): $e');
    }
  }

  /// 서버의 삭제 기록 전체를 `{contactId: deletedAt}`로 내려받는다.
  static Future<Map<String, DateTime>> fetchTombstones(String uid) async {
    try {
      final snap = await _userDoc(uid).collection('deletedContacts').get();
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
