// `IndexedStack` 아래 `const` 자식 위젯은 부모가 다시 그려져도 build()가
// 다시 불리지 않는다는 것을 잠그는 테스트(추가 513).
//
// ## 왜 이 테스트가 필요한가
//
// 설정 화면의 "명함 사진 백업" 숫자가 앱을 새로 시작해야만 갱신되던 결함의
// 진짜 원인이 이것이었다 — `main_tab_screen.dart`의 `_screens`가
// `const [RadarView(), WalletView(), SettingsView()]`처럼 **전부 const**로
// 돼 있었다. `IndexedStack`은 숨겨진 탭도 매 리빌드마다 그리지만, `const`
// 위젯은 Dart가 같은 인스턴스로 정규화(canonicalize)하기 때문에 부모가
// 새 `List`를 매번 만들어도 그 안의 `const SettingsView()`는 이전과
// `identical()`하다 — Flutter의 `Element.updateChild`는 이 경우 자식을 다시
// 그리지 않고 그대로 넘어간다. 그래서 `SettingsView.build()`는 앱 시작
// 직후 딱 한 번만 실행되고, 탭을 나갔다 들어와도 다시 실행되지 않았다.
//
// ⚠️ `SettingsView`는 첫 줄이 `FirebaseAuth.instance`라 `flutter test`에서
// 실물로 못 띄운다(`main_tab_screen_back_button_test.dart`의 기존 주석과
// 같은 제약). 그래서 여기서는 **같은 구조를 재현하는 최소 위젯**으로
// 메커니즘 자체를 잠근다 — 실제 수정은
// `lib/presentation/navigation/main_tab_screen.dart`의 `_screens` getter
// (SettingsView만 const를 뺌)와
// `lib/presentation/features/settings/views/settings_view.dart`의
// `_CardPhotoBackupStatusRowState.didUpdateWidget`(다시 읽기)에 있다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 빌드될 때마다 카운터를 올리는 위젯 — "이 위젯의 build()가 다시
/// 불렸는가"를 셀 수 있게 한다.
class _CountingChild extends StatefulWidget {
  const _CountingChild(this.onBuild);
  final VoidCallback onBuild;

  @override
  State<_CountingChild> createState() => _CountingChildState();
}

class _CountingChildState extends State<_CountingChild> {
  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets(
    '⭐ const 자식은 부모가 여러 번 리빌드돼도 build()가 다시 불리지 않는다(고치기 전 재현)',
    (tester) async {
      var buildCount = 0;
      // 예전 코드와 같은 모양: `const SettingsView()`에 해당하는 자리를
      // 매번 새로 만든 **완전히 같은 const 위젯**으로 재현한다.
      const staticChild = _StaticCountingChildWrapper();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  IndexedStack(index: 0, children: const [staticChild]),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('리빌드'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      buildCount = _staticBuildCount;
      expect(buildCount, 1, reason: '최초 1회는 그려진다');

      // 부모를 여러 번 리빌드한다(탭 전환·다른 상태 변화를 흉내).
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('리빌드'));
        await tester.pump();
      }

      expect(
        _staticBuildCount,
        1,
        reason: 'const 위젯은 identical()이라 Element가 다시 그리지 않는다 — '
            '이것이 설정 화면 백업 숫자가 안 바뀐 진짜 원인이었다',
      );
    },
  );

  testWidgets('⭐ const 를 뺀 자식은 부모가 리빌드될 때마다 build()가 다시 불린다(고친 뒤)', (
    tester,
  ) async {
    var buildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                // ⚠️ 여기가 실제 수정과 같은 자리다 — `const`를 빼면 매
                // build()마다 새 인스턴스가 만들어져 Element가 갱신된다.
                IndexedStack(
                  index: 0,
                  children: [_CountingChild(() => buildCount++)],
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('리빌드'),
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(buildCount, 1);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('리빌드'));
      await tester.pump();
    }

    expect(
      buildCount,
      greaterThan(1),
      reason: 'const를 빼면 매 리빌드마다 다시 그려져 최신 값을 읽을 기회가 생긴다',
    );
  });
}

/// 위 첫 테스트에서 `const` 정규화를 재현하기 위한 최상위 const 위젯.
/// (로컬 함수/클로저는 const 인스턴스에 담을 수 없어 톱레벨 카운터를 쓴다.)
int _staticBuildCount = 0;

class _StaticCountingChildWrapper extends StatelessWidget {
  const _StaticCountingChildWrapper();

  @override
  Widget build(BuildContext context) {
    _staticBuildCount++;
    return const SizedBox.shrink();
  }
}
