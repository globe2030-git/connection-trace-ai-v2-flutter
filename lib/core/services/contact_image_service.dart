import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/card_photo_downscale.dart';
import '../utils/scan_temp_cleanup.dart';
import 'card_photo_backup_service.dart';
import 'card_photo_backup_state.dart';
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
/// `nonce+ciphertext+mac` 바이트를 쓴다.
///
/// **서버 저장(2026-08-15, backlog 추가 218)**: 같은 암호문 파일을
/// [CardPhotoBackupService]가 Cloud Storage에도 올린다 — 기기를 바꾸면
/// 명함 텍스트는 복원되는데 사진만 사라지던 문제를 없애기 위함이다. 여기서
/// 복호화하지 않고 **암호문 그대로** 올리므로 서버는 사진을 열어볼 수 없다.
/// ⚠️ 개인정보처리방침 v2.2 게시 전까지
/// [CardPhotoBackupService.kCardPhotoBackupEnabled]가 `false`라 업로드는
/// 실제로 일어나지 않는다.
class ContactImageService {
  ContactImageService({
    EncryptionKeyService? keyService,
    CardPhotoBackupService? photoBackup,
    CardPhotoBackupStateService? backupState,
  }) : _keyService = keyService ?? EncryptionKeyService(),
       _photoBackup = photoBackup ?? CardPhotoBackupService(),
       _backupState = backupState ?? CardPhotoBackupStateService();

  final EncryptionKeyService _keyService;
  final CardPhotoBackupService _photoBackup;
  final CardPhotoBackupStateService _backupState;

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
      final original = await src.readAsBytes();

      // 보관본은 줄여서 넣는다(2026-08-16). 서버 저장 비용이 누적되는데
      // 충전형은 AI를 쓸 때만 받으므로 회수 경로가 없다 — 근거와 계산은
      // docs/planning/card-photo-storage-cost-spec-2026-08-16.md.
      //
      // ⚠️ **자리가 여기여야 한다.** 촬영 → 크롭 → 회전 → OCR → (화면 닫힘)
      // → 저장 순서라, 크롭 단계에서 줄이면 그 결과물이 곧 OCR 입력이 되어
      // 인식률이 떨어진다. 인식은 이 지점보다 한참 앞에서 이미 끝나 있다.
      //
      // 로컬 파일도 함께 줄어든다. 서버용만 줄이려면 재암호화가 필요해
      // **평문 구간이 한 번 더 생기는데**, 암호문을 그대로 올리는 구조를
      // 고른 이유 자체가 그 구간을 없애는 것이었다. 게다가 기기를 바꾸면
      // 서버 사본을 내려받아 로컬이 되므로 "로컬만 고화질"은 오래 못 간다.
      final bytes = downscaleForArchive(original);

      final key = await _keyService.getOrCreateUserKey(uid);
      final encrypted = await DataCryptoService.encryptBytes(bytes, key);

      final docsDir = await getApplicationDocumentsDirectory();
      final outPath = '${docsDir.path}/${_fileName(contactId)}';
      await File(outPath).writeAsBytes(encrypted, flush: true);
      // ⚠️ 캐시에도 **축소본**을 넣는다. 원본(original)을 넣으면 파일과
      // 화면이 그 실행 동안 어긋난다 — 다음에 앱을 켜면 파일에서 읽어
      // 축소본이 뜨므로, 같은 사진이 세션마다 달라 보인다.
      _decryptedCache[outPath] = Uint8List.fromList(bytes);

      // 서버 업로드는 **기다리지 않는다**(fire-and-forget). 로컬 저장이 이미
      // 끝났고, 업로드는 기기 변경 대비용이라 명함 저장 화면을 네트워크
      // 왕복만큼 붙잡아 둘 이유가 없다.
      //
      // ⚠️ 다만 **결과는 기록한다**(2026-08-16). 예전에는 실패해도 아무
      // 일도 일어나지 않아, **네트워크가 끊긴 채 저장하면 백업이 안 됐는데
      // 아무도 몰랐다.** 그러면 기기를 바꾼 뒤에야 사진이 없다는 것을 알게
      // 되는데, 이 기능을 만든 이유가 정확히 그 상황을 없애는 것이었다.
      // 기록해 두어야 지갑에 "백업 안 됨"을 표시하고 나중에 다시 시도할 수
      // 있다.
      unawaited(
        _photoBackup
            .upload(
              uid: uid,
              contactId: contactId,
              encryptedFilePath: outPath,
            )
            .then(
              (ok) => _backupState.record(
                contactId,
                ok ? CardPhotoBackupState.synced : CardPhotoBackupState.failed,
              ),
            )
            // 상태 기록이 실패해도 저장 자체는 이미 끝났다. 조용히 넘긴다.
            .catchError((_) {}),
      );
      // 원본(촬영 임시 파일)은 여기까지 오면 쓰임이 끝났다. **평문이므로
      // 지운다**(2026-08-16). 저장이 이 파일을 읽는 마지막 지점이라, 더 앞에서
      // 지우면 저장이 빈 파일을 읽는다.
      //
      // ⚠️ 갤러리에서 고른 사진도 image_picker가 임시 폴더에 복사한 사본이라
      // 지워도 원본 사진첩은 그대로다.
      unawaited(deleteQuietly(sourcePath));

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

  /// 로컬에 암호문 파일이 없는 명함들을 서버에서 내려받는다.
  ///
  /// 기기를 바꾸거나 앱을 다시 깔면 로컬 `.enc` 파일이 **하나도 없다.** 명함
  /// 텍스트는 Firestore에서 복원되는데 사진만 비는 상태가 이때 생긴다.
  ///
  /// 새로 받아온 것만 `contactId → 로컬 경로`로 돌려준다(서버에도 없는 명함,
  /// 즉 사진 없이 등록한 명함은 결과에 들어가지 않는다 — 오류가 아니다).
  ///
  /// 순차로 받는다. 명함 수백 장을 동시에 받으면 회선을 다 쓰고 앱이 다른
  /// 복원 작업까지 굶긴다 — `GeoBackfillService`가 지오코더를 순차 호출하는
  /// 것과 같은 판단이다(backlog 추가 76).
  Future<Map<String, String>> downloadMissingCardImages({
    required String uid,
    required Iterable<String> contactIds,
  }) async {
    if (!CardPhotoBackupService.kCardPhotoBackupEnabled) return {};
    final ids = contactIds.toList();
    if (ids.isEmpty) return {};
    final restored = <String, String>{};
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      for (final id in ids) {
        final destination = '${docsDir.path}/${_fileName(id)}';
        if (File(destination).existsSync()) {
          restored[id] = destination;
          continue;
        }
        final ok = await _photoBackup.download(
          uid: uid,
          contactId: id,
          destinationPath: destination,
        );
        if (ok) restored[id] = destination;
      }
    } catch (e) {
      debugPrint('명함 이미지 서버 복원 실패: ${e.runtimeType}');
    }
    return restored;
  }

  /// 명함 삭제 시 암호문 파일도 지운다.
  ///
  /// [uid]와 [contactId]를 함께 주면 **서버 사본까지** 지운다. 주지 않으면
  /// 기기 파일만 지운다 — 로그인 전(게스트)처럼 서버에 사본이 있을 수 없는
  /// 경우가 있어 선택 인자로 뒀다.
  ///
  /// ⚠️ 둘을 빠뜨리면 사용자가 지운 명함의 사진이 서버에 남는다. 방침은
  /// "이용자가 해당 명함을 삭제한 때 즉시 파기"라고 적고 있으므로, 로그인
  /// 상태의 삭제 경로에서는 반드시 함께 넘길 것.
  ///
  /// [path]가 비어 있으면 기기 파일 정리를 건너뛴다 — 서버 복원 직후처럼
  /// **경로가 끊긴 명함**도 서버에는 사본이 있을 수 있어, 그 경우 [uid]·
  /// [contactId]만으로 서버 쪽을 지우기 위함이다.
  Future<void> deleteCardImage(
    String path, {
    String? uid,
    String? contactId,
  }) async {
    if (path.isNotEmpty) {
      try {
        _decryptedCache.remove(path);
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (e) {
        debugPrint('명함 이미지 삭제 실패: ${e.runtimeType}');
      }
    }
    if (uid != null && contactId != null) {
      await _photoBackup.delete(uid: uid, contactId: contactId);
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
  /// [uid]를 주면 **서버에 있는 사본까지** 전부 지운다. 계정 삭제에서는 반드시
  /// 넘길 것 — 기기 파일만 지우면 방침이 약속한 "회원 탈퇴 시 전부 파기"가
  /// 서버 쪽에서 지켜지지 않는다.
  ///
  /// 실패한 파일 수를 반환한다 — 호출부가 사용자에게 알릴 수 있도록.
  /// 하나가 실패해도 나머지는 계속 지운다(멈추면 더 많이 남는다).
  Future<int> deleteAllCardImages({String? uid}) async {
    var failed = 0;
    if (uid != null) {
      failed += await _photoBackup.deleteAllForUser(uid);
    }
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
