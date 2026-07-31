import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/motion_strategy.dart';
import '../../../common/glass_card.dart';
import '../../radar/view_models/radar_view_model.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final radarViewModel = context.watch<RadarViewModel>();
    final settings = radarViewModel.settings;

    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.bgGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '설정',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                // Radar Notification Switch
                GlassCard(
                  child: Row(
                    mainAxisAlignment: MainStateBetween.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.radar, color: AppColors.accentSky, size: 22),
                          SizedBox(width: 10),
                          Text(
                            '주변 인맥 감지 알림',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Switch(
                        value: settings.enabled,
                        onChanged: (val) {},
                        activeColor: AppColors.accentSky,
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Radius Selector Card
                const Text(
                  '📍 감지 반경 설정',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),

                GlassCard(
                  child: Column(
                    children: [
                      RadioListTile<double>(
                        title: const Text('500m 이내 (가까운 인맥)'),
                        value: 500,
                        groupValue: settings.radiusMeters,
                        onChanged: (val) => radarViewModel.updateRadius(val!),
                        activeColor: AppColors.accentSky,
                      ),
                      RadioListTile<double>(
                        title: const Text('1km 이내 (권장)'),
                        value: 1000,
                        groupValue: settings.radiusMeters,
                        onChanged: (val) => radarViewModel.updateRadius(val!),
                        activeColor: AppColors.accentSky,
                      ),
                      RadioListTile<double>(
                        title: const Text('전체 반경 (제한 없음)'),
                        value: double.infinity,
                        groupValue: settings.radiusMeters,
                        onChanged: (val) => radarViewModel.updateRadius(val!),
                        activeColor: AppColors.accentSky,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Battery & Motion Optimization Options
                const Text(
                  '🔋 배터리 & 위치 감지 최적화',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),

                GlassCard(
                  child: Column(
                    children: BatteryMode.values.map((mode) {
                      return RadioListTile<BatteryMode>(
                        title: Text(
                          MotionStrategy.getModeLabel(mode),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        value: mode,
                        groupValue: settings.batteryMode,
                        onChanged: (val) => radarViewModel.updateBatteryMode(val!),
                        activeColor: AppColors.accentLime,
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // Data & Security Information
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: AppColors.accentLime, size: 18),
                          SizedBox(width: 8),
                          Text('데이터 및 권한 안내', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('📍 위치 서비스 (GPS): 내 주변 인맥과의 거리 측정에 사용됩니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      SizedBox(height: 4),
                      Text('🔒 데이터 보관: 모든 명함 정보는 기기 내부 및 암호화 DB에 안전하게 보관됩니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
