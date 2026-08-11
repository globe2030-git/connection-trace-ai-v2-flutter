import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'data_crypto_service.dart';
import 'encryption_key_service.dart';

/// 스캔한 명함 이미지를 **로컬에 암호화해서** 보관하고 복호화해 읽는다(P1-9).
///
/// 왜 암호화하나: 명함 이미지엔 이름·전화·이메일이 인쇄돼 있어 개인정보다.
/// 명함/프로필 텍스트는 이미 AES-256-GCM으로 암호화(추가 72)하는데 이미지만
/// 평문이면 같은 정보가 그대로 새어 나간다(추가 133). 계정(uid)당 키
/// ([EncryptionKeyService])를 그대로 재사용한다.
///
/// 저장 형식: 앱 문서 디렉터리에 `contact_card_<contactId>.enc` 파일로
/// `nonce+ciphertext+mac` 바이트를 쓴다. 서버 백업 대상이 아니다(Firebase
/// Storage 미활성 — 이미지는 로컬 전용, 기기 변경 시 사라짐).
class ContactImageService {
  ContactImageService({EncryptionKeyService? keyService})
    : _keyService = keyService ?? EncryptionKeyService();

  final EncryptionKeyService _keyService;

  // 복호화 결과를 경로별로 캐시한다 — 목록 아바타가 스크롤될 때마다 파일을
  // 다시 읽고 복호화하지 않도록. 값은 실패 시 null이 아니라 캐시하지 않는다.
  static final Map<String, Uint8List> _decryptedCache = {};

  static String _fileName(String contactId) => 'contact_card_$contactId.enc';

  /// 서버 복원이 로컬 명함을 덮어쓰면 `cardImagePath`가 유실된다 — 백업
  /// JSON에는 경로를 넣지 않는데(다른 기기에선 무의미한 로컬 경로라서),
  /// 정작 이 기기에 저장해 둔 암호문 파일은 그대로 남아 있다. 파일명이
  /// contactId로 결정되므로, 경로가 끊긴 명함이 자기 파일을 되찾을 수
  /// 있게 한다. 파일이 없으면(정말 이미지가 없는 명함) null.
  Future<String?> findExistingCardImagePath(String contactId) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final path = '${docsDir.path}/${_fileName(contactId)}';
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// [sourcePath]의 이미지를 읽어 암호화해 저장하고, 저장된 암호문 파일 경로를
  /// 반환한다. 실패하면 null(이미지는 부가 기능이라 저장 실패가 명함 저장을
  /// 막지 않는다).
  Future<String?> saveEncryptedCardImage({
    required String uid,
    required String contactId,
    required String sourcePath,
  }) async {
    try {
      final src = File(sourcePath);
      if (!src.existsSync()) return null;
      final bytes = await src.readAsBytes();
      final key = await _keyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptBytes(bytes, key);

      final docsDir = await getApplicationDocumentsDirectory();
      final outPath = '${docsDir.path}/${_fileName(contactId)}';
      await File(outPath).writeAsBytes(encrypted, flush: true);
      _decryptedCache[outPath] = Uint8List.fromList(bytes);
      return outPath;
    } catch (e) {
      // 개인정보가 로그에 남지 않도록 타입만 남긴다.
      debugPrint('명함 이미지 암호화 저장 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 암호화된 명함 이미지를 복호화해 바이트로 돌려준다. 파일이 없거나(다른
  /// 기기에서 복원된 경우 등) 복호화 실패면 null.
  Future<Uint8List?> loadDecryptedCardImage({
    required String uid,
    required String path,
  }) async {
    final cached = _decryptedCache[path];
    if (cached != null) return cached;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final encrypted = await file.readAsBytes();
      final key = await _keyService.getOrCreateUserKey(uid);
      final plain = await DataCryptoService.decryptBytes(encrypted, key);
      _decryptedCache[path] = plain;
      return plain;
    } catch (e) {
      debugPrint('명함 이미지 복호화 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 명함 삭제 시 암호문 파일도 지운다.
  Future<void> deleteCardImage(String path) async {
    try {
      _decryptedCache.remove(path);
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('명함 이미지 삭제 실패: ${e.runtimeType}');
    }
  }
}
