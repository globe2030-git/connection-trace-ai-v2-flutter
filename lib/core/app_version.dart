import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 실행 중인 앱이 **어떤 빌드인지** 알려준다.
///
/// **왜 필요한가**(backlog 추가 77, P1-30): 아이폰에서 이미 고친 문제가 그대로
/// 보인다는 제보를 받고 원인을 찾다가, 실제로는 기기에 낡은 빌드가 깔려
/// 있었다는 것으로 밝혀진 적이 있다. 화면만 봐서는 지금 보고 있는 앱이 어느
/// 시점의 코드인지 알 수 없어, 결함 제보와 QA 리포트 전체에 "낡은 빌드였을 수
/// 있다"는 의심이 붙는다.
///
/// 버전과 빌드번호는 `package_info_plus`가 **빌드된 산출물에서** 읽으므로
/// `pubspec.yaml`과 어긋날 수 없다. 예전에는 상수로 적어 두고 손으로
/// 맞췄는데, 릴리스마다 갱신을 잊으면 오히려 잘못된 정보를 보여준다.
///
/// 커밋 해시는 빌드할 때 주입한다:
/// ```
/// flutter build apk --release --dart-define=GIT_COMMIT=$(git rev-parse --short HEAD)
/// ```
/// `tool/build_app.sh`를 쓰면 자동으로 붙는다. 주입하지 않으면 해시 없이
/// 버전만 표시한다.
class AppVersion {
  AppVersion._();

  /// 빌드 시점에 주입된 커밋 해시(짧은 형태). 주입하지 않으면 빈 문자열.
  static const String commit = String.fromEnvironment('GIT_COMMIT');

  static String _version = '';
  static String _buildNumber = '';

  /// 앱 시작 시 한 번 호출한다. 실패해도 앱 실행을 막지 않는다 — 버전 표시는
  /// 없어도 되는 정보이지, 앱이 뜨지 못할 이유는 아니다.
  static Future<void> initialize() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (e) {
      debugPrint('앱 버전 정보를 읽지 못했습니다: $e');
    }
  }

  /// 설정 화면에 보여줄 문자열. 예: `1.0.0 (1) · a1b2c3d`
  ///
  /// 커밋 해시가 있으면 함께 보여준다 — 테스터가 이 값을 알려주면 정확히 어느
  /// 코드인지 특정할 수 있다.
  static String get display {
    if (_version.isEmpty) return commit.isEmpty ? '알 수 없음' : commit;
    final base = _buildNumber.isEmpty ? _version : '$_version ($_buildNumber)';
    return commit.isEmpty ? base : '$base · $commit';
  }

  /// 오픈소스 라이선스 화면 등 버전만 필요한 곳에서 쓴다.
  static String get versionOnly =>
      _buildNumber.isEmpty ? _version : '$_version ($_buildNumber)';
}
