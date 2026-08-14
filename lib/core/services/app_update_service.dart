import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 업데이트 안내 수준.
enum AppUpdateLevel {
  /// 최신이거나(또는 확인 실패로) 안내할 필요 없음.
  none,

  /// 새 버전이 있어 **권장**하지만 계속 써도 된다("나중에" 허용).
  recommended,

  /// 최소 지원 버전 미만이라 **강제** — 업데이트 전까지 못 쓴다.
  forced,
}

/// 버전 게이트 판정 결과.
class AppUpdateStatus {
  final AppUpdateLevel level;
  final String? storeUrl;
  final String? message;

  const AppUpdateStatus(this.level, {this.storeUrl, this.message});

  static const AppUpdateStatus none = AppUpdateStatus(AppUpdateLevel.none);
}

/// 앱 시작 시 "지금 깔린 빌드가 너무 낡았는지"를 서버 설정과 비교해 알린다
/// (P1-45, backlog 추가 161).
///
/// ### 왜 필요한가
/// 스토어(App Store/Play) 배포는 **특정 앱의 새 버전이 나왔다고 사용자에게
/// 알려 주지 않는다.** 자동 업데이트를 꺼 둔 사용자는 낡은 앱을 계속 쓰고,
/// 서버(예: AI 프록시, 결제 상품 구조)가 바뀌면 구버전이 깨질 수 있다. iOS는
/// 공식 강제 업데이트 API가 없어, 앱이 직접 버전을 확인해 안내하는 이 방식이
/// 표준이다.
///
/// ### 설계
/// - 기준은 **빌드 번호**(pubspec `1.0.0+N`의 N). 버전 문자열보다 비교가 쉽다.
/// - 서버 값은 Firestore `config/appUpdate`에 두고 **관리자 콘솔에서 편집**한다
///   (충전 상품 설정과 같은 config 패턴 — 배포 없이 제어).
/// - **최소/최신 빌드는 플랫폼별로 나뉜다**(`minSupportedBuildIos`/
///   `minSupportedBuildAndroid`, `latestBuildIos`/`latestBuildAndroid`,
///   추가 165 후속). iOS·Android는 스토어 심사 통과 시점이 달라 실제 배포된
///   최신 빌드번호가 어긋날 수 있다 — 단일 값이면 뒤처진 쪽 스토어 사용자가
///   헛되게 "업데이트 있음"을 보거나, 최소(강제)에 걸려 갈 곳이 없어 앱이
///   막히는(soft-brick) 위험이 있었다. 플랫폼 필드가 없으면(구 설정)
///   레거시 단일 필드(`minSupportedBuild`/`latestBuild`)로 **폴백**한다.
/// - **오프라인·설정 없음·오류는 모두 "안내 안 함"(none)으로 fail-open** 한다.
///   네트워크가 없다고 앱을 잠그면 안 된다.
class AppUpdateService {
  static const String _docPath = 'config/appUpdate';

  /// 테스트에서 갈아끼울 수 있게 열어 둔다.
  final Future<int> Function() _currentBuild;
  final Future<Map<String, dynamic>?> Function() _fetchConfig;
  final bool Function() _isIos;

  AppUpdateService({
    Future<int> Function()? currentBuild,
    Future<Map<String, dynamic>?> Function()? fetchConfig,
    bool Function()? isIos,
  }) : _currentBuild = currentBuild ?? _readCurrentBuild,
       _fetchConfig = fetchConfig ?? _readConfig,
       _isIos = isIos ?? (() => Platform.isIOS);

  Future<AppUpdateStatus> check() async {
    // 웹은 스토어 업데이트 개념이 없어 대상이 아니다.
    if (kIsWeb) return AppUpdateStatus.none;
    try {
      final current = await _currentBuild();
      if (current <= 0) return AppUpdateStatus.none;
      final cfg = await _fetchConfig();
      if (cfg == null) return AppUpdateStatus.none;

      final isIos = _isIos();
      final minBuild = _platformBuild(cfg, isIos, 'minSupportedBuild');
      final latestBuild = _platformBuild(cfg, isIos, 'latestBuild');
      final message = (cfg['message'] as String?)?.trim();
      final storeUrl = _storeUrlFor(cfg, isIos);

      if (current < minBuild) {
        return AppUpdateStatus(
          AppUpdateLevel.forced,
          storeUrl: storeUrl,
          message: message,
        );
      }
      if (current < latestBuild) {
        return AppUpdateStatus(
          AppUpdateLevel.recommended,
          storeUrl: storeUrl,
          message: message,
        );
      }
      return AppUpdateStatus.none;
    } catch (e) {
      // fail-open — 확인 실패로 앱을 막지 않는다.
      debugPrint('앱 업데이트 확인 실패(무시): $e');
      return AppUpdateStatus.none;
    }
  }

  /// 플랫폼별 필드(`<key>Ios`/`<key>Android`)를 우선 읽고, 없으면(null)
  /// 레거시 단일 필드(`<key>`)로 폴백한다 — 기존 설정만 있는 config도
  /// 그대로 동작하게 하기 위함.
  static int _platformBuild(
    Map<String, dynamic> cfg,
    bool isIos,
    String key,
  ) {
    final platformKey = isIos ? '${key}Ios' : '${key}Android';
    final platformValue = (cfg[platformKey] as num?)?.toInt();
    if (platformValue != null) return platformValue;
    return (cfg[key] as num?)?.toInt() ?? 0;
  }

  /// 서버(`config/appUpdate`)가 이미 Rules의 `isValidAppUpdateConfig`로
  /// 공식 스토어 host만 저장하도록 강제되지만(ADMIN-VULN-003), 클라이언트도
  /// 방어적으로 한 번 더 검증한다 — Rules가 어떤 이유로든 비어 있거나 낡은
  /// 배포가 남아 있어도, 강제/권장 업데이트 버튼이 임의 URL(피싱 사이트,
  /// 커스텀 스킴 등)을 열지 않게 하기 위함이다. 검증에 실패하면 안내 화면
  /// 자체는 그대로 뜨되(닫기 불가 상태는 유지) 버튼이 아무것도 열지 않는
  /// "안전한 실패"로 처리한다.
  static String? _storeUrlFor(Map<String, dynamic> cfg, bool isIos) {
    final ios = (cfg['iosUrl'] as String?)?.trim();
    final android = (cfg['androidUrl'] as String?)?.trim();
    final url = isIos ? ios : android;
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      final expectedHost = isIos ? 'apps.apple.com' : 'play.google.com';
      if (uri.scheme == 'https' && uri.host == expectedHost) {
        return url;
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<int> _readCurrentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  static Future<Map<String, dynamic>?> _readConfig() async {
    final snap = await FirebaseFirestore.instance.doc(_docPath).get();
    return snap.exists ? snap.data() : null;
  }
}
