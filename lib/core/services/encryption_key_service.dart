import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 계정(uid)당 명함/프로필 데이터 암호화에 쓰는 AES-256 대칭키를 발급·보관한다.
///
/// 키 보관 위치는 두 곳이다:
/// 1. 이 기기의 보안 저장소(Keystore/Keychain, `flutter_secure_storage`) —
///    평소에는 여기서만 읽어 빠르고 오프라인에서도 동작한다.
/// 2. Firestore `users/{uid}` 문서의 `encryptionKeyB64` 필드 — 사용자가
///    새 기기에서 로그인했을 때 이 키를 내려받아 기존에 암호화해 둔 명함을
///    복호화할 수 있게 하기 위함. 로컬에만 있으면 기기를 바꾸는 순간 기존
///    암호문을 영영 못 여는 상태가 된다.
///
/// **한계(정직하게 명시)**: 키가 암호문과 같은 Firestore 프로젝트 안에
/// 함께 있으므로 완전한 제로-지식/이중격리 암호화는 아니다 — Firestore
/// 프로젝트 관리자 권한을 가진 사람은 이론적으로 키와 암호문 둘 다에
/// 접근할 수 있다. 이 설계가 실제로 방어하는 시나리오는 "기기 분실/로컬
/// 유출", "백업 파일 유출", "서버 DB(문서)만 일부 유출"이다. 완전한 키
/// 분리(Cloud Functions/KMS에서만 키를 다루고 클라이언트는 절대 키 원문을
/// 못 보는 구조)는 Blaze 요금제 인프라가 갖춰진 뒤 별도 backlog로 강화할
/// 예정.
class EncryptionKeyService {
  EncryptionKeyService({
    FlutterSecureStorage? secureStorage,
    FirebaseFirestore? firestore,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _explicitFirestore = firestore;

  final FlutterSecureStorage _secureStorage;
  // 명시적으로 주입된 경우에만 여기 저장한다. 주입되지 않았으면
  // [_userDoc]에서 그때그때 `FirebaseFirestore.instance`를 시도한다 —
  // 생성자에서 곧바로 접근하면 Firebase가 아직 초기화되지 않은 환경(단위
  // 테스트 등)에서 예외가 나 리포지토리 생성 자체가 실패하기 때문에,
  // 실제로 필요한 시점까지 지연시키고 실패해도 try/catch로 흡수한다.
  final FirebaseFirestore? _explicitFirestore;

  static final AesGcm _algorithm = AesGcm.with256bits();

  // 같은 세션(리포지토리 인스턴스 생존 기간) 안에서 반복 조회 시 Firestore
  // 왕복을 피하기 위한 메모리 캐시.
  final Map<String, SecretKey> _memoryCache = {};

  static String _secureStorageKeyFor(String uid) => 'enc_key_v1_$uid';

  /// 계정 삭제(회원 탈퇴) 시 **이 기기에 남은 키**를 지운다.
  ///
  /// 서버 쪽 키(`users/{uid}`의 `encryptionKeyB64`)는 사용자 문서와 함께
  /// 삭제되지만, 기기 보안 저장소의 사본은 지우는 코드가 없었다(2026-08-10
  /// 점검에서 발견). **iOS Keychain은 앱을 삭제해도 남는다** — 이 프로젝트가
  /// 이미 겪은 문제다(앱 삭제 후 로그인 정보 잔존).
  ///
  /// ⚠️ **반드시 다른 정리가 모두 끝난 뒤 마지막에 부를 것.** 키가 먼저
  /// 사라지면 남은 암호문 파일을 열 수도, 무엇인지 확인할 수도 없게 된다.
  Future<bool> deleteLocalKey(String uid) async {
    _memoryCache.remove(uid);
    try {
      await _secureStorage.delete(key: _secureStorageKeyFor(uid));
      return true;
    } catch (e) {
      debugPrint('암호화 키 삭제 실패: ${e.runtimeType}');
      return false;
    }
  }

  static const String _firestoreFieldName = 'encryptionKeyB64';

  DocumentReference<Map<String, dynamic>>? _userDoc(String uid) {
    var db = _explicitFirestore;
    if (db == null) {
      try {
        db = FirebaseFirestore.instance;
      } catch (e) {
        // Firebase가 초기화되지 않은 환경(단위 테스트 등) — 로컬 보안
        // 저장소만으로 동작한다(이 기기에서는 정상 동작하되, 다른 기기로
        // 계정 복원은 불가능해짐).
        debugPrint('Firestore 사용 불가, 로컬 전용으로 동작($uid): $e');
        return null;
      }
    }
    return db.collection('users').doc(uid);
  }

  // 로컬 키는 있는데 서버 사본이 없는 계정의 재점검을 세션당 한 번으로
  // 제한하는 가드. 점검이 실패하면 다시 지워 다음 조회 때 재시도한다.
  final Set<String> _serverCopyChecked = {};

  /// 로컬 키는 있는데 서버(`users/{uid}.encryptionKeyB64`)에 사본이 없는
  /// 계정을 스스로 복구한다.
  ///
  /// 왜 필요한가(2026-08-20 실물 조회에서 발견): 서버 쪽 사용자 문서가
  /// 초기화된 계정이 기기의 키로 계속 암호화 저장을 하고 있었다 — 이
  /// 상태에서 앱을 지우거나 기기를 바꾸면 서버 암호문을 열 키가 세상에
  /// 없다. 기존 흐름은 로컬에 키가 있으면 서버를 다시 보지 않아, 최초
  /// 업로드 실패·서버 초기화 이후에는 영영 복구되지 않았다.
  ///
  /// 서버에 이미 (다른) 키가 있으면 **덮어쓰지 않는다** — 다른 기기가
  /// 새로 발급한 키로 저장한 암호문이 있을 수 있고, 그걸 덮으면 그쪽
  /// 데이터가 열리지 않게 된다. 실패는 조용히 넘어간다(오프라인 로컬 전용
  /// 동작을 바꾸지 않기 위함이며, 다음 조회에서 다시 시도된다).
  Future<void> _ensureServerCopy(String uid, String keyB64) async {
    if (!_serverCopyChecked.add(uid)) return;
    final userDoc = _userDoc(uid);
    if (userDoc == null) return;
    try {
      final doc = await userDoc.get();
      final remote = doc.data()?[_firestoreFieldName] as String?;
      if (remote != null && remote.isNotEmpty) return;
      await userDoc.set({
        _firestoreFieldName: keyB64,
      }, SetOptions(merge: true));
      debugPrint('암호화 키 서버 사본 복구 완료($uid)');
    } catch (e) {
      _serverCopyChecked.remove(uid);
      debugPrint('암호화 키 서버 사본 점검 실패($uid): ${e.runtimeType}');
    }
  }

  /// [uid] 계정의 암호화 키를 반환한다. 순서: 메모리 캐시 → 로컬 보안
  /// 저장소 → Firestore(있으면 로컬에 캐시 후 반환) → 없으면 새로 생성해
  /// 양쪽(로컬+Firestore)에 저장.
  Future<SecretKey> getOrCreateUserKey(String uid) async {
    final cached = _memoryCache[uid];
    if (cached != null) return cached;

    final storageKey = _secureStorageKeyFor(uid);

    try {
      final localB64 = await _secureStorage.read(key: storageKey);
      if (localB64 != null && localB64.isNotEmpty) {
        final key = SecretKey(base64Decode(localB64));
        _memoryCache[uid] = key;
        // 반환을 막지 않고 뒤에서 서버 사본 유무를 점검한다(아래 설명).
        unawaited(_ensureServerCopy(uid, localB64));
        return key;
      }
    } catch (e) {
      debugPrint('로컬 암호화 키 조회 실패($uid): $e');
    }

    final userDoc = _userDoc(uid);
    if (userDoc != null) {
      try {
        final doc = await userDoc.get();
        final remoteB64 = doc.data()?[_firestoreFieldName] as String?;
        if (remoteB64 != null && remoteB64.isNotEmpty) {
          final key = SecretKey(base64Decode(remoteB64));
          _memoryCache[uid] = key;
          try {
            await _secureStorage.write(key: storageKey, value: remoteB64);
          } catch (e) {
            debugPrint('서버에서 받은 암호화 키 로컬 캐시 실패($uid): $e');
          }
          return key;
        }
      } catch (e) {
        debugPrint('Firestore 암호화 키 조회 실패($uid): $e');
      }
    }

    // 로컬에도 서버에도 없음 — 이 계정의 최초 암호화 키를 새로 발급한다.
    final newSecretKey = await _algorithm.newSecretKey();
    final keyBytes = await newSecretKey.extractBytes();
    final keyB64 = base64Encode(keyBytes);

    try {
      await _secureStorage.write(key: storageKey, value: keyB64);
    } catch (e) {
      debugPrint('신규 암호화 키 로컬 저장 실패($uid): $e');
    }
    if (userDoc != null) {
      try {
        await userDoc.set({
          _firestoreFieldName: keyB64,
        }, SetOptions(merge: true));
      } catch (e) {
        // 서버 저장에 실패해도 로컬에는 이미 저장됐으니 이 기기에서는 계속
        // 정상 동작한다 — 다만 다른 기기에서 복원이 안 될 수 있다. 다음
        // 저장 시점에 다시 시도되지는 않으므로(메모리 캐시로 반환값이
        // 고정됨) 조용히 로그만 남긴다.
        debugPrint('신규 암호화 키 서버 저장 실패($uid): $e');
      }
    }

    _memoryCache[uid] = newSecretKey;
    return newSecretKey;
  }
}
