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
  static const String _fileNamePrefix = 'contact_card_';
  static const String _fileNameSuffix = '.enc';

  /// 서버 복원이 로컬 명함을 덮어쓰면 `cardImagePath`가 유실된다 — 백업
  /// JSON에는 경로를 넣지 않는데(다른 기기에선 무의미한 로컬 경로라서),
  /// 정작 이 기기에 저장해 둔 암호문 파일은 그대로 남아 있다. 파일명이
  /// contactId로 결정되므로, 경로가 끊긴 명함이 자기 파일을 되찾을 수
  /// 있게 한다. 파일이 없으면(정말 이미지가 없는 명함) null.
  ///
  /// 단건용 — 명함 수정 화면 진입 시 한 건만 확인할 때 쓴다. 목록 전체를
  /// 재연결할 때는 [findAllExistingCardImagePaths]를 대신 쓸 것(명함마다
  /// 개별 IO를 내지 않기 위함).
  Future<String?> findExistingCardImagePath(String contactId) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final path = '${docsDir.path}/${_fileName(contactId)}';
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// [findExistingCardImagePath]의 일괄판 — 명함이 수백 장이어도 문서
  /// 디렉터리를 **한 번만** 조회해 `contactId → 암호문 파일 경로` 맵을
  /// 만든다(개별 존재 확인 대신 파일명 규칙으로 매칭). 서버 복원/다기기
  /// 병합 직후 로컬 명함 목록에서 경로가 빠진 항목을 일괄 재연결하는 데
  /// 쓴다(추가 - 명함 이미지 경로 일괄 재연결).
  Future<Map<String, String>> findAllExistingCardImagePaths() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docsDir.path);
      if (!dir.existsSync()) return {};
      final result = <String, String>{};
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;
        if (!name.startsWith(_fileNamePrefix) || !name.endsWith(_fileNameSuffix)) {
          continue;
        }
        final id = name.substring(
          _fileNamePrefix.length,
          name.length - _fileNameSuffix.length,
        );
        if (id.isEmpty) continue;
        result[id] = entity.path;
      }
      return result;
    } catch (e) {
      debugPrint('명함 이미지 파일 목록 조회 실패: ${e.runtimeType}');
      return {};
    }
  }

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

  /// 계정 삭제(회원 탈퇴) 시 이 기기에 남은 **모든** 명함 이미지 파일을 지운다.
  ///
  /// `clearLocal()`은 SharedPreferences만 비우므로 이미지 파일은 그대로 남았다.
  /// 게다가 명함 목록이 먼저 비워지면 경로를 잃어 **나중에 지울 수도 없는 고아
  /// 파일**이 된다(2026-08-10 점검에서 발견). 방침은 "영구 삭제"라고 적고
  /// 있는데 제3자(명함 주인)의 개인정보가 담긴 파일이 남는 셈이라 반드시
  /// 정리해야 한다.
  ///
  /// 파일명 규칙(`contact_card_*.enc`)으로 **쓸어내는** 방식이라, 이전에
  /// 중단된 삭제가 남긴 고아 파일까지 함께 정리된다.
  ///
  /// ⚠️ **이 방식은 "이 기기 로컬에 계정이 하나뿐"이라는 전제 위에서만
  /// 안전하다.** 로컬 저장소를 계정별로 분리하는 작업(HANDOFF P1-10)이
  /// 반영되면 **uid 범위로 좁혀야** 다른 계정의 이미지를 지우지 않는다.
  ///
  /// 실패한 파일 수를 반환한다 — 호출부가 사용자에게 알릴 수 있도록.
  /// 하나가 실패해도 나머지는 계속 지운다(멈추면 더 많이 남는다).
  Future<int> deleteAllCardImages() async {
    var failed = 0;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final entries = docsDir.listSync();
      for (final entry in entries) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!name.startsWith('contact_card_') || !name.endsWith('.enc')) {
          continue;
        }
        try {
          _decryptedCache.remove(entry.path);
          await entry.delete();
        } catch (e) {
          failed++;
          debugPrint('명함 이미지 삭제 실패: ${e.runtimeType}');
        }
      }
    } catch (e) {
      failed++;
      debugPrint('명함 이미지 목록 조회 실패: ${e.runtimeType}');
    }
    _decryptedCache.clear();
    return failed;
  }
}
