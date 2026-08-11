import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/icons/app_icons.dart';
import '../features/radar/view_models/radar_view_model.dart';
import '../features/radar/views/radar_view.dart';
import '../features/settings/views/settings_view.dart';
import '../features/wallet/views/wallet_view.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
