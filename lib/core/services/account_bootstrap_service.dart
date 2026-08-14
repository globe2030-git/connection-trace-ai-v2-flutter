import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
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
      final deviceId = await _resolveDeviceId();
      final callable = FirebaseFunctions.instanceFor(
        region: region,
      ).httpsCallable('bootstrapAccount');
      final result = await callable.call<Map<String, dynamic>>(
        deviceId == null ? null : {'deviceId': deviceId},
      );
      return result.data['referralCode'] as String?;
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다(다른 서비스와 동일 원칙).
      debugPrint('bootstrapAccount 호출 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 재가입×무료체험 무한 루프 방어(U5)에 쓸 raw device id를 구한다.
  /// iOS는 `identifierForVendor`(device_info_plus), Android는
  /// Settings.Secure.ANDROID_ID(`android_id` 패키지 — device_info_plus는
  /// v9+부터 이 값을 더 이상 제공하지 않아 별도 패키지가 필요하다, 근거는
  /// pubspec.yaml 주석).
  ///
  /// **식별자를 못 구하면(플랫폼 미지원, 시뮬레이터, 권한 문제, 값이 빈
  /// 문자열 등) 반드시 null을 반환한다** — 절대 예외를 밖으로 던져 로그인/
  /// 부트스트랩을 막지 않는다(서버는 deviceId가 없으면 기기 가드를 그냥
  /// 건너뛰도록 설계돼 있다, functions/src/index.ts `bootstrapAccount`).
  static Future<String?> _resolveDeviceId() async {
    try {
      if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        final id = info.identifierForVendor;
        return (id == null || id.isEmpty) ? null : id;
      }
      if (Platform.isAndroid) {
        final id = await const AndroidId().getId();
        return (id == null || id.isEmpty) ? null : id;
      }
      return null;
    } catch (e) {
      debugPrint('기기 식별자 조회 실패: ${e.runtimeType}');
      return null;
    }
  }
}
