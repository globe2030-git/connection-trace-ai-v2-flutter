import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/ai_usage_chip.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../view_models/radar_view_model.dart';
import 'my_profile_edit_modal_view.dart';
import 'qr_code_modal_view.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import '../../wallet/views/add_card_modal_view.dart';
import '../../../common/connection_sense_background_painter.dart';
import 'location_consent_sheet.dart';
import 'location_access_flow.dart';
import 'nearby_map_view.dart';

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
    final nearbyCount = viewModel.usingRealGps
        ? viewModel.filteredContacts.length
        : null;
    final restOfList = viewModel.filteredContacts
        .where((c) => c.id != nearby?.id)
        .toList();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bgBase,
          body: Container(
            decoration: const BoxDecoration(color: AppColors.bgBase),
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
                        // Header: title + greeting, 명함등록 / QR
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          // 오른쪽 버튼 묶음의 높이가 화면마다 달라도(원형
                          // 아이콘 2개 vs 라벨 있는 버튼 등) 제목이 항상
                          // 같은 높이에서 시작하도록 맨 위로 고정 — 기본값인
                          // center로 두면 제목이 버튼 높이에 따라 미묘하게
                          // 위아래로 밀린다(다른 탭과 비교 시 눈에 띔).
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  // 남은 AI 생성 횟수(탭하면 상세). 서비스 미배포/
                                  // 미조회 시 스스로 아무것도 그리지 않는다.
                                  const SizedBox(height: 8),
                                  const AiUsageChip(),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '명함 등록',
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.accentSoftStrong,
                                    shape: const CircleBorder(),
                                    // 기본 IconButton은 최소 48x48로 렌더링돼
                                    // 옆의 QR 버튼과 크기가 안 맞았다 —
                                    // 두 아이콘을 정확히 같은 크기(40px)로 고정.
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 40),
                                    maximumSize: const Size(40, 40),
                                  ),
                                  icon: const AppIcon(
                                    AppIconId.addCard,
                                    color: AppColors.accentText,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      AddCardModalView.show(context),
                                ),
                                IconButton(
                                  tooltip: 'QR 스캔',
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppColors.accentSoftStrong,
                                    shape: const CircleBorder(),
                                    // 기본 IconButton은 최소 48x48로 렌더링돼
                                    // 옆의 명함등록 버튼과 크기가 안 맞았다 —
                                    // 두 아이콘을 정확히 같은 크기(40px)로 고정.
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(40, 40),
                                    maximumSize: const Size(40, 40),
                                  ),
                                  icon: const AppIcon(
                                    AppIconId.qrScan,
                                    color: AppColors.accentText,
                                    size: 20,
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
                                      AddCardModalView.show(
                                        context,
                                        prefillData: scannedContact,
                                      );
                                    });
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

                        // 새 기기에서 복원한 직후에는 명함 좌표가 없어 거리
                        // 계산이 안 된다(좌표는 서버에 백업하지 않고 주소로
                        // 다시 계산한다 — backlog 추가 75). 그동안 "주변에
                        // 아무도 없음"으로 보이면 오해를 사므로 준비 중임을
                        // 알린다.
                        // 앱을 처음 깔면 내 명함이 없는데 화면 어디에도 그걸
                        // 알리는 표시가 없어서, 무엇을 먼저 해야 하는지 알 수
                        // 없었다(실사용 피드백). 위치 안내보다 아래, 인맥
                        // 목록보다 위에 둬서 "권한 → 내 명함 → 인맥"이라는
                        // 자연스러운 순서가 되게 한다.
                        if (context
                            .watch<MyProfileRepository>()
                            .profile
                            .isUnset) ...[
                          const _SetupMyCardCard(),
                          const SizedBox(height: 16),
                        ],

                        if (viewModel.isPreparingContactLocations) ...[
                          _PreparingLocationsCard(
                            done: viewModel.contactLocationsPrepared,
                            total: viewModel.contactLocationsToPrepare,
                          ),
                          const SizedBox(height: 16),
                        ],

                        // 감지 반경 선택. 원래 설정 화면에만 있었는데, 반경을
                        // 바꾸면 바로 이 목록이 달라지므로 결과를 보면서 고를
                        // 수 있는 이 화면이 제자리다(사용자 요청, 추가 139).
                        Align(
                          alignment: Alignment.centerRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _RadiusSelector(
                                radiusMeters: viewModel.settings.radiusMeters,
                                onChanged: viewModel.updateRadius,
                              ),
                              const SizedBox(height: 6),
                              // 반경 선택 바로 아래 — 반경을 정하고 그 결과를
                              // 지도에서 확인하는 순서가 자연스럽다.
                              _ExpandToMapButton(
                                enabled: viewModel.usingRealGps,
                                onTap: () => NearbyMapView.show(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // "지금 가까운 사람 N명" 요약 카드 — 탭하면 위치를 새로고침한다.
                        _NearbyCountCard(
                          count: nearbyCount,
                          isRefreshing: viewModel.isRefreshingLocation,
                          onTap: viewModel.isRefreshingLocation
                              ? null
                              : () => handleLocationAccessAction(
                                  context,
                                  viewModel,
                                ),
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
                            border: Border.all(color: AppColors.borderSubtle),
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
                                  '위치는 사용 중에만 확인해요.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: viewModel.isRefreshingLocation
                                    ? 'GPS 확인 중...'
                                    : viewModel.usingRealGps
                                    ? '내 위치 갱신'
                                    : '위치 설정',
                                child: InkWell(
                                  onTap: viewModel.isRefreshingLocation
                                      ? null
                                      : () => handleLocationAccessAction(
                                          context,
                                          viewModel,
                                        ),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentText.withValues(
                                        alpha: 0.2,
                                      ),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.accentText.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: viewModel.isRefreshingLocation
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
                                  cardImagePath: contact.useCardAsAvatar
                                      ? contact.cardImagePath
                                      : null,
                                  uid: contact.useCardAsAvatar
                                      ? context
                                            .read<AuthRepository>()
                                            .firebaseUid
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
                                        [contact.company, contact.phone]
                                            .where((s) => s.trim().isNotEmpty)
                                            .join(' · '),
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
/// 내 명함을 아직 만들지 않았을 때 첫 화면에 띄우는 안내.
///
/// 왜 필요한가: 앱을 처음 설치하면 할 일이 무엇인지 알려주는 것이 아무것도
/// 없었다. 내 명함 설정은 설정 화면 안에 있어서 찾아 들어가야 했고, 그걸
/// 모르면 "명함을 등록해도 AI가 나를 모르는" 상태로 계속 쓰게 된다 —
/// AI 대화 가이드는 내 정보를 상대에게 소개하는 근거로 쓰기 때문이다.
///
/// 닫기 버튼을 두지 않은 이유: 이 카드는 내 명함을 만들면 저절로 사라진다.
/// 닫을 수 있게 하면 "닫아 놓고 영영 설정하지 않는" 상태가 되는데, 그 상태의
/// 사용자는 앱의 핵심 기능을 반쪽만 쓰게 된다.
class _SetupMyCardCard extends StatelessWidget {
  const _SetupMyCardCard();

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
            child: const AppIcon(
              AppIconId.cardData,
              size: 22,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '내 명함을 먼저 만들어 주세요',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'AI가 상대에게 나를 소개할 때 이 정보를 씁니다',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => MyProfileEditModalView.show(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '만들기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                cardImagePath: contact.useCardAsAvatar
                    ? contact.cardImagePath
                    : null,
                uid: contact.useCardAsAvatar
                    ? context.read<AuthRepository>().firebaseUid
                    : null,
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

/// 감지 반경 선택 버튼. 현재 반경을 보여주고, 누르면 선택 시트를 연다.
///
/// 설정 화면에도 같은 항목이 있었지만 그쪽에서는 결과를 볼 수 없었다 —
/// 반경을 바꾸면 바로 달라지는 것이 "주변 인맥" 목록이라 여기가 제자리다
/// (사용자 요청, 추가 139).
class _RadiusSelector extends StatelessWidget {
  final double radiusMeters;
  final ValueChanged<double> onChanged;

  const _RadiusSelector({required this.radiusMeters, required this.onChanged});

  /// 3km·5km는 사용자 요청으로 추가했다(추가 139). 도보권(500m)과 같은 동네
  /// (1km) 사이만으로는 "차로 잠깐 가는 거리"를 담을 수 없었다.
  static const options = <double>[500, 1000, 3000, 5000, double.infinity];

  static String label(double meters) {
    if (meters.isInfinite) return '제한 없음';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(0)}km';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _openPicker(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.borderFunctional),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(
                AppIconId.detectRadius,
                size: 16,
                color: AppColors.accentText,
              ),
              const SizedBox(width: 6),
              Text(
                '반경 ${label(radiusMeters)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.expand_more,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.cardSurface,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '감지 반경',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                '주변 인맥 목록에 표시할 최대 거리를 선택하세요. 고른 값은 기기에 저장돼 다음에 열어도 그대로 유지됩니다.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (final option in options)
                ListTile(
                  minTileHeight: 52,
                  title: Text(label(option)),
                  trailing: radiusMeters == option
                      ? const Icon(Icons.check_circle, color: AppColors.accent)
                      : const Icon(
                          Icons.circle_outlined,
                          color: AppColors.textMuted,
                        ),
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }
}

/// 지도를 여는 "확대" 버튼.
///
/// 목록만으로는 "어느 방향으로 얼마나 떨어져 있는지"를 알 수 없다 — 거리
/// 숫자는 방향을 담지 못한다. 지도는 그 한 가지를 위해 있다.
class _ExpandToMapButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _ExpandToMapButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? AppColors.accentText : AppColors.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? AppColors.accentSoft : AppColors.bgBase,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          // 위치를 아직 못 잡았으면 지도를 열어도 보여 줄 기준점이 없다.
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: enabled
                    ? AppColors.accentSoftStrong
                    : AppColors.borderFunctional,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.zoom_out_map, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  '지도에서 크게 보기',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
