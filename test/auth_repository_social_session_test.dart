import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/data/repositories/auth_repository.dart';

/// ⚠️ **로그아웃·탈퇴 때 웹뷰 쿠키를 지우는지**를 못박는다.
///
/// 안 지우면 같은 기기의 다음 사람이 '카카오로 계속하기'를 눌렀을 때
/// 아이디를 묻지 않고 **앞사람 계정으로 들어간다.** 이 앱에서 그것은 곧
/// 남의 명함(제3자 개인정보)이 통째로 열리는 것이다.
///
/// 📌 이 결함은 **코드 리뷰로 잡혔다.** 실기기에서도 계정을 바꿔 가며
/// 눌러 보지 않으면 안 보인다 — 혼자 쓰는 기기에서는 늘 자기 계정이라
/// "잘 된다"로만 보인다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Firebase Auth 는 이 테스트에서 부르지 않는다. 혹시 플랫폼 채널을
    // 타더라도 조용히 넘어가도록 비워 둔다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/firebase_auth'),
      (call) async => null,
    );
  });

  test('⚠️ 로그아웃하면 소셜 웹뷰 세션을 지운다', () async {
    var cleared = 0;
    final repo = AuthRepository(clearWebSession: () async => cleared++);

    await repo.signOut();

    expect(cleared, 1, reason: '쿠키를 안 지우면 다음 사람이 앞사람 계정으로 들어간다');
  });

  // 📌 계정 삭제 경로는 여기서 못 덮는다 — 첫 줄이 FirebaseAuth.instance 라
  // Firebase 초기화가 필요하고, `flutter test`에는 그것이 없다. 코드에는
  // 로그아웃과 같은 자리에 같은 정리를 넣어 뒀고(주석 참고), 실제 동작은
  // 실기기 확인 대상이다. **자동 테스트가 덮지 못하는 자리라고 적어 둔다** —
  // 안 적으면 다음 사람이 "테스트가 있으니 됐다"고 읽는다.

  test('쿠키 정리가 실패해도 로그아웃 자체는 끝난다', () async {
    // 정리에 실패했다고 로그아웃을 막으면 이용자는 로그아웃을 못 한다.
    // 그쪽이 더 나쁜 결과다.
    final repo = AuthRepository(
      clearWebSession: () async => throw Exception('플랫폼 채널 없음'),
    );

    await expectLater(repo.signOut(), completes);
    expect(repo.isSignedIn, isFalse);
  });
}
