import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/motion_strategy.dart';
import '../../../../data/repositories/ai_credentials_repository.dart';
import '../../../common/glass_card.dart';
import '../../radar/view_models/radar_view_model.dart';
import 'ai_connection_modal_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final radarViewModel = context.watch<RadarViewModel>();
    final settings = radarViewModel.settings;
    final aiCredentials = context.watch<AiCredentialsRepository>();

    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgDarkSlate,
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.radar, color: AppColors.accentText, size: 22),
                          SizedBox(width: 10),
                          Text(
                            '주변 인맥 감지 알림',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      Switch(
                        value: settings.enabled,
                        onChanged: (_) => radarViewModel.toggleDetection(),
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
                      ),
                      RadioListTile<double>(
                        title: const Text('1km 이내 (권장)'),
                        value: 1000,
                        groupValue: settings.radiusMeters,
                        onChanged: (val) => radarViewModel.updateRadius(val!),
                      ),
                      RadioListTile<double>(
                        title: const Text('전체 반경 (제한 없음)'),
                        value: double.infinity,
                        groupValue: settings.radiusMeters,
                        onChanged: (val) => radarViewModel.updateRadius(val!),
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
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // AI Connection
                const Text(
                  '🤖 AI 연동',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const AiConnectionModalView(),
                    );
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.smart_toy_outlined, color: AppColors.accentText, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '30초 AI 대화 브리핑 연동',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              aiCredentials.activeProvider != null
                                  ? '${aiCredentials.activeProvider!.displayName} 연동됨'
                                  : '아직 연동되지 않음 — 연동해야 AI 브리핑을 받을 수 있어요',
                              style: TextStyle(
                                fontSize: 12,
                                color: aiCredentials.activeProvider != null ? AppColors.accentText : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
                    ],
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
                          Icon(Icons.shield_outlined, color: AppColors.accentText, size: 18),
                          SizedBox(width: 8),
                          Text('데이터 및 권한 안내', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text('📍 위치 서비스 (GPS): 내 주변 인맥과의 거리 측정에 사용됩니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      SizedBox(height: 4),
                      Text('🔒 데이터 보관: 모든 명함 정보는 서버로 전송되지 않고 이 기기의 로컬 저장소에만 보관됩니다.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
