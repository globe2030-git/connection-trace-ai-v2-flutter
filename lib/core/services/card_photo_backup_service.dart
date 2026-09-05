import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// 명함 원본 사진을 **암호문 그대로** 서버(Cloud Storage)에 올리고 내려받는다.
///
/// ## 왜 필요한가
///
/// 지금까지 명함 사진은 기기에만 있었다([ContactImageService] 주석: "서버 백업
/// 대상이 아니다 — 이미지는 로컬 전용, 기기 변경 시 사라짐"). 그래서 폰을
/// 바꾸면 **명함 텍스트는 복원되는데 사진만 통째로 없어졌다.** 사용자에게는
/// "복원이 반쯤 됐다"로 보이는 상태다.
///
/// ## 무엇을 올리는가 — 원본이 아니라 암호문이다
///
/// [ContactImageService]가 이미 로컬에 `nonce+ciphertext+mac` 형태로 암호화해
/// 저장해 둔 `.enc` 파일을 **그대로** 올린다. 여기서 복호화하지 않는다.
/// 그래서:
/// - 서버(회사 포함)는 사진을 열어볼 수 없다. 키는 계정별로 따로 있다
///   (`EncryptionKeyService`).
/// - 업로드·다운로드 경로에 평문 이미지가 존재하는 순간이 없다.
/// - 재암호화 비용이 없다.
///
/// 저장 위치는 `users/{uid}/cards/{contactId}.enc`. `storage.rules`가
/// 본인 uid 폴더만 읽고 쓸 수 있게 막는다.
///
/// ## ✅ 켜져 있다 (2026-08-26부터)
///
/// [kCardPhotoBackupEnabled]가 `true`다 — **왜 켰는지는 그 필드에** 적혀 있다.
///
/// ⚠️ **예전에는 꺼져 있었고, 끄는 데에는 이유가 있었다.** 개인정보처리방침
/// v2.2(명함 사진의 서버 저장을 고지하는 개정)가 게시되기 전에 켜면 **고지
/// 없는 수집**이 된다 — 이 저장소에서 BYOK 서술 불일치로 이미 한 번 겪은
/// 종류의 사고다(방침 v2.0 전부개정 사유).
///
/// 📌 **켜졌다고 그 순서를 지우지 않는다.** 다시 꺼야 할 일이 생기면
/// `docs/planning/cs-retention-spec-2026-08-15.md` 5절이 그 순서다:
/// 법무 검토 → 방침 게시 → 고지 기간 경과 → 이 플래그 `true` → 배포.
///
/// 🚨 **이 문단이 열흘 동안 「기본은 꺼져 있다」라고 말하고 있었다** — 바로
/// 아래 [kCardPhotoBackupEnabled] 가 `true` 이고 *"✅ 2026-08-26부터 켠다"*
/// 라고 적혀 있는데도. **한 파일이 자기 자신과 모순돼 있었다**(추가 687).
/// 📌 낡은 기록은 멀리 있을 때보다 **같은 파일 안에 있을 때 더 잘 속인다** —
/// 위를 읽고 아래를 안 읽는다.
class CardPhotoBackupService {
  /// ✅ **2026-08-26부터 켠다**(사용자 결정 — 내 명함·등록 명함 모두 서버로).
  ///
  /// ## 왜 켜도 되나
  ///
  /// 🚨 **게시된 방침 본문이 이미 서버 저장을 고지하고 있다**(2-1 표·4번
  /// 보유기간·6번 위탁·"국내 저장" 절). 이용자가 지금 그 페이지를 열면
  /// *"서버에 암호화 저장된다"*고 읽는다. 켜지 않는 쪽이 오히려 문서와
  /// 실물이 어긋난 상태였다.
  ///
  /// **켜기 전 관문 셋이 다 닫혔다**(2026-08-26 확인):
  /// - 계정 전환에서 **선택이 끝나기 전에는 서버로 아무것도 쓰지 않는다**
  ///   (`auth_gate.dart` — *"여기서 처음으로 서버 쓰기가 허용된다"*)
  /// - 전환 다이얼로그가 **"유지"가 무슨 일인지** 말한다(같은 파일)
  /// - **이중 사본** — Firestore 실측에서 3중 상태가 아니었다(계정 15개 중
  ///   명함이 있는 곳 7개, 건수가 제각각이라 같은 묶음의 복제가 아니다)
  ///
  /// ## 시행일이 아니라 **일반 사용자 배포**가 기준이다
  ///
  /// 방침 시행일을 게이트로 쓰면, 이용자가 없는 테스트 기간에 개발만 막힌다
  /// — 실제로 그렇게 막혔다(2026-08-26 사용자 지적). 시행일은 일반 배포
  /// 시점에 맞춰 잡고, 테스트 기간에는 기능을 열어 둔다.
  static const bool kCardPhotoBackupEnabled = true;

  // 초기화 형식 인자(this._storage)로 바꾸면 인자명이 `_storage`가 되어 내부
  // 필드명이 생성자 밖으로 드러난다. 이 필드는 아래 _bucket 게터가 감싸는
  // 구현 세부라 그대로 둔다.
  // ignore: prefer_initializing_formals
  CardPhotoBackupService({FirebaseStorage? storage}) : _storage = storage;

  // 지연 생성 — 테스트에서 Firebase 초기화 없이 이 클래스를 만들 수 있어야
  // 한다. 플래그가 꺼져 있으면 아래 메서드들이 Storage에 손을 대지 않으므로
  // 인스턴스도 만들어지지 않는다.
  final FirebaseStorage? _storage;
  FirebaseStorage get _bucket => _storage ?? FirebaseStorage.instance;

  static const String _extension = '.enc';

  /// 암호문 파일이라 이미지 MIME이 아니다. `storage.rules`도 이 타입을
  /// 전제로 검사한다 — 둘 중 하나만 바꾸면 업로드가 조용히 거부된다.
  static const String _contentType = 'application/octet-stream';

  Reference _ref(String uid, String contactId) =>
      _bucket.ref('users/$uid/cards/$contactId$_extension');

  /// 로컬 암호문 파일을 서버에 올린다.
  ///
  /// 실패해도 예외를 던지지 않는다 — 사진 백업은 부가 기능이라, 실패가 명함
  /// 저장을 되돌리거나 사용자 흐름을 막아서는 안 된다. 다음 저장 때 다시
  /// 시도된다.
  ///
  /// 성공하면 `true`. 플래그가 꺼져 있으면 아무 일도 하지 않고 `false`.
  Future<bool> upload({
    required String uid,
    required String contactId,
    required String encryptedFilePath,
  }) async {
    if (!kCardPhotoBackupEnabled) return false;
    try {
      final file = File(encryptedFilePath);
      if (!file.existsSync()) return false;
      await _ref(uid, contactId).putFile(
        file,
        SettableMetadata(contentType: _contentType),
      );
      return true;
    } catch (e) {
      // 개인정보가 로그에 남지 않도록 예외 타입만 남긴다(CLAUDE.md 4절).
      debugPrint('명함 사진 서버 업로드 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// 서버의 암호문을 [destinationPath]에 내려받는다.
  ///
  /// 복호화는 하지 않는다 — 내려받은 파일은 [ContactImageService]가 로컬에
  /// 저장해 두는 것과 **완전히 같은 형식**이라, 그 서비스의 읽기 경로가
  /// 그대로 동작한다.
  ///
  /// 서버에 파일이 없으면(사진 없는 명함, 플래그를 켜기 전에 등록한 명함)
  /// `false`. 이건 오류가 아니라 정상적인 경우다.
  Future<bool> download({
    required String uid,
    required String contactId,
    required String destinationPath,
  }) async {
    if (!kCardPhotoBackupEnabled) return false;
    try {
      final bytes = await _ref(uid, contactId).getData(_maxDownloadBytes);
      if (bytes == null || bytes.isEmpty) return false;
      await File(destinationPath).writeAsBytes(bytes, flush: true);
      return true;
    } on FirebaseException catch (e) {
      // object-not-found는 "사진이 없는 명함"이라 흔한 정상 경로다. 로그로
      // 남기면 복원 때마다 수십 줄이 찍혀 진짜 오류를 덮는다.
      if (e.code != 'object-not-found') {
        debugPrint('명함 사진 서버 다운로드 실패: ${e.code}');
      }
      return false;
    } catch (e) {
      debugPrint('명함 사진 서버 다운로드 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// `storage.rules`가 업로드를 5MB로 제한하므로 같은 값을 쓴다. 이보다 크게
  /// 잡으면 규칙이 막을 파일을 메모리로 읽으려다 OOM이 날 수 있다.
  static const int _maxDownloadBytes = 5 * 1024 * 1024;

  /// 서버에 **실제로** 올라가 있는 명함 사진의 contactId 집합(2026-08-16,
  /// 추가 256).
  ///
  /// 재설치 뒤 한도 카운터를 되살리는 데 쓴다 — 카운터가 기기에만 있어서
  /// 앱을 다시 깔면 0으로 돌아가는데, 서버에는 사진이 그대로 있다.
  ///
  /// ## ⚠️ 실패와 "없음"을 구분한다 — 이게 이 함수의 요점이다
  ///
  /// 목록을 **못 읽으면 `null`**, 읽었는데 비었으면 **빈 집합**이다. 둘을
  /// 섞으면 회선이 나쁠 때 카운터가 **0으로 떨어져 한도가 느슨해지는
  /// 방향**으로 틀린다. 부르는 쪽은 `null`이면 **아무것도 하지 않아야 한다.**
  ///
  /// [download]가 `bool`이라 이 구분을 못 하는 것과 대비된다 — 그래서 개수를
  /// 셀 때는 다운로드 성공 수가 아니라 이 목록을 쓴다.
  ///
  /// ⚠️ **이 경로는 아직 실물에서 통과한 적이 없다.** `storage.rules`의
  /// `users/{uid}/{allPaths=**}`에 `allow read`가 있어 규칙상 열려 있어야
  /// 하지만(Storage에서 read는 get과 list를 함께 덮는다), 플래그가 꺼져 있어
  /// 한 번도 돌지 않았다. 실패해도 호출부가 조용히 넘어가도록 짜 둔 이유다.
  Future<Set<String>?> listSyncedContactIds(String uid) async {
    if (!kCardPhotoBackupEnabled) return null;
    try {
      final listing = await _bucket.ref('users/$uid/cards').listAll();
      return listing.items
          .map((item) => item.name)
          .where((name) => name.endsWith(_extension))
          .map((name) => name.substring(0, name.length - _extension.length))
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      // ⚠️ 빈 집합이 아니라 null이다. 위 문단 참고.
      debugPrint('명함 사진 서버 목록 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 명함 1건의 서버 사진을 지운다. 사용자가 그 명함을 삭제했을 때 부른다.
  ///
  /// 이미 없으면 성공으로 친다 — 삭제는 멱등이어야 한다. 여기서 실패를
  /// 시끄럽게 만들면, 로컬에서는 지워졌는데 서버에만 남은 상태를 사용자가
  /// 알 방법이 없다.
  Future<void> delete({required String uid, required String contactId}) async {
    if (!kCardPhotoBackupEnabled) return;
    try {
      await _ref(uid, contactId).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        debugPrint('명함 사진 서버 삭제 실패: ${e.code}');
      }
    } catch (e) {
      debugPrint('명함 사진 서버 삭제 실패: ${e.runtimeType}');
    }
  }

  /// 회원 탈퇴 시 그 계정의 사진을 **전부** 지운다.
  ///
  /// ⚠️ 클라이언트가 지우는 구조라 **탈퇴 도중 앱이 죽으면 사진이 서버에
  /// 남는다.** 명함 텍스트(Firestore)는 서버 트리거 `onUserDeletedCleanup`이
  /// 뒷정리를 하지만 Storage는 그 트리거 범위 밖이다. 방침이 "탈퇴 시 파기"를
  /// 약속하므로 **서버 트리거에 Storage 정리를 추가하는 것이 후속 과제**다
  /// (cs-retention-spec 3절과 같은 성격 — 지금은 `functions` 영역을 다른
  /// 세션이 배포 중이라 손대지 않았다).
  ///
  /// 지우지 못한 개수를 반환한다. 하나가 실패해도 나머지는 계속 지운다 —
  /// 멈추면 더 많이 남는다([ContactImageService.deleteAllCardImages]와 같은 판단).
  Future<int> deleteAllForUser(String uid) async {
    if (!kCardPhotoBackupEnabled) return 0;
    var failed = 0;
    try {
      final listing = await _bucket.ref('users/$uid/cards').listAll();
      for (final item in listing.items) {
        try {
          await item.delete();
        } catch (e) {
          failed++;
          debugPrint('명함 사진 서버 삭제 실패: ${e.runtimeType}');
        }
      }
    } catch (e) {
      failed++;
      debugPrint('명함 사진 서버 목록 조회 실패: ${e.runtimeType}');
    }
    return failed;
  }
}
