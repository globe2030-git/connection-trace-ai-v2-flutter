import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 명함 사진 서버 저장의 **게이트**를 고정하는 테스트.
///
/// ## ✅ 2026-08-26에 켰다 — 이 테스트가 제 일을 했다
///
/// 이 파일은 *"켤 때는 이 테스트가 실패하므로, 방침 게시를 확인한 사람이
/// **의식적으로** 기대값을 바꾸게 된다"*는 장치였다. 실제로 플래그를 켜자
/// 여기서 걸렸고, 아래 근거를 확인한 뒤 기대값을 바꿨다.
///
/// **근거 셋(전부 실측):**
/// 1. 🚨 **게시된 방침 본문이 이미 서버 저장을 고지하고 있다** — 2-1 수집
///    항목표, 4번 보유기간표의 *"서버 — 해당 명함을 삭제한 때 즉시 파기"*,
///    6번 위탁 현황의 *"명함 원본 사진의 서버 저장 및 복원(Cloud Storage)"*,
///    그리고 *"명함 원본 사진은 … 회사 서버에 암호화하여 저장됩니다"*.
///    **켜지 않는 쪽이 오히려 문서와 실물이 어긋난 상태였다.**
/// 2. **관문 셋이 닫혔다** — 계정 전환에서 선택 전 서버 쓰기 금지(`auth_gate`
///    *"여기서 처음으로 서버 쓰기가 허용된다"*), 전환 다이얼로그 문구, 그리고
///    이중 사본(Firestore 실측: 계정 15개 중 명함 보유 7개, 건수가 제각각이라
///    같은 묶음의 복제가 아니다 — 08-21의 3중 상태가 아니다).
/// 3. **시행일이 아니라 일반 사용자 배포가 기준이다**(사용자 확정) — 시행일을
///    게이트로 쓰면 이용자가 없는 테스트 기간에 개발만 막힌다.
///
/// ⚠️ **다시 끄게 되면** 아래 `skip` 이 풀리면서 "꺼져 있으면 네트워크에 손대지
/// 않는다"가 다시 검사된다. 그 성질은 버리지 않았다.
void main() {
  group('명함 사진 서버 저장 게이트', () {
    test('⭐ 켜져 있다 — 근거는 이 파일 맨 위에 있다', () {
      expect(
        CardPhotoBackupService.kCardPhotoBackupEnabled,
        isTrue,
        reason: '2026-08-26 사용자 결정으로 켰다(내 명함·등록 명함 모두 서버로). '
            '다시 끌 일이 생기면 이 기대값과 함께 아래 skip 조건도 같이 본다 — '
            '끄면 "네트워크에 손대지 않는다" 검사가 자동으로 되살아난다.',
      );
    });

    // 아래 넷은 **꺼진 상태의 성질**을 지킨다. 켜져 있는 동안은 Firebase를
    // 실제로 부르므로(테스트 환경에는 초기화가 없다) 의미가 없어 건너뛴다.
    // 다시 끄면 자동으로 되살아난다 — 성질을 버리지 않고 재워 둔 것이다.
    final skipWhenOn = CardPhotoBackupService.kCardPhotoBackupEnabled
        ? '플래그가 켜져 있어 "꺼진 상태의 성질"은 지금 검사 대상이 아니다'
        : null;

    // Firebase를 초기화하지 않은 상태에서 도는 테스트다. 플래그가 꺼져 있으면
    // 각 메서드가 Storage 인스턴스에 손도 대지 않아야 하므로, 예외 없이
    // 돌아오는 것 자체가 "네트워크 경로로 들어가지 않았다"는 증거가 된다.
    // (들어갔다면 Firebase 미초기화로 예외가 난다.)
    final service = CardPhotoBackupService();

    test('꺼져 있으면 업로드는 아무 일도 하지 않는다', skip: skipWhenOn, () async {
      final result = await service.upload(
        uid: 'u1',
        contactId: 'c1',
        encryptedFilePath: '/tmp/없는파일.enc',
      );
      expect(result, isFalse);
    });

    test('꺼져 있으면 다운로드는 아무 일도 하지 않는다', skip: skipWhenOn, () async {
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

    test('꺼져 있으면 삭제도 조용히 통과한다', skip: skipWhenOn, () async {
      // 삭제는 반환값이 없다 — 예외가 나지 않는 것이 확인 대상이다.
      await service.delete(uid: 'u1', contactId: 'c1');
    });

    test('꺼져 있으면 전체 삭제는 실패 0건으로 돌아온다', skip: skipWhenOn, () async {
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
