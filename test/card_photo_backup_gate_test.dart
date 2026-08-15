import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 명함 사진 서버 저장의 **게이트**를 고정하는 테스트.
///
/// 이 기능은 개인정보처리방침 v2.2(사진의 서버 저장을 고지하는 개정)가
/// 게시되고 고지 기간이 지난 뒤에야 켤 수 있다. 방침보다 코드가 먼저 나가면
/// **고지 없는 수집**이 된다 — 이 저장소가 BYOK 서술 불일치로 이미 한 번
/// 겪은 종류의 사고다(방침 v2.0 전부개정 사유).
///
/// 그래서 "플래그가 꺼져 있다"와 "꺼져 있으면 네트워크에 손대지 않는다"를
/// 테스트로 박아 둔다. 켤 때는 이 테스트가 실패하므로, **방침 게시를 확인한
/// 사람이 의식적으로** 아래 기대값을 바꾸게 된다. 실수로 켜지는 것을 막는
/// 장치이지, 켜지 못하게 하는 장치가 아니다.
void main() {
  group('명함 사진 서버 저장 게이트', () {
    test('⭐ 방침 게시 전에는 꺼져 있다', () {
      expect(
        CardPhotoBackupService.kCardPhotoBackupEnabled,
        isFalse,
        reason:
            '개인정보처리방침 v2.2 게시 + 고지 기간 경과 전에는 켜면 안 된다. '
            '켜는 절차는 docs/planning/cs-retention-spec-2026-08-15.md 5절 참고. '
            '켰다면 이 테스트의 기대값을 함께 바꾸고, 방침이 실제로 게시됐는지 '
            '확인한 근거를 커밋 메시지에 남길 것.',
      );
    });

    // Firebase를 초기화하지 않은 상태에서 도는 테스트다. 플래그가 꺼져 있으면
    // 각 메서드가 Storage 인스턴스에 손도 대지 않아야 하므로, 예외 없이
    // 돌아오는 것 자체가 "네트워크 경로로 들어가지 않았다"는 증거가 된다.
    // (들어갔다면 Firebase 미초기화로 예외가 난다.)
    final service = CardPhotoBackupService();

    test('꺼져 있으면 업로드는 아무 일도 하지 않는다', () async {
      final result = await service.upload(
        uid: 'u1',
        contactId: 'c1',
        encryptedFilePath: '/tmp/없는파일.enc',
      );
      expect(result, isFalse);
    });

    test('꺼져 있으면 다운로드는 아무 일도 하지 않는다', () async {
      final destination = '${Directory.systemTemp.path}/gate_test_download.enc';
      final result = await service.download(
        uid: 'u1',
        contactId: 'c1',
        destinationPath: destination,
      );
      expect(result, isFalse);
      expect(
        File(destination).existsSync(),
        isFalse,
        reason: '꺼진 상태에서 파일을 만들면 안 된다',
      );
    });

    test('꺼져 있으면 삭제도 조용히 통과한다', () async {
      // 삭제는 반환값이 없다 — 예외가 나지 않는 것이 확인 대상이다.
      await service.delete(uid: 'u1', contactId: 'c1');
    });

    test('꺼져 있으면 전체 삭제는 실패 0건으로 돌아온다', () async {
      final failed = await service.deleteAllForUser('u1');
      expect(
        failed,
        0,
        reason: '꺼진 상태에서 "지우지 못했다"고 보고하면 호출부가 사용자에게 '
            '거짓 경고를 띄운다',
      );
    });
  });
}
