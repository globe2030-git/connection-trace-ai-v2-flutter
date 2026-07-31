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
          items: [
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons3d/radar.png', width: 24, height: 24),
              activeIcon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSky.withOpacity(0.2),
                ),
                child: Image.asset('assets/icons3d/radar.png', width: 26, height: 26),
              ),
              label: '레이더',
            ),
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons3d/wallet.png', width: 24, height: 24),
              activeIcon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSky.withOpacity(0.2),
                ),
                child: Image.asset('assets/icons3d/wallet.png', width: 26, height: 26),
              ),
              label: '명함 지갑',
            ),
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons3d/settings.png', width: 24, height: 24),
              activeIcon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSky.withOpacity(0.2),
                ),
                child: Image.asset('assets/icons3d/settings.png', width: 26, height: 26),
              ),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
