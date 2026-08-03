import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../common/glass_card.dart';
import '../../../common/action_circle_button.dart';
import '../view_models/radar_view_model.dart';
import 'qr_code_modal_view.dart';
import 'my_profile_modal_view.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import '../../wallet/views/add_card_modal_view.dart';
import '../../../common/connection_sense_background_painter.dart';
import 'location_consent_sheet.dart';
import 'location_access_flow.dart';

class RadarView extends StatefulWidget {
  const RadarView({super.key});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> {
  bool _initialConsentPromptScheduled = false;
  bool _consentSheetVisible = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RadarViewModel>();
    if (viewModel.shouldShowLocationConsent &&
        !_initialConsentPromptScheduled &&
        !_consentSheetVisible) {
      _initialConsentPromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showConsent(viewModel);
      });
    }

    final nearby = viewModel.nearbyAlertContact;
    final nearbyDistance = nearby != null
        ? GeoUtils.getDistanceMeters(viewModel.currentPosition, nearby.geo)
        : null;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bgDarkSlate,
          body: Container(
            decoration: const BoxDecoration(color: AppColors.bgDarkSlate),
            child: Stack(
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ConnectionSenseBackgroundPainter(),
                    ),
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top App Title & Sub Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '주변 인맥',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _greetingForNow(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    color: AppColors.textPrimary,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet<ContactModel>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const QrCodeModalView(),
                                    ).then((scannedContact) {
                                      if (scannedContact == null ||
                                          !context.mounted) {
                                        return;
                                      }
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => AddCardModalView(
                                          prefillData: scannedContact,
                                        ),
                                      );
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.person_outline,
                                    color: AppColors.textPrimary,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) =>
                                          const MyProfileModalView(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        if (viewModel.locationAccessState !=
                            LocationAccessState.ready) ...[
                          _LocationStatusCard(
                            viewModel: viewModel,
                            onAction: () =>
                                handleLocationAccessAction(context, viewModel),
                          ),
                          const SizedBox(height: 16),
                        ],

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
                                    nearbyDistance != null
                                        ? (nearbyDistance < 1000
                                              ? '${nearbyDistance.round()}'
                                              : (nearbyDistance / 1000)
                                                    .toStringAsFixed(1))
                                        : '--',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -1.0,
                                    ),
                                  ),
                                  if (nearbyDistance != null) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      nearbyDistance < 1000 ? 'm' : 'km',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
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
                                    : viewModel.usingRealGps
                                    ? '주변에 감지된 인맥이 없습니다'
                                    : '위치 권한이 없어 거리를 표시할 수 없습니다',
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
                          child: RadarPulseHeroWidget(
                            nearbyContact: nearby,
                            nearbyDistanceMeters: nearbyDistance,
                            isLocationAvailable: viewModel.usingRealGps,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Quick Action Control Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ActionCircleButton(
                              icon: viewModel.usingRealGps
                                  ? Icons.my_location
                                  : Icons.location_off_outlined,
                              label: viewModel.usingRealGps ? '위치 갱신' : '위치 설정',
                              isActive: viewModel.usingRealGps,
                              onTap: () => handleLocationAccessAction(
                                context,
                                viewModel,
                              ),
                            ),
                            ActionCircleButton(
                              icon: Icons.description_outlined,
                              label: 'AI 브리핑',
                              isActive: nearby != null,
                              onTap: nearby == null
                                  ? null
                                  : () => viewModel.openBriefing(nearby),
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
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Rounded Capsule Search Bar — 근접 인맥 리스트를 이름/회사/직함으로 필터링
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.capsuleInputBg,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: viewModel.setSearchTerm,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.capsuleInputText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: '이름, 회사명, 키워드로 검색해 보세요',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.search,
                                color: AppColors.capsuleInputText,
                                size: 22,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 위치를 계속 추적하지 않는 실제 동작을 명확하게 안내한다.
                        GlassCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.privacy_tip_outlined,
                                color: AppColors.accentText,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '위치는 앱 사용 중 요청할 때만 확인합니다.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: viewModel.isRefreshingLocation
                                    ? null
                                    : () => handleLocationAccessAction(
                                        context,
                                        viewModel,
                                      ),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentText.withValues(
                                      alpha: 0.2,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.accentText.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      viewModel.isRefreshingLocation
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.accentText,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.my_location,
                                              color: AppColors.accentText,
                                              size: 14,
                                            ),
                                      const SizedBox(width: 6),
                                      Text(
                                        viewModel.isRefreshingLocation
                                            ? 'GPS 확인 중...'
                                            : viewModel.usingRealGps
                                            ? '내 위치 갱신'
                                            : '위치 설정',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accentText,
                                        ),
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
                          final distance = GeoUtils.getDistanceMeters(
                            viewModel.currentPosition,
                            contact.geo,
                          );
                          return GlassCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            onTap: () => viewModel.openBriefing(contact),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppColors.accent.withValues(
                                    alpha: 0.2,
                                  ),
                                  backgroundImage: contact.avatarUrl != null
                                      ? NetworkImage(contact.avatarUrl!)
                                      : null,
                                  child: contact.avatarUrl == null
                                      ? Text(
                                          contact.name.substring(0, 1),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.accentText,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${contact.name} ${contact.title}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        contact.company,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentText.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    GeoUtils.formatDistanceLabel(distance),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accentText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
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

  Future<void> _showConsent(RadarViewModel viewModel) async {
    if (_consentSheetVisible) return;
    _consentSheetVisible = true;
    final accepted = await showLocationConsentSheet(context);
    _consentSheetVisible = false;
    if (!mounted || accepted == null) return;
    if (accepted) {
      await viewModel.acceptLocationConsent();
    } else {
      await viewModel.declineLocationConsent();
    }
  }
}

class _LocationStatusCard extends StatelessWidget {
  final RadarViewModel viewModel;
  final VoidCallback onAction;

  const _LocationStatusCard({required this.viewModel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final (title, message, actionLabel) = _locationStatusCopy(
      viewModel.locationAccessState,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentText.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: viewModel.isRefreshingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentText,
                      ),
                    )
                  : const Icon(
                      Icons.location_off_outlined,
                      color: AppColors.accentText,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: viewModel.isRefreshingLocation
                          ? null
                          : onAction,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

(String, String, String?) _locationStatusCopy(LocationAccessState state) {
  return switch (state) {
    LocationAccessState.loading ||
    LocationAccessState.locating => ('위치 상태를 확인하고 있어요', '잠시만 기다려 주세요.', null),
    LocationAccessState.consentRequired => (
      '위치 사용 동의가 필요해요',
      '동의 전에는 운영체제 위치 권한을 요청하지 않습니다.',
      '위치 사용 안내 보기',
    ),
    LocationAccessState.consentDeclined => (
      '위치 없이 사용 중이에요',
      '명함 기능은 사용할 수 있지만 주변 거리 기능은 표시되지 않습니다.',
      '위치 사용하기',
    ),
    LocationAccessState.serviceDisabled => (
      '기기의 위치 서비스가 꺼져 있어요',
      '주변 거리를 표시하려면 기기 위치 서비스를 켜 주세요.',
      '위치 설정 열기',
    ),
    LocationAccessState.permissionDenied => (
      '위치 권한이 허용되지 않았어요',
      '위치 권한이 없어 거리를 표시할 수 없습니다.',
      '위치 권한 허용',
    ),
    LocationAccessState.permissionDeniedForever => (
      '위치 권한이 차단되어 있어요',
      '기기 설정에서 커넥션센스의 위치 권한을 허용해 주세요.',
      '앱 권한 설정 열기',
    ),
    LocationAccessState.ready => (
      '위치 서비스 사용 중',
      '현재 위치로 주변 인맥과의 거리를 계산합니다.',
      null,
    ),
    LocationAccessState.unavailable => (
      '현재 위치를 확인하지 못했어요',
      '잠시 후 다시 시도하거나 기기 위치 설정을 확인해 주세요.',
      '다시 시도',
    ),
  };
}

String _greetingForNow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return '좋은 오전이에요!';
  if (hour < 18) return '좋은 오후예요!';
  return '편안한 저녁이에요!';
}

/// 배터리를 지속적으로 사용하는 반복 애니메이션 없이 현재 위치와 가장 가까운
/// 실제 인맥만 정적으로 보여주는 레이더 요약 카드.
class RadarPulseHeroWidget extends StatelessWidget {
  final dynamic nearbyContact;
  final double? nearbyDistanceMeters;
  final bool isLocationAvailable;

  const RadarPulseHeroWidget({
    super.key,
    this.nearbyContact,
    this.nearbyDistanceMeters,
    this.isLocationAvailable = true,
  });

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
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isLocationAvailable) ...[
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
              ),
            ),
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentSoft.withValues(alpha: 0.65),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.22),
                ),
              ),
            ),
          ],

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
                  child: Icon(
                    Icons.wifi_tethering,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isLocationAvailable ? '내 위치' : '위치 확인 필요',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          // Nearby Contact Blip Positioned on Radar Ring (Distinctly distinguished!)
          if (isLocationAvailable && nearbyContact != null)
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
                        nearbyContact.name.substring(0, 1),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${nearbyContact.name} ${GeoUtils.formatDistanceLabel(nearbyDistanceMeters).replaceAll(' 근접', '')}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
