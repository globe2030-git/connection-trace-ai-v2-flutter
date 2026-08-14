import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/app_update_service.dart';

void main() {
  AppUpdateService service({
    required int build,
    Map<String, dynamic>? config,
    bool throwOnFetch = false,
    bool isIos = false,
  }) => AppUpdateService(
    currentBuild: () async => build,
    fetchConfig: () async {
      if (throwOnFetch) throw Exception('network');
      return config;
    },
    isIos: () => isIos,
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

  group('스토어 URL 방어적 재검증(ADMIN-VULN-003)', () {
    // Rules가 이미 공식 스토어 host만 저장하도록 강제하지만, 클라이언트도
    // 한 번 더 검증해 낡은 배포·데이터 불일치로 임의 URL이 들어와도 버튼이
    // 아무것도 열지 않게 한다. 안내 자체(forced/recommended)는 그대로 뜬다.
    test('공식 host가 아니면 storeUrl이 null — 안내는 그대로 뜬다', () async {
      final s = await service(
        build: 4,
        config: {
          'minSupportedBuild': 5,
          'latestBuild': 10,
          'iosUrl': 'https://evil.example.com/app',
          'androidUrl': 'https://evil.example.com/app',
        },
      ).check();
      expect(s.level, AppUpdateLevel.forced);
      expect(s.storeUrl, isNull);
    });

    test('http(비-https) 스킴이면 storeUrl이 null', () async {
      final s = await service(
        build: 4,
        config: {
          'minSupportedBuild': 5,
          'latestBuild': 10,
          'androidUrl': 'http://play.google.com/store/apps/details?id=x',
        },
      ).check();
      expect(s.level, AppUpdateLevel.forced);
      expect(s.storeUrl, isNull);
    });

    test('커스텀 스킴이면 storeUrl이 null', () async {
      final s = await service(
        build: 4,
        config: {
          'minSupportedBuild': 5,
          'latestBuild': 10,
          'androidUrl': 'myapp://update',
        },
      ).check();
      expect(s.level, AppUpdateLevel.forced);
      expect(s.storeUrl, isNull);
    });

    test('공식 host면 storeUrl이 그대로 반환된다', () async {
      final s = await service(build: 4, config: config, isIos: true).check();
      expect(s.level, AppUpdateLevel.forced);
      expect(s.storeUrl, 'https://apps.apple.com/app/id0');
    });
  });

  group('플랫폼별 빌드 필드(추가 165 후속)', () {
    const platformConfig = {
      'minSupportedBuild': 1, // 레거시(둘 중 낮은 값) — 있어도 플랫폼 필드가 우선
      'latestBuild': 1,
      'minSupportedBuildIos': 8,
      'latestBuildIos': 12,
      'minSupportedBuildAndroid': 5,
      'latestBuildAndroid': 9,
      'iosUrl': 'https://apps.apple.com/app/id0',
      'androidUrl': 'https://play.google.com/store/apps/details?id=x',
    };

    test('iOS는 iOS 전용 필드로만 판정된다(Android 값과 무관)', () async {
      // Android 최신(9) 이상이지만 iOS 최신(12) 미만 — iOS 기준으로는 권장.
      final s = await service(
        build: 9,
        config: platformConfig,
        isIos: true,
      ).check();
      expect(s.level, AppUpdateLevel.recommended);
    });

    test('Android는 Android 전용 필드로만 판정된다(iOS 값과 무관)', () async {
      // Android 최신(9)과 같아 안내 없음. 같은 빌드가 iOS 필드(최신 12)
      // 기준이었다면 권장(recommended)이 나왔을 것 — android 브랜치가
      // 실제로 iOS 필드를 무시함을 보여준다.
      final s = await service(
        build: 9,
        config: platformConfig,
        isIos: false,
      ).check();
      expect(s.level, AppUpdateLevel.none);
    });

    test('플랫폼 필드가 없으면(구 설정) 레거시 단일 필드로 폴백한다', () async {
      const legacyOnly = {
        'minSupportedBuild': 5,
        'latestBuild': 10,
        'androidUrl': 'https://play.google.com/store/apps/details?id=x',
      };
      final s = await service(
        build: 4,
        config: legacyOnly,
        isIos: false,
      ).check();
      expect(s.level, AppUpdateLevel.forced); // legacy min(5) 기준
    });
  });
}
