import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
class DataBackupService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> _contactsCollection(
    String uid,
  ) => _userDoc(uid).collection('contacts');

  /// 명함 1건을 서버에 백업한다. 실패해도 로컬 저장은 이미 끝난 뒤라
  /// 사용자 작업을 막지 않는다 — 조용히 실패하고 다음 저장 때 다시 시도된다.
  static Future<void> backupContact(String uid, ContactModel contact) async {
    try {
      await _contactsCollection(uid).doc(contact.id).set(contact.toJson());
    } catch (e) {
      debugPrint('명함 서버 백업 실패(${contact.id}): $e');
    }
  }

  static Future<void> deleteContactBackup(String uid, String contactId) async {
    try {
      await _contactsCollection(uid).doc(contactId).delete();
    } catch (e) {
      debugPrint('명함 서버 백업 삭제 실패($contactId): $e');
    }
  }

  static Future<void> backupProfile(String uid, MyProfileModel profile) async {
    try {
      await _userDoc(uid).set({
        'profile': profile.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('프로필 서버 백업 실패: $e');
    }
  }

  /// 이 계정으로 서버에 백업된 명함 전체를 내려받는다. 새 기기에서 로그인
  /// 직후, 로컬 명함 목록이 비어있을 때만 호출된다(기존 데이터를 덮어쓰지
  /// 않기 위함).
  static Future<List<ContactModel>> restoreContacts(String uid) async {
    try {
      final snapshot = await _contactsCollection(uid).get();
      return snapshot.docs
          .map((doc) => ContactModel.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('명함 서버 복원 실패: $e');
      return [];
    }
  }

  static Future<MyProfileModel?> restoreProfile(String uid) async {
    try {
      final doc = await _userDoc(uid).get();
      final data = doc.data();
      final profileJson = data?['profile'] as Map<String, dynamic>?;
      if (profileJson == null) return null;
      return MyProfileModel.fromJson(profileJson);
    } catch (e) {
      debugPrint('프로필 서버 복원 실패: $e');
      return null;
    }
  }

  /// 계정 삭제(backlog #49)용: 이 uid로 서버에 백업된 데이터를 전부 지운다
  /// — `users/{uid}/contacts` 하위 문서 전체와 `users/{uid}` 문서 자체.
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
