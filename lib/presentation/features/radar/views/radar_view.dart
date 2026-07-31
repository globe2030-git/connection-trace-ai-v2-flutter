import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/motion_strategy.dart';
import '../../../common/glass_card.dart';
import '../../../common/action_circle_button.dart';
import '../view_models/radar_view_model.dart';
import '../../briefing/views/briefing_overlay_view.dart';

class RadarView extends StatelessWidget {
  const RadarView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RadarViewModel>();
    final nearby = viewModel.nearbyAlertContact;
    final nearbyDistance = nearby != null
        ? GeoUtils.getDistanceMeters(viewModel.currentPosition, nearby.geo)
        : null;

    return Stack(
      children: [
        Scaffold(
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
                    // Top App Title & Sub Actions
                    Row(
                      mainAxisAlignment: MainStateBetween.spaceBetween,
                      children: [
                        const Text(
                          'Connection Trace',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: AppColors.textPrimary, size: 22),
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(Icons.notifications_none, color: AppColors.textPrimary, size: 22),
                              onPressed: () {},
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_outline, color: AppColors.textPrimary, size: 22),
                              onPressed: () {},
                            ),
                          ],
                        )
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Big Hero Proximity Metric (Matching reference design sample!)
                    Center(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                nearbyDistance != null ? (nearbyDistance < 1000 ? '${nearbyDistance.round()}' : (nearbyDistance / 1000).toStringAsFixed(1)) : '140',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                nearbyDistance != null ? (nearbyDistance < 1000 ? 'm' : 'km') : 'm',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 120,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.accentLime,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            nearby != null
                                ? '${nearby.name} ${nearby.title} (${nearby.company})'
                                : '김민준 이사 · 테크노바 근접중',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Hero Radar Interactive Avatar Container
                    Center(
                      child: Container(
                        width: 220,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentSky.withOpacity(0.15),
                              blurRadius: 20,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.radar, size: 120, color: AppColors.accentSky.withOpacity(0.3)),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: AppColors.accentSky,
                                  child: const Icon(Icons.person, color: Colors.white, size: 30),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentSky,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'ME',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Quick Action Control Buttons (Matching reference sample: 켜기, 브리핑, 명함, 설정)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ActionCircleButton(
                          icon: Icons.radar,
                          label: '감지 켜기',
                          isActive: viewModel.settings.enabled,
                          onTap: () {},
                        ),
                        ActionCircleButton(
                          icon: Icons.description_outlined,
                          label: 'AI 브리핑',
                          isActive: true,
                          onTap: () {
                            if (nearby != null) {
                              viewModel.openBriefing(nearby);
                            }
                          },
                        ),
                        ActionCircleButton(
                          icon: Icons.credit_card,
                          label: '명함 지갑',
                          onTap: () {},
                        ),
                        ActionCircleButton(
                          icon: Icons.warning_amber_rounded,
                          label: '우선 알림',
                          onTap: () {},
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Rounded Capsule Search Bar (Matching reference sample: High contrast white search capsule)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.capsuleInputBg,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: const [
                          Expanded(
                            child: Text(
                              '이름, 회사명, 키워드로 검색해 보세요',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.search, color: AppColors.capsuleInputText, size: 22),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status & Battery Optimization Translucent Pills
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: AppColors.accentLime, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              MotionStrategy.getModeLabel(viewModel.settings.batteryMode),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Proximity List Pill Widgets
                    Text(
                      '근접 인맥 리스트 (${viewModel.filteredContacts.length}명)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    ...viewModel.filteredContacts.map((contact) {
                      final distance = GeoUtils.getDistanceMeters(viewModel.currentPosition, contact.geo);
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        onTap: () => viewModel.openBriefing(contact),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.accentSky.withOpacity(0.2),
                              child: Text(
                                contact.name.substring(0, 1),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentSky),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${contact.name} ${contact.title}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    contact.company,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accentSky.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                GeoUtils.formatDistanceLabel(distance),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentSky),
                              ),
                            )
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Full Screen 30-Second AI Briefing Overlay
        if (viewModel.selectedContactForBriefing != null)
          BriefingOverlayView(
            contact: viewModel.selectedContactForBriefing!,
            onClose: viewModel.closeBriefing,
          ),
      ],
    );
  }
}
