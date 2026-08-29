import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/data/repositories/auth_repository.dart';

/// 로그인 화면 「최근」 배지(설계:
/// docs/planning/specs/login-recent-provider-2026-08-29.md)가 읽는
/// `AuthRepository.lastProvider`를 검증한다.
///
/// ⚠️ **실제 SNS 로그인 세 경로(`signInWithGoogle`/`signInWithApple`/
/// `signInWithSocial`)와 계정 삭제(`deleteFirebaseAccountAndLocalSession`)는
/// 여기서 직접 부를 수 없다** — 전부 `FirebaseAuth.instance`를 건드리는데,
/// `flutter test`에는 Firebase 앱 초기화가 없어 `[core/no-app]` 예외가 난다
/// (`auth_repository_social_session_test.dart`가 이미 같은 이유로 계정
/// 삭제 경로를 못 덮는다고 적어 뒀다).
///
/// 그래서 이 테스트는 그 세 경로가 인증 성공 뒤 **실제로 실행하는 것과
/// 똑같은 코드**([AuthRepository.completeSignIn], `@visibleForTesting`)와,
/// 계정 삭제 끝에서 실행하는 것과 똑같은 정리 코드
/// ([AuthRepository.clearLastProviderForAccountDeletion])를 직접 불러
/// 검증한다 — Firebase를 건드리지 않는 순수 로컬 저장 로직이라 가능하다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/firebase_auth'),
      (call) async => null,
    );
  });

  test('로그인 성공 시 lastProvider가 기록된다', () async {
    final repo = AuthRepository(clearWebSession: () async {});
    // 생성자의 비동기 로드가 끝날 때까지 한 틱 기다린다.
    await Future<void>.delayed(Duration.zero);

    expect(repo.lastProvider, isNull, reason: '아직 로그인 전이므로 기록이 없어야 한다');

    await repo.completeSignIn(
      SnsAuthProvider.google,
      displayName: '홍길동',
      email: 'gil@example.com',
      photoUrl: null,
    );

    expect(repo.lastProvider, SnsAuthProvider.google);

    // 인스턴스 상태가 아니라 실제로 shared_preferences에 저장됐는지도 함께
    // 확인한다 — 다음 로그인 화면(새 AuthRepository 인스턴스)이 읽을 값이다.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_login_provider_v1'), 'google');
  });

  test('로그아웃해도 lastProvider는 남는다(세션 키와 분리됐다)', () async {
    final repo = AuthRepository(clearWebSession: () async {});
    await repo.completeSignIn(
      SnsAuthProvider.kakao,
      displayName: null,
      email: null,
      photoUrl: null,
    );
    expect(repo.isSignedIn, isTrue);

    await repo.signOut();

    expect(repo.isSignedIn, isFalse, reason: '로그아웃은 세션을 끝내야 한다');
    expect(
      repo.lastProvider,
      SnsAuthProvider.kakao,
      reason: '「최근」 배지는 로그아웃 뒤에도 보여야 한다 — 존재 이유 자체가 그것이다',
    );
  });

  test('계정 삭제 정리 로직을 부르면 lastProvider가 지워진다', () async {
    final repo = AuthRepository(clearWebSession: () async {});
    await repo.completeSignIn(
      SnsAuthProvider.naver,
      displayName: null,
      email: null,
      photoUrl: null,
    );
    expect(repo.lastProvider, SnsAuthProvider.naver);

    // deleteFirebaseAccountAndLocalSession() 자체는 FirebaseAuth.instance를
    // 건드려 flutter test에서 부를 수 없다(위 클래스 주석 참고) — 그 메서드가
    // 끝에서 호출하는 정리 로직만 따로 검증한다.
    await repo.clearLastProviderForAccountDeletion();

    expect(repo.lastProvider, isNull, reason: '삭제된 계정으로 안내하면 안 된다');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_login_provider_v1'), isNull);
  });

  test('게스트 로그인(QA 전용)은 lastProvider를 기록하지 않는다', () async {
    final repo = AuthRepository(clearWebSession: () async {});

    repo.signInAsGuest();

    expect(repo.isSignedIn, isTrue, reason: '게스트 로그인 자체는 성공해야 한다');
    expect(
      repo.lastProvider,
      isNull,
      reason: '게스트는 실제 SNS 수단이 아니라 「최근」으로 보여줄 의미가 없다',
    );
  });
}
