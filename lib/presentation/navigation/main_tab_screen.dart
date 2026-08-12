import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/icons/app_icons.dart';
import '../features/radar/view_models/radar_view_model.dart';
import '../features/radar/views/radar_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/wallet/views/wallet_view.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

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

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    RadarView(),
    WalletView(),
    SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MainTabScreen.tabRequest.addListener(_handleTabRequest);
  }

  @override
  void dispose() {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<RadarViewModel>().refreshLocationAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // '주변' 탭을 누르면 그 위에 떠 있던 AI 대화 가이드 오버레이를 닫아
          // 첫 화면으로 돌아온다. IndexedStack이라 이미 주변에 있는 상태에서
          // 탭을 다시 눌러도 _currentIndex가 그대로여서 오버레이가 남아 있던
          // 문제를 고친다(사용자 제보: 주변 → AI 가이드 → 주변이 안 돌아옴).
          if (index == 0) {
            context.read<RadarViewModel>().closeBriefing();
          }
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: AppIcon(AppIconId.nearbyPeople),
            selectedIcon: AppIcon(AppIconId.nearbyPeople),
            label: '주변',
          ),
          NavigationDestination(
            icon: AppIcon(AppIconId.cardWallet),
            selectedIcon: AppIcon(AppIconId.cardWallet),
            label: '명함',
          ),
          NavigationDestination(
            icon: AppIcon(AppIconId.settings),
            selectedIcon: AppIcon(AppIconId.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
