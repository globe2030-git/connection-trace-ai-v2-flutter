import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../features/radar/view_models/radar_view_model.dart';
import '../features/radar/views/radar_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/wallet/views/add_card_modal_view.dart';
import '../features/wallet/views/wallet_view.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key, this.debugScreens, this.debugExitApp});

  /// 탭 순서. 다른 화면에서 탭을 지정할 때 숫자를 직접 쓰지 않게 이름을 둔다.
  static const int nearbyTabIndex = 0;
  static const int walletTabIndex = 1;
  static const int settingsTabIndex = 2;

  /// 다른 화면에서 탭을 바꿔 달라고 요청하는 통로.
  ///
  /// 탭은 이 화면의 State가 들고 있어서 하위 화면이 직접 바꿀 수 없다. 주변
  /// 화면에서 "명함 지갑에서 전체 검색"으로 보내 주려면 통로가 필요해 둔다
  /// (E-07 후속). 값을 넣으면 아래 리스너가 반영하고 곧바로 비운다 — 남겨 두면
  /// 다음에 이 화면이 다시 만들어질 때 의도치 않게 탭이 튄다.
  static final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);

  /// [tabRequest]에 요청을 넣는다. 호출부가 notifier를 직접 만지지 않게 감싼다.
  static void openTab(int index) => tabRequest.value = index;

  // ⚠️ 명함 등록 진입점의 자리는 2026-08-28 하루에 세 번 바뀌었다 — 지금
  // 이 아래 `NavigationBar`(4번째 목적지 "등록")가 최종 형태다. 이전
  // 시도(FAB, `centerDocked`→`endFloat`)와 그 사이 있었던 `hideFab`
  // 신호는 여기서 완전히 걷어냈다 — 탭 목적지로 가면서 더는 필요 없다
  // (아래 build() 주석에 이유를 적어 둔다). 되돌릴 자리는
  // PR #632(오른쪽 아래 FAB, 미병합)에 남아 있다.

  /// 테스트 전용: 실제 화면(주변/명함/설정) 대신 가벼운 대역 화면을 주입한다.
  ///
  /// 설정 화면은 첫 줄이 `FirebaseAuth.instance`라 `flutter test`에서
  /// Firebase 초기화 없이는 렌더링할 수 없다(추가 437 전에도 있던 제약,
  /// `auth_repository_social_session_test.dart` 참고). 뒤로가기 로직(탭
  /// 전환·두 번 눌러 종료)은 어떤 화면이 그 자리에 있는지와 무관하므로,
  /// 실물 화면 대신 대역을 넣어 그 로직만 잠근다.
  @visibleForTesting
  final List<Widget>? debugScreens;

  /// 테스트 전용: 실제 종료(`SystemNavigator.pop`) 대신 주입할 수 있는 훅.
  @visibleForTesting
  final Future<void> Function()? debugExitApp;

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  /// 첫 탭(주변)에서 뒤로가기를 한 번 눌렀다는 표시. 2초 안에 한 번 더
  /// 누르면 종료하고, 아니면 [_exitArmTimer]가 스스로 꺼서 다음 뒤로가기는
  /// 다시 안내부터 보여준다(추가 437 — "한 번 더 누르면 종료" 패턴).
  bool _exitArmed = false;
  Timer? _exitArmTimer;

  // ⚠️ `SettingsView()`는 일부러 `const`로 두지 않는다(추가 513).
  //
  // `IndexedStack`은 화면을 전부 계속 그리므로(숨겨진 탭도 매 리빌드마다
  // build()를 다시 부른다), 탭을 바꿔도 State가 안 사라지는 것 자체는
  // 문제가 아니다. 문제는 **`const` 위젯은 Dart가 같은 인스턴스로
  // 정규화(canonicalize)해서**, 매번 같은 `List`를 새로 만들어도 안의
  // `const SettingsView()`는 `identical()`이 참이 되고, Flutter는 이
  // 경우 `Element.updateChild`에서 자식을 다시 그리지 않고 그대로
  // 넘어간다는 것이다 — 결과적으로 **`SettingsView.build()`가 앱을 새로
  // 시작한 뒤 딱 한 번만 실행되고, 그 뒤로는 탭을 눌러도 다시 실행되지
  // 않는다.** 그 안의 `_CardPhotoBackupStatusRow`(사진 백업 현황)가
  // `initState()`에서 한 번만 읽고 절대 안 바뀌던 원인이 이것이다 —
  // 명함을 등록해 서버에 사진이 올라가도, 이미 그려진 그 화면은 다시
  // 그려질 기회 자체가 없었다.
  //
  // `SettingsView()`만 `const`를 빼면 매 리빌드(탭 전환 포함)마다 새
  // 위젯 인스턴스가 만들어져 `didUpdateWidget`이 불리고, 그 안의
  // `_CardPhotoBackupStatusRowState.didUpdateWidget`이 최신 값을 다시
  // 읽는다(State 자체는 그대로 유지되므로 `initState`가 다시 불리는 건
  // 아니다). Radar·Wallet은 이 결함이 보고되지 않아 그대로 `const`로 둔다
  // — 바꾸는 범위를 좁혀 다른 화면에 영향이 번지지 않게 한다.
  List<Widget> get _screens =>
      widget.debugScreens ??
      [const RadarView(), const WalletView(), SettingsView()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MainTabScreen.tabRequest.addListener(_handleTabRequest);
  }

  @override
  void dispose() {
    _exitArmTimer?.cancel();
    MainTabScreen.tabRequest.removeListener(_handleTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleTabRequest() {
    final requested = MainTabScreen.tabRequest.value;
    if (requested == null || !mounted) return;
    setState(() => _currentIndex = requested);
    // 요청을 소비한다. 비우면 이 리스너가 한 번 더 불리지만 위에서 null로 걸러진다.
    MainTabScreen.tabRequest.value = null;
  }

  // "등록"이 끼어드는 자리(0=주변, 1=명함, 2=등록, 3=설정) — 실제 화면이
  // 아니라 모달을 여는 동작이라 [_screens]/[IndexedStack]에는 대응하는
  // 화면이 없다.
  static const int _addDestinationIndex = 2;

  /// 실제 화면 인덱스(0=주변, 1=명함, 2=설정) → `NavigationBar` 목적지
  /// 인덱스. "등록"이 설정 바로 앞에 끼어들어서 설정만 한 칸 밀린다.
  int _destinationIndexForScreen(int screenIndex) =>
      screenIndex >= _addDestinationIndex ? screenIndex + 1 : screenIndex;

  /// `NavigationBar`가 목적지를 고를 때마다 불린다. "등록" 자리를 고르면
  /// **탭 선택 상태를 바꾸지 않고** 모달만 연다 — 눌러도 원래 있던 탭
  /// (주변이든 명함이든)에 그대로 남아야 한다(globe2030님 지시,
  /// 2026-08-28). `selectedIndex`에 [_addDestinationIndex]가 들어갈 일이
  /// 없어서(아래에서 setState를 안 한다) `NavigationBar`도 그 자리를
  /// "선택됨"으로 그리지 않는다 — 별도 처리 없이 저절로 지켜진다.
  void _handleDestinationSelected(int destinationIndex) {
    if (destinationIndex == _addDestinationIndex) {
      AddCardModalView.show(context);
      return;
    }
    final screenIndex = destinationIndex > _addDestinationIndex
        ? destinationIndex - 1
        : destinationIndex;
    // '주변' 탭을 누르면 그 위에 떠 있던 AI 대화 가이드 오버레이를 닫아
    // 첫 화면으로 돌아온다. IndexedStack이라 이미 주변에 있는 상태에서
    // 탭을 다시 눌러도 _currentIndex가 그대로여서 오버레이가 남아 있던
    // 문제를 고친다(사용자 제보: 주변 → AI 가이드 → 주변이 안 돌아옴).
    if (screenIndex == MainTabScreen.nearbyTabIndex) {
      context.read<RadarViewModel>().closeBriefing();
    }
    setState(() => _currentIndex = screenIndex);
  }

  /// "등록" 목적지의 아이콘 — 나머지 셋(주변·명함·설정)과 다르게 보이도록
  /// 강조색 원형 배지로 그린다. 이 목적지는 [_handleDestinationSelected]가
  /// 절대 "선택됨"으로 만들지 않으므로, 다른 셋처럼 선택 시에만 색이
  /// 진해지는 방식으로는 평생 흐린 색으로 남는다 — 그러면 "동작"이 아니라
  /// "죽은 탭"처럼 보인다. 그래서 선택 여부와 무관하게 항상 강조색을
  /// 준다. 크기는 28px(다른 아이콘 24px보다 살짝 큼)로 시선을 끌되,
  /// FAB만큼 튀지 않게 억제했다 — 인스타그램·유튜브의 가운데 강조 탭
  /// 정도가 기준(globe2030님 재확인 지시, 2026-08-28).
  Widget _buildAddDestinationIcon() {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: AppIcon(AppIconId.addCard, color: Colors.white, size: 16),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<RadarViewModel>().refreshLocationAccess();
    }
  }

  /// 뒤로가기(안드로이드 네비게이션 바·제스처) 처리(추가 437).
  ///
  /// 테스터 제보: 뒤로가기를 누르면 다른 앱처럼 종료되는 대신 화면만 닫혀
  /// 최근 앱 목록에 프로세스가 그대로 살아 있었다. 원인은 이 루트 셸에
  /// `PopScope`/`SystemNavigator.pop` 호출이 전혀 없어 Flutter 기본 동작
  /// (Android가 알아서 처리 — 프로세스는 안 끝난다)에 맡겨져 있었던 것.
  ///
  /// 순서:
  /// 1) AI 대화 브리핑 오버레이가 열려 있으면 아무것도 하지 않는다 — 그
  ///    오버레이는 주변 화면 안에 `Stack`으로 떠 있을 뿐 별도 Route가 아니라
  ///    이 화면과 같은 Route에 얹혀 있고, 오버레이 쪽에도 `PopScope`가 있어
  ///    같은 뒤로가기 한 번에 양쪽이 동시에 반응한다. 여기서도 처리하면
  ///    오버레이를 닫으면서 동시에 탭 전환/종료 안내까지 겹쳐 뜬다. 이
  ///    화면은 오버레이의 State를 직접 모르므로(주변 화면이 따로 그린다)
  ///    `RadarViewModel.selectedContactForBriefing`으로 열림 여부를 판단한다.
  /// 2) 첫 탭(주변)이 아니면 첫 탭으로 돌아간다 — 안드로이드 관례. 탭을
  ///    옮긴 채로 뒤로가기가 바로 종료되면 오히려 놀란다.
  /// 3) 첫 탭에서: 2초 안에 두 번 누르면 종료, 아니면 안내만 띄운다 —
  ///    오조작으로 앱이 바로 닫히는 것을 막는 통용 패턴.
  Future<void> _handleBackPressed() async {
    final radarViewModel = context.read<RadarViewModel>();
    if (radarViewModel.selectedContactForBriefing != null) {
      // 오버레이 쪽 PopScope가 이미 닫는다.
      return;
    }

    if (_currentIndex != MainTabScreen.nearbyTabIndex) {
      setState(() => _currentIndex = MainTabScreen.nearbyTabIndex);
      return;
    }

    if (_exitArmed) {
      _exitArmTimer?.cancel();
      _exitArmed = false;
      final exitApp = widget.debugExitApp ?? SystemNavigator.pop;
      await exitApp();
      return;
    }

    _exitArmed = true;
    _exitArmTimer?.cancel();
    _exitArmTimer = Timer(const Duration(seconds: 2), () {
      _exitArmed = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('한 번 더 누르면 종료됩니다.'),
        backgroundColor: AppColors.accent,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 항상 false로 두고 SystemNavigator.pop을 직접 불러 종료한다 —
      // Navigator에 맡기면(루트뿐인 단일 Route) 기본은 "그냥 화면만
      // 내려가고 프로세스는 남는" Android 기본 동작이라 이 결함의 원인이다.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPressed();
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _screens),
        // 명함 등록 진입점을 "주변"·"명함" 두 화면의 머리글(화면 오른쪽 위)
        // 대신 하단 탭 바로 옮긴다(globe2030님 결정, 2026-08-28). 원인은
        // 한 손(엄지) 조작 — 화면 오른쪽 위는 큰 화면(폴드 등)에서 엄지가
        // 닿기 어렵고, 하단은 항상 닿는다. 설계 문서:
        // docs/planning/specs/card-add-button-placement-2026-08-28.md.
        //
        // ⚠️ **이 형태(4번째 탭)가 나오기까지 같은 날 세 번 바뀌었다 —
        // 다음에 이 화면을 다시 만질 사람을 위해 순서를 남긴다.**
        // 1) 처음엔 `NavigationBar`의 세 목적지에 끼워 넣지 않고
        //    `FloatingActionButton`(`centerDocked`, 하단 바 가운데 도킹)을
        //    띄웠다 — "저 셋은 눌러서 머무는 곳(선택 상태가 남는다)인데
        //    명함 등록은 동작이라 성격이 다르다"는 판단이었다.
        // 2) 실기기(폴드, 빌드 04db06a)에서 결함이 났다 — **이 탭 바는
        //    목적지가 3개라 가운데 자리에 이미 "명함" 탭이 있었다.**
        //    `centerDocked`는 가운데가 비는 짝수(2·4) 탭에 쓰는 위치인데
        //    탭 개수를 안 세고 골라서, "명함" 탭 아이콘이 FAB에 완전히
        //    가려졌다. `endFloat`(오른쪽 아래)로 옮겨 대응했다(PR #632,
        //    미병합으로 보존 — 되돌릴 자리로 남겨 뒀다).
        // 3) globe2030님께 다시 여쭤보니 **원래 뜻이 "설정 탭 옆"을
        //    문자 그대로 말씀하신 것**이었다 — ⓐ(오른쪽 아래)는 그
        //    표현과의 거리를 이쪽이 판단해서 고른 것이었는데, 실제 뜻은
        //    ⓒ(탭 자체를 4개로)였다. 그래서 지금 이 형태로 다시 왔다.
        //
        // **교훈**: `FloatingActionButtonLocation.centerDocked`는 "가운데에
        // 예쁘게 뜬다"가 아니라 "가운데 자리를 실제로 차지한다"는 뜻이다
        // — 다음에 이 위젯을 쓸 때는 먼저 탭(또는 그 자리에 이미 있는 것)
        // 개수부터 센다. 그리고 사용자의 위치 표현("설정 옆")은 이쪽이
        // 판단으로 대신 읽지 말고, 여러 후보가 있으면 실물을 보여주고
        // 정하는 편이 빠르다 — 이번에도 논리가 아니라 화면으로 정했다.
        //
        // "등록" 목적지는 [_addDestinationIndex] 자리에 있고, 고르면
        // [_handleDestinationSelected]가 화면을 바꾸지 않고 모달만 연다.
        bottomNavigationBar: NavigationBar(
          selectedIndex: _destinationIndexForScreen(_currentIndex),
          onDestinationSelected: _handleDestinationSelected,
          destinations: [
            const NavigationDestination(
              icon: AppIcon(AppIconId.nearbyPeople),
              selectedIcon: AppIcon(AppIconId.nearbyPeople),
              label: '주변',
            ),
            const NavigationDestination(
              icon: AppIcon(AppIconId.cardWallet),
              selectedIcon: AppIcon(AppIconId.cardWallet),
              label: '명함',
            ),
            // 라벨은 "등록"으로 뒀다("추가"도 후보였다) — 이 동작을 이미
            // 앱 전체가 "명함 등록"이라 불러왔다(모달 제목·툴팁·저장
            // 완료 스낵바가 전부 이 말을 쓴다). 탭 라벨만 "추가"로 부르면
            // 같은 동작에 두 말이 붙어 오히려 헷갈린다. 폭이 좁아 2글자로만
            // 썼다 — 탭 4개일 때 하나당 폭은 폴드 접힌 화면 기준 실측
            // 411.4dp ÷ 4 = 102.8dp(`adb shell dumpsys display` 실측,
            // 2026-08-28)뿐이라 "명함 등록"(4글자)은 줄바꿈·잘림 위험이
            // 있다.
            NavigationDestination(
              icon: _buildAddDestinationIcon(),
              label: '등록',
              tooltip: '명함 등록',
            ),
            const NavigationDestination(
              icon: AppIcon(AppIconId.settings),
              selectedIcon: AppIcon(AppIconId.settings),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
