import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
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
    final myProfile = context.watch<MyProfileRepository>().profile;
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
    final nearbyCount = viewModel.usingRealGps
        ? viewModel.filteredContacts.length
        : null;
    final restOfList = viewModel.filteredContacts
        .where((c) => c.id != nearby?.id)
        .toList();

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
                        // Header: title + greeting, QR / 명함등록 / 내 프로필
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
                                  tooltip: 'QR 스캔',
                                  icon: const AppIcon(
                                    AppIconId.qrScan,
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
                                  tooltip: '명함 등록',
                                  icon: const AppIcon(
                                    AppIconId.addCard,
                                    color: AppColors.textPrimary,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const AddCardModalView(),
                                    );
                                  },
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) =>
                                          const MyProfileModalView(),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: ContactAvatar(
                                      photoPath: myProfile.avatarPath,
                                      name: myProfile.name.isEmpty
                                          ? '?'
                                          : myProfile.name,
                                      radius: 16,
                                    ),
                                  ),
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

                        // 새 기기에서 복원한 직후에는 명함 좌표가 없어 거리
                        // 계산이 안 된다(좌표는 서버에 백업하지 않고 주소로
                        // 다시 계산한다 — backlog 추가 75). 그동안 "주변에
                        // 아무도 없음"으로 보이면 오해를 사므로 준비 중임을
                        // 알린다.
                        if (viewModel.isPreparingContactLocations) ...[
                          _PreparingLocationsCard(
                            done: viewModel.contactLocationsPrepared,
                            total: viewModel.contactLocationsToPrepare,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // "지금 가까운 사람 N명" 요약 카드 — 탭하면 위치를 새로고침한다.
                        _NearbyCountCard(
                          count: nearbyCount,
                          isRefreshing: viewModel.isRefreshingLocation,
                          onTap: viewModel.isRefreshingLocation
                              ? null
                              : () =>
                                    handleLocationAccessAction(context, viewModel),
                        ),

                        const SizedBox(height: 14),

                        // 가장 가까운 인맥을 대표 카드로 크게 보여준다.
                        if (nearby != null)
                          _FeaturedContactCard(
                            contact: nearby,
                            distanceMeters: nearbyDistance,
                            onCall: nearby.phone.trim().isEmpty
                                ? null
                                : () => PhoneCallService.showCallPicker(
                                    context,
                                    nearby,
                                  ),
                            // "가까운 인맥" 리스트 항목을 눌렀을 때와 똑같이 AI
                            // 브리핑 화면(연락처 정보 + AI 연동 + 전화)으로 간다.
                            // 예전엔 명함 수정 폼(카메라 스캔 버튼까지 있는)이
                            // 열려서 그냥 보려는 건데 수정 화면처럼 보이는
                            // 문제가 있었다.
                            onDetail: () => viewModel.openBriefing(nearby),
                          )
                        else
                          GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                viewModel.usingRealGps
                                    ? '주변에 감지된 인맥이 없습니다'
                                    : '위치 권한이 없어 거리를 표시할 수 없습니다',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

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

                        const SizedBox(height: 16),

                        // 가까운 인맥 리스트 (대표 카드에 나온 사람은 제외)
                        Text(
                          '가까운 인맥 (${restOfList.length}명)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),

                        ...restOfList.map((contact) {
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
                                ContactAvatar(
                                  photoPath: contact.avatarUrl,
                                  name: contact.name,
                                  radius: 20,
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
                                        [
                                          contact.company,
                                          contact.phone,
                                        ].where((s) => s.trim().isNotEmpty).join(
                                          ' · ',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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

/// "지금 가까운 사람 N명" 요약 카드.
/// 명함 좌표를 주소로부터 다시 계산하는 동안 보여주는 안내.
///
/// 좌표는 서버에 백업하지 않기 때문에(backlog 추가 75, C안) 기기를 바꾸거나
/// 계정을 다시 연결하면 이 구간이 잠깐 생긴다. 이 카드가 없으면 사용자에게는
/// "인맥이 다 사라진 것"처럼 보인다.
class _PreparingLocationsCard extends StatelessWidget {
  final int done;
  final int total;

  const _PreparingLocationsCard({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total > 0
                      ? '인맥 위치를 준비하고 있어요 ($done/$total)'
                      : '인맥 위치를 준비하고 있어요',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '명함 주소로 위치를 계산하는 중입니다. 끝나면 주변 인맥이 표시됩니다.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyCountCard extends StatelessWidget {
  final int? count;
  final bool isRefreshing;
  final VoidCallback? onTap;

  const _NearbyCountCard({
    required this.count,
    required this.isRefreshing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : const AppIcon(
                      AppIconId.radarDetect,
                      color: AppColors.accent,
                      size: 22,
                    ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '지금 가까운 사람',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count != null ? '$count명' : '--',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accentText,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 가장 가까운 인맥을 크게 보여주는 대표 카드.
class _FeaturedContactCard extends StatelessWidget {
  final ContactModel contact;
  final double? distanceMeters;
  final VoidCallback? onCall;
  final VoidCallback onDetail;

  const _FeaturedContactCard({
    required this.contact,
    required this.distanceMeters,
    required this.onCall,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      contact.company,
      contact.title,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContactAvatar(
                photoPath: contact.avatarUrl,
                name: contact.name,
                radius: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 12,
                                color: AppColors.accentText,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                GeoUtils.formatDistanceLabel(distanceMeters),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _lastContactLabel(contact),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCall,
                  icon: const AppIcon(
                    AppIconId.callCheck,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    '연락하기',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton.icon(
                onPressed: onDetail,
                icon: const Text(
                  'AI 대화 가이드',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentText,
                  ),
                ),
                label: const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.accentText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 최근 소통 기록 중 가장 최신 항목을 기준으로 "N일 전" 형태로 보여준다.
/// 소통 기록이 없으면 가짜로 채우지 않고 "소통 기록 없음"으로 표시한다.
String _lastContactLabel(ContactModel contact) {
  if (contact.commLogs.isEmpty) return '소통 기록 없음';
  final latest = contact.commLogs
      .map((l) => l.timestamp)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final days = DateTime.now().difference(latest).inDays;
  if (days <= 0) return '오늘 연락';
  if (days == 1) return '최근 연락 어제';
  return '최근 연락 $days일 전';
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
