import 'package:connection_trace_ai_flutter/core/icons/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 에셋 파일명 실재 검증.
///
/// 2026-08-11 이미지 파일명을 도메인 접두사 체계(12자 이내)로 일괄 개명하면서
/// 만든 안전망. 파일명과 코드 참조는 컴파일 타임에 검증되지 않아서, 개명이나
/// 파일 추가/삭제에서 한 곳이라도 어긋나면 **앱을 띄워 그 화면을 열기 전까지
/// 아무도 모른다** — 아이콘은 39종이라 화면을 다 눌러 보는 것도 현실적이지
/// 않다. 여기서 번들 로드를 시도해 어긋난 참조를 커밋 전에 잡는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppIconId의 모든 SVG 에셋 파일이 실제로 존재한다', () async {
    for (final id in AppIconId.values) {
      try {
        await rootBundle.load(id.assetPath);
      } catch (_) {
        fail('${id.name}의 에셋을 찾지 못했습니다: ${id.assetPath}');
      }
    }
  });

  test('코드가 직접 참조하는 이미지 파일이 실제로 존재한다', () async {
    // 파일을 옮기거나 개명하면 이 목록도 함께 고칠 것 (참조처 주석 참고).
    const paths = [
      'assets/images/brand/ci.png', // login_view.dart
      'assets/images/brand/splash.png', // splash_gate.dart, radar_view.dart
      'assets/images/brand/icon.png', // pubspec flutter_launcher_icons
    ];
    for (final path in paths) {
      try {
        await rootBundle.load(path);
      } catch (_) {
        fail('이미지 에셋을 찾지 못했습니다: $path');
      }
    }
  });
}
