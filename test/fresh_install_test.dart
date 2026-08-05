import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/core/services/fresh_install_service.dart';

/// iOS Keychain은 앱을 삭제해도 지워지지 않는다(backlog 추가 78). 재설치를
/// 감지해 보안 저장소를 비우는 로직이 의도대로 동작하는지 확인한다.

/// `deleteAll()` 호출 여부만 기록하는 가짜 보안 저장소.
class _FakeSecureStorage extends FlutterSecureStorage {
  const _FakeSecureStorage(this.calls);

  final List<String> calls;

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('deleteAll');
  }
}

/// `deleteAll()`이 던지는 경우(최초 설치 등)를 흉내 낸다.
class _ThrowingSecureStorage extends FlutterSecureStorage {
  const _ThrowingSecureStorage();

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('보안 저장소 접근 불가');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('설치 표식이 없으면(=재설치) 보안 저장소를 비우고 세션을 끊는다', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    var signedOut = false;

    final purged = await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async => signedOut = true,
    );

    expect(purged, isTrue);
    expect(calls, ['deleteAll']);
    expect(signedOut, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(FreshInstallService.markerKey),
      isTrue,
      reason: '다음 실행부터는 정리하지 않도록 표식을 남겨야 한다',
    );
  });

  test('표식은 없지만 기존 앱 데이터가 남아 있으면 정리하지 않는다', () async {
    // 이 로직이 없던 버전에서 업데이트한 기존 사용자 — 앱을 지운 적이 없으므로
    // 로그아웃시키면 안 된다. 진짜 재설치라면 shared_preferences가 통째로
    // 비어 있다는 점으로 구분한다.
    SharedPreferences.setMockInitialValues({'saved_contacts_v2': 'ciphertext'});
    final calls = <String>[];
    var signedOut = false;

    final purged = await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async => signedOut = true,
    );

    expect(purged, isFalse);
    expect(calls, isEmpty);
    expect(signedOut, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(FreshInstallService.markerKey),
      isTrue,
      reason: '다음 재설치를 감지할 수 있도록 표식은 남겨야 한다',
    );
  });

  test('설치 표식이 있으면 아무것도 건드리지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      FreshInstallService.markerKey: true,
    });
    final calls = <String>[];
    var signedOut = false;

    final purged = await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async => signedOut = true,
    );

    expect(purged, isFalse);
    expect(calls, isEmpty, reason: '멀쩡히 쓰던 사용자를 로그아웃시키면 안 된다');
    expect(signedOut, isFalse);
  });

  test('두 번째 실행에서는 정리가 반복되지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];

    await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async {},
    );
    await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async {},
    );

    expect(calls, ['deleteAll']);
  });

  test('보안 저장소 정리가 실패해도 표식은 남기고 진행한다', () async {
    SharedPreferences.setMockInitialValues({});

    final purged = await FreshInstallService.purgeIfReinstalled(
      secureStorage: const _ThrowingSecureStorage(),
      signOut: () async {},
    );

    expect(purged, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FreshInstallService.markerKey), isTrue);
  });

  test('세션 종료가 실패해도 정리는 완료된 것으로 본다', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];

    final purged = await FreshInstallService.purgeIfReinstalled(
      secureStorage: _FakeSecureStorage(calls),
      signOut: () async => throw StateError('Firebase 미초기화'),
    );

    expect(purged, isTrue);
    expect(calls, ['deleteAll']);
  });
}
