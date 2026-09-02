import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **터치 영역 48dp 가 보장된다는 것을 고정한다**(2026-09-02 실측).
///
/// ## 왜 이 테스트가 생겼나 — 세어 보고 「고쳐야 한다」고 잘못 보고했다
///
/// `minimumSize: const Size(40, 40)` 같은 코드를 세어 **48dp 미만 터치 대상이
/// 15건**이라고 보고했다. **틀렸다.** 전부 이미 48dp 다.
///
/// ```
/// 보이는 크기   40×40   ← styleFrom 의 minimumSize/maximumSize 가 정하는 것
/// 터치 영역     48×48   ← Flutter 가 따로 보장한다
/// ```
///
/// 근거는 둘이다.
/// - `ThemeData` 가 모바일에서 `materialTapTargetSize` 를 `padded` 로 둔다.
/// - `padded` 면 `_InputPadding` 이 **시각 크기 밖으로 히트 영역을 넓힌다.**
///
/// 📌 **코드를 읽어서는 이 사실을 알 수 없다.** 그래서 세는 대신 **실제로
/// 눌러 봤다** — 시각 경계 밖(중심에서 20~22px)을 탭해도 반응한다.
///
/// ## 이 테스트가 하는 일
///
/// 허수였다는 것을 적어 두는 것만으로는 부족하다. **다음 사람이 또 센다.**
/// 그래서 보장 자체를 테스트로 고정한다 — 누가 `materialTapTargetSize` 를
/// 건드리거나 `tapTargetSize: shrinkWrap` 을 기본으로 깔면 **여기서 깨진다.**
///
/// ⚠️ **데스크톱은 다르다.** `ThemeData` 가 데스크톱에서는 `shrinkWrap` 을
/// 쓴다 — **의도된 차이**이고, 이 앱이 나가는 곳은 iOS·Android 다.
void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  /// 중심에서 [dx]만큼 떨어진 곳을 눌러 반응하는지 본다.
  Future<int> tapOffCenter(WidgetTester tester, double dx) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (_) => IconButton(
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              maximumSize: const Size(40, 40),
            ),
            onPressed: () => tapped++,
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.byType(IconButton)) + Offset(dx, 0));
    await tester.pump();
    return tapped;
  }

  group('터치 영역 48dp 보장', () {
    testWidgets('40×40 으로 보이는 아이콘 버튼도 48×48 을 차지한다', (tester) async {
      await tester.pumpWidget(
        wrap(
          IconButton(
            style: IconButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              maximumSize: const Size(40, 40),
            ),
            onPressed: () {},
            icon: const Icon(Icons.close),
          ),
        ),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    });

    testWidgets('시각 경계(20px) 밖을 눌러도 반응한다', (tester) async {
      expect(await tapOffCenter(tester, 22), 1);
    });

    testWidgets('48dp 경계(24px) 밖을 누르면 반응하지 않는다', (tester) async {
      // 위 테스트만 있으면 "무한히 넓다"와 구분되지 않는다. 경계가 실제로
      // 48dp 라는 것은 밖에서 안 눌리는 것으로만 확인된다.
      expect(await tapOffCenter(tester, 26), 0);
    });

    testWidgets('constraints 를 없애고 아이콘을 16px 로 줄여도 48×48 이다', (tester) async {
      // 인라인 안내의 닫기 버튼들이 이 모양이다(padding 0 · BoxConstraints()).
      // 보이는 것은 16px 아이콘뿐이라 세면 "작다"로 잡히지만, 실제로는 아니다.
      var tapped = 0;
      await tester.pumpWidget(
        wrap(
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => tapped++,
          ),
        ),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
      await tester.tapAt(
        tester.getCenter(find.byType(IconButton)) + const Offset(20, 0),
      );
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('보장의 출처 — 모바일 테마가 padded 다', (tester) async {
      // 위 셋이 깨졌을 때 "왜"를 바로 알 수 있게 출처를 따로 고정한다.
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          ThemeData(platform: platform).materialTapTargetSize,
          MaterialTapTargetSize.padded,
          reason: '$platform 에서 padded 가 아니면 위 보장이 사라진다',
        );
      }
    });
  });
}
