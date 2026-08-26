/// **배선 테스트** — 명함을 지울 때 **장부에서도 지우는가**(추가 518).
///
/// `card_photo_backfill_wiring_test.dart` 와 같은 이유로 있다. 이 저장소가
/// 추가 79에서 겪은 사고 — *"서비스는 정상인데 부르는 쪽이 없다"* — 가
/// 여기서 그대로 재현됐다.
///
/// ```
/// CardPhotoBackupStateService.forget()   만들어져 있었다
/// 저장소 전체에서 부르는 곳                0건
/// ```
///
/// 🚨 그 결과 **서버 객체는 지워지는데 장부에는 「백업됨」으로 남았다.**
/// 2026-08-26 실측: 서버 102건인데 설정 화면은 **104장**이라고 표시했다.
/// 차이 2건은 그날 만들었다 지운 시험 명함 둘과 정확히 일치했다.
///
/// ⚠️ 그리고 지운 명함이 **한도(2,000장)를 계속 차지한다.** 등록·삭제를
/// 반복하면 실제 저장량보다 훨씬 빨리 한도에 닿는다.
///
/// 📌 **이 결함은 추가 517을 고치기 전에는 드러날 수 없었다.** 그때는 서버
/// 삭제 자체가 규칙에 막혀 있어 **장부와 서버가 어차피 둘 다 안 줄었고**,
/// 둘을 구분할 방법이 없었다. 하나를 고치니 다음 것이 보였다.
library;

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_service.dart';
import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';
import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 장부 호출을 세는 가짜. 진짜 저장은 하지 않는다.
class _SpyLedger extends CardPhotoBackupStateService {
  final List<String> forgotten = [];
  int clearCount = 0;

  @override
  Future<void> forget(String contactId) async => forgotten.add(contactId);

  @override
  Future<void> clear() async => clearCount++;
}

/// 서버를 안 부르는 가짜. 이 테스트는 **장부만** 본다.
class _NoopBackup extends CardPhotoBackupService {
  @override
  Future<bool> delete({required String uid, required String contactId}) async =>
      true;

  @override
  Future<int> deleteAllForUser(String uid) async => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ContactImageService build(_SpyLedger ledger) => ContactImageService(
    photoBackup: _NoopBackup(),
    backupState: ledger,
  );

  group('명함 하나를 지울 때', () {
    test('🚨 장부에서도 지운다 — 안 지우면 한도를 계속 차지한다', () async {
      final ledger = _SpyLedger();
      await build(ledger).deleteCardImage(
        '',
        uid: 'uid_test',
        contactId: 'contact_1',
      );

      expect(ledger.forgotten, ['contact_1']);
    });

    test('uid 가 없으면(로그아웃 상태) 장부를 안 건드린다', () async {
      // 서버에 올린 적이 없으므로 지울 장부 항목도 없다.
      final ledger = _SpyLedger();
      await build(ledger).deleteCardImage('', contactId: 'contact_1');

      expect(ledger.forgotten, isEmpty);
    });

    test('contactId 가 없으면 장부를 안 건드린다', () async {
      final ledger = _SpyLedger();
      await build(ledger).deleteCardImage('', uid: 'uid_test');

      expect(ledger.forgotten, isEmpty);
    });
  });

  group('계정 삭제(회원 탈퇴)', () {
    test('🚨 장부를 통째로 비운다 — 남으면 다음 계정 화면에 앞 사람 숫자가 뜬다', () async {
      final ledger = _SpyLedger();
      await build(ledger).deleteAllCardImages(uid: 'uid_test');

      expect(ledger.clearCount, 1);
    });

    test('uid 없이 불러도(기기 정리만) 장부는 비운다', () async {
      // 파일을 다 지웠는데 장부만 남으면 화면이 거짓말한다.
      final ledger = _SpyLedger();
      await build(ledger).deleteAllCardImages();

      expect(ledger.clearCount, 1);
    });
  });
}
