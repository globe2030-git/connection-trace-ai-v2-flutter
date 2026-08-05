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
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
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
