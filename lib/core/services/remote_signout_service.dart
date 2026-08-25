import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 원격 로그아웃 — **이 계정으로 로그인한 모든 기기의 세션을 끊는다**
/// (서버 콜러블 `revokeMySessions`, `functions/src/index.ts`).
///
/// ## 왜 필요한가
///
/// 폰을 잃어버렸을 때 이용자가 할 수 있는 일이 **계정 삭제밖에 없었다**
/// (추가 471, 법률 조사 추가 458이 찾아낸 공백). 그런데 계정 삭제는 명함과
/// 프로필까지 서버에서 지운다 — 되찾으려던 것이 함께 사라진다. **잃어버린
/// 것은 기기인데 데이터를 버려야 했다.**
///
/// ## ⚠️ 지금 이 기기도 함께 끊긴다
///
/// 서버의 `revokeRefreshTokens`는 **그 uid의 모든 세션**을 무효로 만든다.
/// 부르고 있는 기기도 예외가 아니다. 그래서 **누르기 전에 그 사실을 알려야
/// 한다** — 안 알리면 되찾은 뒤 자기 폰이 로그아웃돼 있는 것을 결함으로
/// 읽는다(`settings_view.dart`의 확인 다이얼로그가 그 몫을 한다).
///
/// ## 끊긴 것을 앱이 어떻게 아나 — **새로 만들지 않았다**
///
/// 세션이 끊긴 기기는 토큰을 갱신할 때 `user-token-expired`를 받는다.
/// [AuthRepository.isAccountAlreadyDeleted]가 **그 코드를 이미 잡고 있다** —
/// 계정 삭제를 감지하려고 만든 것인데 기기 입장에서는 상태가 같다
/// (`auth_repository.dart:566~570`). 감지 코드를 새로 만들지 않는다.
///
/// ## ⚠️ 실패를 삼키지 않는다
///
/// [AccountBootstrapService]는 실패해도 조용히 넘긴다 — 그쪽은 부가 기능이고
/// 실패해도 이용자가 잃는 것이 없기 때문이다. **여기는 반대다.** 이용자는
/// *"끊었다"*고 믿고 화면을 떠나는데 실제로는 안 끊긴 상태가 가장 나쁘다.
/// 그래서 예외를 그대로 올려 호출부가 실패를 화면에 보이게 한다.
class RemoteSignOutService {
  static const String region = 'asia-northeast3';

  /// 모든 기기의 세션을 끊는다. 실패하면 [RemoteSignOutException]을 던진다.
  static Future<void> revokeAllSessions() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable('revokeMySessions');
      await callable.call<Map<String, dynamic>>();
    } on FirebaseFunctionsException catch (e) {
      // ⚠️ 개인정보를 남기지 않는다 — 코드만 찍는다(다른 서비스와 같은 원칙).
      debugPrint('revokeMySessions 실패: ${e.code}');
      throw RemoteSignOutException(_messageFor(e.code));
    } catch (e) {
      debugPrint('revokeMySessions 실패: ${e.runtimeType}');
      throw const RemoteSignOutException(
        '세션을 끊지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
      );
    }
  }

  /// 서버 오류 코드를 이용자가 읽을 문장으로 바꾼다.
  ///
  /// ⚠️ `not-found`를 따로 다룬다 — **함수가 아직 배포되지 않았을 때** 나오는
  /// 코드다. 이 기능은 서버 함수가 있어야 도는데 배포는 별도 결정이라, 그
  /// 사이에 누른 사람이 *"고장 났다"*로 읽지 않게 다른 문장을 준다.
  static String _messageFor(String code) => switch (code) {
    'unauthenticated' => '로그인이 필요해요.',
    'not-found' => '아직 준비 중인 기능이에요. 조금만 기다려 주세요.',
    _ => '세션을 끊지 못했어요. 잠시 후 다시 시도해 주세요.',
  };
}

/// 원격 로그아웃 실패. [message]는 그대로 화면에 보여도 되는 문장이다.
class RemoteSignOutException implements Exception {
  final String message;

  const RemoteSignOutException(this.message);

  @override
  String toString() => message;
}
