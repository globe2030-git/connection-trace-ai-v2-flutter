import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// 로그인 시 1회(사실상 매 로그인마다 불러도 무해하게) 호출하는 서버
/// 부트스트랩 — 신규 콜러블 `bootstrapAccount`를 불러 (a) 무료체험
/// 크레딧을 uid당 1회만 지급하고(멱등) (b) 본인 리퍼럴 코드를 발급한다
/// (멱등). 지급/발급 로직 자체는 서버(functions/src/index.ts
/// `bootstrapAccount`)에 있다 — 근거:
/// docs/planning/ai-credit-wallet-spec.md §3-1,
/// docs/planning/monetization-referral-implementation-spec-2026-08-14.md.
///
/// **왜 매 로그인마다 불러도 안전한가**: 서버가
/// `aiUsage.freeGrantedAt`/`users/{uid}.referralCode` 존재 여부로 멱등
/// 가드를 걸므로, 이 함수를 몇 번을 불러도 실제 지급·발급은 uid당 딱 한
/// 번만 일어난다.
///
/// **실패해도 로그인 자체를 막지 않는다** — Apple refresh token 저장
/// (`AuthRepository._storeAppleRefreshTokenOnServer`)과 같은 패턴으로,
/// 호출부는 반드시 이 메서드를 try-catch 없이 그냥 불러도 되게(내부에서
/// 이미 모든 예외를 삼킨다) 만든다.
class AccountBootstrapService {
  static const String region = 'asia-northeast3';

  /// 서버 응답의 `referralCode`를 반환한다. 실패하면 null — 지금은 이
  /// 값을 화면에서 아직 안 쓰지만(다음 라운드에서 리퍼럴 UI가 사용할
  /// 예정), 호출부가 필요해지면 바로 쓸 수 있게 반환값을 남겨 둔다.
  static Future<String?> call() async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable('bootstrapAccount');
      final result = await callable.call<Map<String, dynamic>>();
      return result.data['referralCode'] as String?;
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다(다른 서비스와 동일 원칙).
      debugPrint('bootstrapAccount 호출 실패: ${e.runtimeType}');
      return null;
    }
  }
}
