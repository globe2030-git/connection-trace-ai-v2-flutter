import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 인증번호 요청 결과. 🚨 **인증번호는 여기 없다** — 서버가 응답에 싣지 않는다.
enum PhoneOtpRequestResult {
  /// 보냈다(또는 테스트 번호라 보내지 않고 통과시켰다).
  sent,

  /// 아직 3분이 안 지났다.
  tooSoon,

  /// 오늘 받을 수 있는 횟수를 다 썼다.
  dailyCap,

  /// 번호 모양이 잘못됐다.
  invalidNumber,

  /// 보내지 못했다(발송사 키 없음·발송사 오류 등).
  sendFailed,

  /// 그 밖의 실패.
  unknown,
}

/// 인증번호 확인 결과.
enum PhoneOtpConfirmResult {
  verified,

  /// 3분이 지났다. 화면 문구는 "시간이 지났어요, 다시 받기"(추가 563).
  expired,

  /// 인증번호가 틀렸다.
  mismatch,

  /// 여러 번 틀려서 이 인증번호가 죽었다.
  tooManyAttempts,

  /// 인증번호를 아직 안 받았다.
  noChallenge,

  /// ⏸️ 이 번호가 **이미 다른 계정**에 있다. 1차 범위에서는 잇지 않고
  /// 알리기만 한다(추가 564).
  alreadyTaken,

  unknown,
}

/// 휴대전화번호 인증(추가 565).
///
/// ## 🚨 이 클래스가 판정하지 않는다
///
/// 만료·상한·정답 여부는 **전부 서버가 본다**. 여기서 남은 시간을 세거나
/// 횟수를 저장하지 않는다 — 기기 시계를 돌리거나 앱을 지웠다 깔면 뚫린다.
///
/// 화면이 타이머를 보여 주긴 하지만 그것은 **표시일 뿐**이고, 실제로 막는
/// 것은 서버다. 타이머가 0이 되기 전에 눌러도 서버가 거부한다.
class PhoneVerificationService {
  static const String region = 'asia-northeast3';

  /// 디버그 빌드에서 게이트를 강제로 켠다(검증용).
  ///
  /// `flutter build apk --debug --dart-define=PHONE_GATE_FORCE=true`
  ///
  /// ⚠️ 기본값은 `false`다. 그리고 [kDebugMode] 뒤에 있어 **릴리스에서는
  /// 분기 자체가 사라진다.**
  static const bool _forceGateInDebug =
      bool.fromEnvironment('PHONE_GATE_FORCE');

  /// 🚨 **게이트를 켤지 말지 — 원격 스위치.**
  ///
  /// ## 왜 스위치가 필요한가
  ///
  /// 게이트는 `phoneVerifiedAt`이 없으면 막는데, **기존 이용자에게는 그 필드가
  /// 없다.** 그래서 스위치가 없으면 **새 빌드를 받는 순간 기존 테스터 전원이
  /// 인증 화면에 갇힌다** — 건너뛰기가 없고 뒤로가기도 막혀 있어서 나갈
  /// 길이 아예 없다.
  ///
  /// ⚠️ **자동 테스트로는 안 보이는 층이다.** 테스트도 CI도 초록인데
  /// 병합하면 사람이 잠긴다. 규칙이 아니라 *"누구에게 무슨 일이 일어나는가"*를
  /// 봐야 나온다.
  ///
  /// ## 지갑(과금) 코드가 쓴 방식과 같다 (CLAUDE.md 6절)
  ///
  /// ```
  /// 코드는 main 에 올라간다
  /// 서버에 배포돼도 켜지지 않는다
  /// 실제 스위치는 「필드를 만드는 것」 하나 — 그것만 사용자 결정
  /// ```
  ///
  /// 🚨 **끄는 쪽이 기본값이다.** 문서가 없어도, 필드가 없어도, 읽기에
  /// 실패해도 **안 막는다.** *"설정이 없으면 막는다"*가 되면 설정을 깜빡한
  /// 것이 사람을 가두는 일이 된다.
  static Future<bool> isGateEnabled() async {
    // 🚨 **디버그 빌드에서만 강제로 켤 수 있다.** 검증용이다.
    //
    // ## 왜 서버 설정을 안 쓰나
    //
    // 게이트를 실기기에서 보려면 스위치가 켜져 있어야 하는데, **서버에 켜
    // 두면 끄는 것을 잊을 수 있다.** 잊으면 켜진 채로 남고, 나중에 빌드가
    // 나가는 순간 **아무 신호 없이 전원이 잠긴다.**
    //
    // 📌 여기서는 **아예 안 만드는 길**이 있다 — 빌드 인자로만 켜고,
    // 그 빌드는 검증용이라 사라진다. **끌 것이 없으니 잊을 것도 없다.**
    //
    // ## 🚨 릴리스에서는 존재하지 않는다
    //
    // `kDebugMode`가 릴리스에서 컴파일 타임 상수 `false`라 이 분기는
    // **트리 셰이킹으로 통째로 사라진다.** 인자를 넣어 릴리스를 구워도
    // 켜지지 않는다 — 테스트 번호 목록과 달리 **운영에 남을 수 있는 값이
    // 아니다.**
    if (kDebugMode && _forceGateInDebug) return true;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('phoneVerification')
          .get();
      // 문서가 없으면 꺼짐.
      final data = snap.data();
      if (data == null) return false;
      // 필드가 없거나 true가 아니면 꺼짐.
      return data['enforce'] == true;
    } catch (e) {
      debugPrint('phoneVerification 설정 조회 실패: ${e.runtimeType}');
      // 🚨 못 읽으면 끈다 — 막지 않는다.
      return false;
    }
  }

  /// 이 계정이 번호 인증을 마쳤는지.
  ///
  /// ⚠️ **못 읽으면 `null`을 준다** — `false`가 아니다. 둘은 다르다.
  /// `false`는 *"안 했다"*이고 `null`은 *"모른다"*인데, 모르는 것을 안 한
  /// 것으로 다루면 **읽기가 한 번 실패한 사람이 인증 화면에 갇힌다.**
  /// 부르는 쪽이 그 구분을 보고 정한다.
  static Future<bool?> isVerified(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null) return false;
      return data['phoneVerifiedAt'] != null;
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다(다른 서비스와 동일 원칙).
      debugPrint('phoneVerified 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 인증번호를 요청한다.
  ///
  /// [retryAfterMs]는 서버가 준 값이다 — 화면이 *"몇 초 뒤에 다시"*를 보여
  /// 줄 때 **기기 시계로 세지 말고 이 값을 쓴다.**
  static Future<({PhoneOtpRequestResult result, int? retryAfterMs})> request(
    String phone,
  ) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable('phoneOtpRequest');
      await callable.call<Map<String, dynamic>>({'phone': phone});
      return (result: PhoneOtpRequestResult.sent, retryAfterMs: null);
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? details['reason'] as String? : null;
      final retryAfterMs = details is Map
          ? (details['retryAfterMs'] as num?)?.toInt()
          : null;
      return (
        result: switch (e.code) {
          'invalid-argument' => PhoneOtpRequestResult.invalidNumber,
          'unavailable' => PhoneOtpRequestResult.sendFailed,
          'resource-exhausted' => reason == 'daily-cap'
              ? PhoneOtpRequestResult.dailyCap
              : PhoneOtpRequestResult.tooSoon,
          _ => PhoneOtpRequestResult.unknown,
        },
        retryAfterMs: retryAfterMs,
      );
    } catch (e) {
      debugPrint('phoneOtpRequest 호출 실패: ${e.runtimeType}');
      return (result: PhoneOtpRequestResult.unknown, retryAfterMs: null);
    }
  }

  /// 인증번호를 확인한다.
  static Future<PhoneOtpConfirmResult> confirm({
    required String phone,
    required String code,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable('phoneOtpConfirm');
      await callable.call<Map<String, dynamic>>({
        'phone': phone,
        'code': code,
      });
      return PhoneOtpConfirmResult.verified;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final reason = details is Map ? details['reason'] as String? : null;
      if (e.code == 'already-exists') {
        return PhoneOtpConfirmResult.alreadyTaken;
      }
      return switch (reason) {
        'expired' => PhoneOtpConfirmResult.expired,
        'too-many-attempts' => PhoneOtpConfirmResult.tooManyAttempts,
        'no-challenge' => PhoneOtpConfirmResult.noChallenge,
        'mismatch' => PhoneOtpConfirmResult.mismatch,
        _ => PhoneOtpConfirmResult.unknown,
      };
    } catch (e) {
      debugPrint('phoneOtpConfirm 호출 실패: ${e.runtimeType}');
      return PhoneOtpConfirmResult.unknown;
    }
  }
}
