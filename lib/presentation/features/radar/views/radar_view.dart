import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/motion_strategy.dart';
import '../../../common/glass_card.dart';
import '../../../common/action_circle_button.dart';
import '../view_models/radar_view_model.dart';
import 'qr_code_modal_view.dart';
import 'notification_center_modal_view.dart';
import 'my_profile_modal_view.dart';
import 'priority_modal_view.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import '../../wallet/views/add_card_modal_view.dart';

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
              color: AppColors.bgDarkSlate,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top App Title & Sub Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Connection Trace',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: AppColors.textPrimary, size: 22),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const QrCodeModalView(),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.notifications_none, color: AppColors.textPrimary, size: 22),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const NotificationCenterModalView(),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.person_outline, color: AppColors.textPrimary, size: 22),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const MyProfileModalView(),
                                );
                              },
                            ),
                          ],
                        )
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Big Hero Proximity Metric
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
                              color: AppColors.accentText,
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

                    const SizedBox(height: 20),

                    // Hero Animated Radar Pulse Beacon Container (ME Center + Surrounding Contact Blips)
                    Center(
                      child: RadarPulseHeroWidget(nearbyContact: nearby),
                    ),

                    const SizedBox(height: 20),

                    // Quick Action Control Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ActionCircleButton(
                          icon: Icons.radar,
                          label: viewModel.settings.enabled ? '감지 ON' : '감지 OFF',
                          isActive: viewModel.settings.enabled,
                          onTap: () => viewModel.toggleDetection(),
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
                          icon: Icons.add_card,
                          label: '명함 등록',
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const AddCardModalView(),
                            );
                          },
                        ),
                        ActionCircleButton(
                          icon: Icons.star,
                          label: '우선 알림',
                          isActive: true,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const PriorityModalView(),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Rounded Capsule Search Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.capsuleInputBg,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: Row(
                        children: const [
                          Expanded(
                            child: Text(
                              '이름, 회사명, 키워드로 검색해 보세요',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.search, color: AppColors.capsuleInputText, size: 22),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Status & Battery Optimization Translucent Pills + Location Refresh Button
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.bolt, color: AppColors.accentText, size: 18),
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
                          InkWell(
                            onTap: viewModel.isRefreshingLocation ? null : viewModel.refreshLocation,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.accentText.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.accentText.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                children: [
                                  viewModel.isRefreshingLocation
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentText),
                                        )
                                      : const Icon(Icons.my_location, color: AppColors.accentText, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    viewModel.isRefreshingLocation ? 'GPS 갱신 중...' : '내 위치 갱신',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.accentText),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Proximity List Pill Widgets (Sorted by Distance first, Name alphabetical second)
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
                              backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                              backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
                              child: contact.avatarUrl == null
                                  ? Text(
                                      contact.name.substring(0, 1),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentText),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${contact.name} ${contact.title}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                                color: AppColors.accentText.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                GeoUtils.formatDistanceLabel(distance),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accentText),
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

/// Pulsing Animated Wi-Fi / Radar Beacon Widget for ME vs Nearby Contacts
class RadarPulseHeroWidget extends StatefulWidget {
  final dynamic nearbyContact;

  const RadarPulseHeroWidget({super.key, this.nearbyContact});

  @override
  State<RadarPulseHeroWidget> createState() => _RadarPulseHeroWidgetState();
}

class _RadarPulseHeroWidgetState extends State<RadarPulseHeroWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 160,
      decoration: BoxDecoration(
        color: AppColors.cardDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseVal = _pulseController.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Expanding Wi-Fi / Radar Pulse Waves centered on ME
              Container(
                width: 60 + (pulseVal * 120),
                height: 60 + (pulseVal * 120),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentText.withValues(alpha: (1.0 - pulseVal) * 0.5),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 40 + (pulseVal * 60),
                height: 40 + (pulseVal * 60),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.accentText.withValues(alpha: (1.0 - pulseVal) * 0.6),
                    width: 1.5,
                  ),
                ),
              ),

              // ME Central Pulsing Beacon (Compact size with bright indicator)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bgDarkSlate,
                      border: Border.all(color: AppColors.accentText, width: 1.5),
                    ),
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.accent,
                      child: Icon(Icons.wifi_tethering, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'ME (내 위치)',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  )
                ],
              ),

              // Nearby Contact Blip Positioned on Radar Ring (Distinctly distinguished!)
              if (widget.nearbyContact != null)
                Positioned(
                  top: 18,
                  right: 28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accentText),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.accent,
                          child: Text(
                            widget.nearbyContact.name.substring(0, 1),
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${widget.nearbyContact.name} 140m',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
