// 재설치 후 한도 카운터 복구 검사(2026-08-16, 추가 256).
//
// 무엇을 지키려는 검사인가: **한도가 천장 구실을 계속하게 하는 것.**
//
// 한도 판정의 재료(`syncedCount`)는 SharedPreferences 한 곳에만 있어서, 앱을
// 지웠다 깔면 0으로 돌아간다. 서버에는 사진이 그대로 있으므로 그 상태로는
// 한도를 **한 번 더** 채울 수 있었다. 악의가 아니라 **기기 변경·재설치라는,
// 이 기능을 만든 이유 그 자체**가 한도를 무너뜨리는 경로였다.
//
// ⚠️ 특히 지켜야 할 것은 **"못 읽었다"를 0으로 적지 않는 것**이다. 회선이
// 나쁠 때 0으로 적으면 한도가 **느슨해지는 방향**으로 틀리는데, 그건 지금
// 고치려는 결함과 정확히 같은 모양이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('markSyncedAll — 서버 실물로 카운터를 되살린다', () {
    test('빈 상태에서 서버 목록을 적으면 그만큼 세어진다', () async {
      final svc = CardPhotoBackupStateService();
      expect((await svc.load()).syncedCount, 0, reason: '재설치 직후');

      await svc.markSyncedAll({'c1', 'c2', 'c3'});

      final map = await svc.load();
      expect(map.syncedCount, 3);
      expect(map.stateOf('c2'), CardPhotoBackupState.synced);
    });

    test('빈 목록이면 아무것도 적지 않는다', () async {
      final svc = CardPhotoBackupStateService();
      await svc.markSyncedAll(const <String>[]);
      expect((await svc.load()).raw, isEmpty);
    });

    test('빈 문자열 id는 무시한다 — 파일명이 이상해도 카운터가 부풀지 않는다', () async {
      final svc = CardPhotoBackupStateService();
      await svc.markSyncedAll({'', 'c1'});
      expect((await svc.load()).syncedCount, 1);
    });

    test('⚠️ 덮어쓰지 않고 덧붙인다 — 기존 사유를 잃지 않는다', () async {
      // 기존 기록에는 "왜 안 올라갔는지"까지 들어 있다. 서버 목록으로 통째로
      // 갈아치우면 그 사유가 사라진다.
      final svc = CardPhotoBackupStateService();
      await svc.record('c9', CardPhotoBackupState.quotaExceeded);

      await svc.markSyncedAll({'c1'});

      final map = await svc.load();
      expect(map.stateOf('c9'), CardPhotoBackupState.quotaExceeded);
      expect(map.stateOf('c1'), CardPhotoBackupState.synced);
      expect(map.syncedCount, 1, reason: 'quota는 synced로 세지 않는다');
    });

    test('같은 id를 두 번 적어도 두 번 세지 않는다', () async {
      final svc = CardPhotoBackupStateService();
      await svc.markSyncedAll({'c1'});
      await svc.markSyncedAll({'c1'});
      expect((await svc.load()).syncedCount, 1);
    });
  });

  group('⚠️ 복구가 한도를 다시 걸리게 하는가 — 이 결함의 본체', () {
    test('재설치 전 한도에 닿았다면, 복구 후에도 닿아 있어야 한다', () async {
      const quota = 3;

      // 재설치 전: 3장을 올려 한도를 채웠다.
      final before = CardPhotoBackupStateService();
      await before.markSyncedAll({'c1', 'c2', 'c3'});
      expect((await before.load()).syncedCount, quota);

      // 재설치: SharedPreferences가 통째로 비워진다.
      SharedPreferences.setMockInitialValues({});
      final after = CardPhotoBackupStateService();
      expect(
        (await after.load()).syncedCount,
        0,
        reason: '이 0이 결함의 정체 — 서버에는 3장이 그대로 있다',
      );

      // 복구: 서버 목록(c1·c2·c3)으로 되살린다.
      await after.markSyncedAll({'c1', 'c2', 'c3'});
      expect((await after.load()).syncedCount, quota);
    });

    test('⚠️ 목록을 못 읽었을 때(null)는 부르지 않으므로 0이 유지된다', () async {
      // listSyncedContactIds는 실패를 null로, "없음"을 빈 집합으로 돌려준다.
      // 호출부는 null이면 markSyncedAll을 부르지 않는다 — 여기서는 그 계약이
      // 지켜졌을 때 상태가 그대로라는 것만 고정한다.
      final svc = CardPhotoBackupStateService();
      await svc.record('c9', CardPhotoBackupState.failed);

      // (null이라 아무 호출도 하지 않은 상황)

      final map = await svc.load();
      expect(map.stateOf('c9'), CardPhotoBackupState.failed);
      expect(map.syncedCount, 0);
    });
  });
}
