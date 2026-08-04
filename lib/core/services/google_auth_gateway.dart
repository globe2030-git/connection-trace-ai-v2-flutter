import 'package:google_sign_in/google_sign_in.dart';

/// `GoogleSignIn.instance.initialize()`는 "정확히 한 번만" 호출해야 하고 두 번째
/// 호출부터는 동작이 정의되어 있지 않다. 이메일 동기화(EmailSyncService)와
/// SNS 로그인(AuthRepository)이 같은 GoogleSignIn 싱글턴을 공유해서 쓰기 때문에,
/// 초기화 호출을 이 게이트웨이 하나로 모아 중복 호출을 막는다.
class GoogleAuthGateway {
  static Future<void>? _initFuture;

  static Future<void> ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize();
  }
}
