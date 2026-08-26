/// **배선 테스트** — 소급 업로드를 "실제로 부르는가", 그리고 **부르면 안 될
/// 때 안 부르는가"(추가 508).
///
/// `contacts_repository_wiring_test.dart`와 같은 이유로 있다. 그 파일의 머리말이
/// 말하는 사고가 이 기능에 그대로 적용된다 — 서비스 단위 테스트는 전부 초록인데
/// **부르는 쪽이 없어서** 아무 일도 안 일어나는 것.
///
/// 🚨 그런데 이 기능은 반대쪽 위험이 더 무겁다. **부르면 안 되는데 부르는 것**이다.
/// 계정 전환에서 "교체"를 고른 이용자의 명함 사진을 새 계정 서버로 올리면
/// **제3자(명함 주인) 개인정보의 근거 없는 제공**이 된다. 글자 백업에서 이미
/// 한 번 일어난 일이고, 그래서 `skipServerMigration` 인자가 생겼다.
library;

import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 부름을 세는 가짜. 진짜 업로드는 하지 않는다.
class _SpyImageService extends ContactImageService {
  final List<String> backfillCalls = [];

  @override
  Future<int> backfillCardImageUploads(String uid) async {
    // ⚠️ **await 앞에서** 기록한다. 호출부가 `unawaited`로 띄우므로, 기다리는
    // 쪽 없이도 여기까지는 동기적으로 온다 — 테스트가 시간을 재지 않아도 된다.
    backfillCalls.add(uid);
    return 0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_SpyImageService> runMaintenance({
    required bool skipServerMigration,
  }) async {
    final spy = _SpyImageService();
    final repo = ContactsRepository(contactImageService: spy);
    await repo.setCurrentUid('uid_test');
    await repo.runPostSyncMaintenance(
      skipServerMigration: skipServerMigration,
    );
    return spy;
  }

  test('⭐ 로그인 뒤 뒤처리에서 소급 업로드가 실제로 불린다', () async {
    final spy = await runMaintenance(skipServerMigration: false);
    expect(
      spy.backfillCalls,
      ['uid_test'],
      reason: 'runPostSyncMaintenance가 backfillCardImageUploads를 불러야 한다',
    );
  });

  // 🚨 이 파일에서 가장 중요한 검사다.
  test('🚨 "교체"를 고른 계정 전환에서는 부르지 않는다', () async {
    final spy = await runMaintenance(skipServerMigration: true);
    expect(
      spy.backfillCalls,
      isEmpty,
      reason: '이전 계정의 명함 사진을 새 계정 서버로 올리면 '
          '제3자 개인정보의 근거 없는 제공이 된다',
    );
  });

  test('로그인 전(uid 없음)에는 부르지 않는다', () async {
    final spy = _SpyImageService();
    final repo = ContactsRepository(contactImageService: spy);
    await repo.runPostSyncMaintenance();
    expect(spy.backfillCalls, isEmpty);
  });
}
