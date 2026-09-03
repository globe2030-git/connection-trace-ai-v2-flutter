import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 로그인 뒤 동의 적용이 **`mounted` 뒤에 갇히지 않는지** 본다.
///
/// ## 무엇을 지키려는 검사인가
///
/// 2026-09-03 실기기에서 잡았다. 증상이 둘로 보였는데 뿌리는 하나였다.
///
/// ```
/// ① ⑨에서 광고 동의를 골랐는데 로그인 뒤 옛 광고 동의 화면이 또 떴다
/// ② termsConsentAt 이 계정 18개 중 0개였다 — P1-17 이 사실상 죽어 있었다
/// ```
///
/// 원인: `_applyPendingConsent` 호출부가 `if (mounted)` 안에 있었다. 로그인이
/// 성공하면 `AuthGate` 가 위젯 트리를 통째로 갈아 끼우므로 **그 지점에서
/// `mounted` 는 이미 false** 다. 블록이 통째로 안 돌아 **광고 동의도 필수
/// 동의도 서버에 안 남았다.**
///
/// 🚨 **그 함수 자신의 주석이 정확히 그것을 경고하고 있었다** —
/// *"이 함수 안에서 `context` 나 `mounted` 를 확인하면 호출 자체가 취소될 수
/// 있다."* 함수 **안**은 지켰는데 **부르는 자리**가 어겼다.
///
/// ## 왜 위젯 테스트가 아니라 소스를 보나
///
/// ⚠️ **이 층은 위젯 테스트로 안 보인다.** 트리를 갈아 끼우는 것은 `AuthGate`
/// 이고, 로그인 화면만 띄운 테스트에서는 그 일이 **일어나지 않는다.** 그래서
/// `mounted` 가 계속 true 라 통과해 버린다 — 실기기에서만 드러나는 자리다.
///
/// 📌 **소스를 보는 검사는 「통과만 하는 테스트」가 되기 쉽다.** 그래서 이
/// 파일을 만들 때 **옛 코드(고치기 전)에 대고 돌려 실제로 깨지는지 먼저
/// 확인했다.** 안 깨지면 이 검사는 아무것도 안 지킨다.
void main() {
  final source = File(
    'lib/presentation/features/auth/views/login_view.dart',
  ).readAsStringSync();
  final lines = source.split('\n');

  /// `_applyPendingConsent(` 를 실제로 **부르는** 줄 번호들.
  /// 선언부(`Future<void> _applyPendingConsent`)와 주석은 뺀다.
  List<int> callSites() => [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].contains('_applyPendingConsent(') &&
          !lines[i].contains('Future<void>') &&
          !lines[i].trimLeft().startsWith('///') &&
          !lines[i].trimLeft().startsWith('//'))
        i,
  ];

  test('🚨 동의 적용 호출부가 둘 다 남아 있다', () {
    // 소셜 경로와 이메일 경로. 하나가 사라지면 그 경로의 동의가 안 남는다.
    expect(
      callSites().length,
      2,
      reason: '호출부가 2곳이어야 한다(소셜·이메일). 실제: ${callSites()}',
    );
  });

  test('🚨 호출부가 `if (mounted)` 블록 안에 있으면 안 된다', () {
    for (final i in callSites()) {
      // 호출 줄과 그 앞 3줄을 본다 — 가드는 바로 위에 붙는다.
      final window = lines
          .sublist((i - 3).clamp(0, lines.length), i + 1)
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        window.contains('if (mounted)'),
        isFalse,
        reason:
            '${i + 1}행 호출부가 `if (mounted)` 안에 있다. 로그인 직후에는 '
            'AuthGate 가 트리를 갈아 끼워 mounted 가 false 라 호출이 통째로 '
            '사라진다 — 광고 동의와 필수 동의가 서버에 안 남는다.\n$window',
      );
      expect(
        window.contains('!mounted'),
        isFalse,
        reason:
            '${i + 1}행 호출부 앞에 `!mounted` 로 빠져나가는 줄이 있다. '
            '위와 같은 이유로 동의가 안 남는다.\n$window',
      );
    }
  });

  test('🚨 호출부가 `context` 를 다시 읽으면 안 된다', () {
    // context.read 는 위젯이 트리에서 빠지면 던진다. 로그인 성공 직후가
    // 정확히 그 순간이라, uid 는 **미리 잡아 둔** AuthRepository 에서 읽어야 한다.
    for (final i in callSites()) {
      final window = lines
          .sublist((i - 3).clamp(0, lines.length), i + 1)
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        window.contains('context.read'),
        isFalse,
        reason:
            '${i + 1}행 호출부가 context 를 다시 읽는다. 함수 위에서 미리 잡아 둔 '
            '`auth` 를 쓸 것.\n$window',
      );
    }
  });
}
