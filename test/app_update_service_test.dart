import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/app_update_service.dart';

void main() {
  AppUpdateService service({
    required int build,
    Map<String, dynamic>? config,
    bool throwOnFetch = false,
  }) => AppUpdateService(
    currentBuild: () async => build,
    fetchConfig: () async {
      if (throwOnFetch) throw Exception('network');
      return config;
    },
  );

  const config = {
    'minSupportedBuild': 5,
    'latestBuild': 10,
    'iosUrl': 'https://apps.apple.com/app/id0',
    'androidUrl': 'https://play.google.com/store/apps/details?id=x',
    'message': '업데이트해 주세요',
  };

  test('최소 지원 미만이면 강제(forced)', () async {
    final s = await service(build: 4, config: config).check();
    expect(s.level, AppUpdateLevel.forced);
    expect(s.message, '업데이트해 주세요');
  });

  test('최소 이상이지만 최신 미만이면 권장(recommended)', () async {
    final s = await service(build: 7, config: config).check();
    expect(s.level, AppUpdateLevel.recommended);
  });

  test('최신이면 안내 없음(none)', () async {
    final s = await service(build: 10, config: config).check();
    expect(s.level, AppUpdateLevel.none);
  });

  test('최신보다 높아도 안내 없음', () async {
    final s = await service(build: 12, config: config).check();
    expect(s.level, AppUpdateLevel.none);
  });

  test('설정 문서가 없으면 안내 없음', () async {
    final s = await service(build: 1, config: null).check();
    expect(s.level, AppUpdateLevel.none);
  });

  test('빌드번호를 못 읽으면(0) 안내 없음', () async {
    final s = await service(build: 0, config: config).check();
    expect(s.level, AppUpdateLevel.none);
  });

  test('조회 실패는 fail-open — 앱을 막지 않는다', () async {
    final s = await service(build: 1, throwOnFetch: true).check();
    expect(s.level, AppUpdateLevel.none);
  });

  test('경계값 — min과 같으면 강제 아님', () async {
    final s = await service(build: 5, config: config).check();
    expect(s.level, AppUpdateLevel.recommended); // 5 >= min(5), < latest(10)
  });
}
