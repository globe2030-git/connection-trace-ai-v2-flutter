import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../features/radar/views/radar_view.dart';
import '../features/wallet/views/wallet_view.dart';
import '../features/settings/views/settings_view.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    RadarView(),
    WalletView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDarkObsidian,
          border: Border(top: BorderSide(color: AppColors.borderDark, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.textPrimary,
          unselectedItemColor: AppColors.textMuted,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.radar_outlined, size: 24),
              activeIcon: Icon(Icons.radar, size: 26, color: AppColors.accentText),
              label: '레이더',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.credit_card_outlined, size: 24),
              activeIcon: Icon(Icons.credit_card, size: 26, color: AppColors.accentText),
              label: '명함 지갑',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, size: 24),
              activeIcon: Icon(Icons.settings, size: 26, color: AppColors.accentText),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
