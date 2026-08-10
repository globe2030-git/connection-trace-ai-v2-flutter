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
    final size = MediaQuery.sizeOf(context);
    final viewModel = context.watch<RadarViewModel>();
    if (viewModel.shouldShowLocationConsent &&
        !_initialConsentPromptScheduled &&
        !_consentSheetVisible) {
      _initialConsentPromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showConsent(viewModel);
      });
    }

    final nearbyCount = viewModel.usingRealGps
        ? viewModel.filteredContacts.length
        : null;
    // 가장 가까운 한 명도 목록에 포함한다 — 대표 카드를 없앴으므로 빼면
    // 그 사람만 어디에도 안 나온다(사용자 요청, 2026-08-10).
    final nearbyList = viewModel.filteredContacts;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bgBase,
          body: Container(
            decoration: const BoxDecoration(color: AppColors.bgBase),
            child: Stack(
              children: [
                // 배경을 손으로 그린 레이더 링 대신 **앱 아이콘 마크**로
                // 바꿨다(사용자 요청, 2026-08-10). 앱을 켰을 때 보이는 첫
                // 화면이 스플래시·런처 아이콘과 같은 그림이라 브랜드가 이어진다.
                //
                // 아주 옅게(6%) 깔고 오른쪽 위로 밀어 둔다 — 본문 글자와
                // 겹치는 자리라 진하면 읽기를 방해한다. `ExcludeSemantics`로
                // 스크린리더에서는 아예 없는 것으로 다룬다(장식용이다).
                Positioned(
                  top: -size.width * 0.18,
                  right: -size.width * 0.22,
                  width: size.width * 0.95,
                  child: const ExcludeSemantics(
                    child: Opacity(
                      opacity: 0.06,
                      child: RepaintBoundary(
                        child: Image(
                          image: AssetImage(
                            'assets/icons3d/pin_card_blue_splash.png',
                          ),
                          fit: BoxFit.contain,
                        ),
                      ),
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
                        // 반경 선택과 지도 열기를 한 줄에 나란히 둔다(사용자
                        // 요청, 2026-08-10). 둘은 "주변을 어디까지, 어떻게 볼
                        // 것인가"라는 같은 결정에 속하는데 각각 한 줄씩 차지해
                        // 화면 위쪽을 두 줄이나 먹고 있었다.
                        //
                        // `Row`가 아니라 `Wrap`인 이유: 반경이 "제한 없음"일
                        // 때 라벨이 가장 길어지는데, 화면이 좁거나 시스템 글자
                        // 크기를 키운 기기에서는 두 버튼이 한 줄에 안 들어갈 수
                        // 있다. `Row`면 그 상황에서 오버플로 줄무늬가 뜨지만
                        // `Wrap`은 조용히 아랫줄로 내려 준다.
                        Wrap(
                          // 오른쪽 정렬에서 가운데 정렬로(사용자 요청,
                          // 2026-08-10). 이 줄은 화면 폭을 거의 다 쓰는 카드
                          // 위에 얹혀 있어, 오른쪽으로 몰아 두면 왼쪽이 크게
                          // 비어 균형이 맞지 않았다.
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // 지도 → 반경 순서(사용자 요청, 2026-08-10).
                            // 지도를 먼저 열고 그 안에서 범위를 가늠하는
                            // 흐름을 앞세운다.
                            _ExpandToMapButton(
                              enabled: viewModel.usingRealGps,
                              onTap: () => NearbyMapView.show(context),
                            ),
                            _RadiusSelector(
                              radiusMeters: viewModel.settings.radiusMeters,
                              onChanged: viewModel.updateRadius,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 검색창을 반경·지도 줄 바로 아래로 옮겼다(사용자 요청,
                        // 2026-08-10). 예전에는 대표 카드 아래에 있어서, 찾고
                        // 싶은 사람이 있을 때 화면을 한참 내려야 보였다.
                        // Rounded Capsule Search Bar — 근접 인맥 리스트를 이름/회사/직함으로 필터링
                        Container(
                          // 높이를 약 15% 줄인다(사용자 요청, 2026-08-10).
                          // 캡슐 자체의 세로 여백을 없애고 TextField가 스스로
                          // 잡는 높이만 남긴다 — 글자 크기는 건드리지 않아
                          // 읽기 어려워지지 않는다.
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          constraints: const BoxConstraints(minHeight: 40),
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
                                    // 기본 세로 여백(약 8)을 줄여 캡슐 높이를
                                    // 낮춘다. 터치는 캡슐 전체가 받으므로
                                    // 목표 크기는 minHeight 40으로 지킨다.
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
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

                        const SizedBox(height: 12),

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

                        const SizedBox(height: 8),

                        // 위치 아이콘과 조작 안내를 "지금 가까운 사람" 카드
                        // 바로 아래 한 줄에 둔다(사용자 요청, 2026-08-10).
                        // 아이콘이 무엇을 켜고 끄는지가 그 카드의 숫자이므로,
                        // 상단 버튼 줄보다 여기가 가깝다.
                        //
                        // 길게 누르기는 눌러 보기 전에는 알 수 없는 동작이라
                        // 설명을 옆에 붙인다. 툴팁만으로는 길게 눌러야 뜨는데,
                        // 그 자체가 길게 누를 줄 아는 사람에게만 보인다.
                        Row(
                          children: [
                            _RefreshLocationButton(
                              isRefreshing: viewModel.isRefreshingLocation,
                              usingRealGps: viewModel.usingRealGps,
                              isDetecting: viewModel.hasLocationConsent,
                              onTap: () => handleLocationAccessAction(
                                context,
                                viewModel,
                              ),
                              onToggleDetect: () =>
                                  _toggleNearbyDetect(context, viewModel),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '짧게: 위치 갱신 · 길게: 주변 인맥 감지 켜기/끄기',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                            // 남은 AI 생성 횟수(탭하면 상세). 제목 아래에
                            // 있던 것을 이 줄로 옮겼다(사용자 요청,
                            // 2026-08-10) — 제목 영역이 세 줄로 길어져
                            // 화면 위쪽을 많이 먹고 있었다. 서비스 미배포·
                            // 미조회 시에는 스스로 아무것도 그리지 않으므로
                            // 이 줄이 비어 보이지 않는다.
                            const AiUsageChip(),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // 가장 가까운 한 명을 큰 대표 카드로 따로 보여 주던
                        // 것을 없앴다(사용자 요청, 2026-08-10). 같은 사람이
                        // 카드와 목록 두 곳에 다른 모양으로 나타나 "왜 저
                        // 사람만 다른가"를 설명해야 했고, 대표 카드가 화면
                        // 절반을 먹어 정작 목록은 스크롤해야 보였다.
                        // 이제 **가장 가까운 사람도 목록의 첫 줄**로 들어간다.
                        if (viewModel.filteredContacts.isEmpty)
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

                        const SizedBox(height: 16),

                        // 가까운 인맥 리스트 (대표 카드에 나온 사람은 제외)
                        Text(
                          '가까운 인맥 (${nearbyList.length}명)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 명함 지갑 목록과 같은 형태로 맞춘다(사용자 요청,
                        // 2026-08-10) — 이름/직함/회사명 세 줄, 아바타 왼쪽,
                        // 오른쪽에 동작 버튼. 같은 인맥을 두 화면에서 다른
                        // 모양으로 보여 줄 이유가 없다.
                        //
                        // 다른 점 하나: 여기에는 **근접 거리**가 함께 붙는다.
                        // 이 화면의 존재 이유가 "지금 얼마나 가까운가"이므로
                        // 목록에서도 그 값이 보여야 한다.
                        ...nearbyList.map((contact) {
                          final distance = GeoUtils.getDistanceMeters(
                            viewModel.currentPosition,
                            contact.geo,
                          );
                          return _NearbyContactTile(
                            contact: contact,
                            distanceMeters: distance,
                            onOpen: () => viewModel.openBriefing(contact),
                            onCall: () => PhoneCallService.showCallPicker(
                              context,
                              contact,
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
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        // 배경을 지도 느낌으로 깐다(사용자 결정, 2026-08-10).
        //
        // **실제 지도 타일이 아니라 앱이 그린 그래픽이다.** 홈 화면에 진짜
        // 지도를 깔면 앱을 켜기만 해도 지도 사업자에게 타일 요청이 나가는데,
        // 오늘 배포한 개인정보처리방침 10-3은 "지도 화면을 열지 않으면 어떤
        // 요청도 발생하지 않는다"고 적고 있다. 방침을 고치는 대신 요청이 아예
        // 없는 방식을 택했다 — 방침과 구현이 어긋나는 것 자체가 리스크다.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _MapStyleCardPainter()),
                  ),
                ),
              ),
              Padding(
                // 대표 카드를 없앤 자리를 이 카드가 대신한다(사용자 요청,
                // 2026-08-10). 여백과 아이콘·숫자를 키워 예전 대표 카드와
                // 비슷한 덩치를 갖게 했다 — 화면 위쪽이 허전해지지 않도록.
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 31,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
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
                    // 라벨은 왼쪽, 숫자는 오른쪽 끝(사용자 요청, 2026-08-10). 예전에는
                    // 둘이 왼쪽에 붙어 있어 카드 오른쪽 절반이 통째로 비어 있었다.
                    const Expanded(
                      child: Text(
                        '지금 가까운 사람',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "지금 가까운 사람" 카드의 지도풍 배경.
///
/// **실제 지도가 아니다.** 도로 격자와 블록, 그리고 현위치를 뜻하는 동심원을
/// 옅게 그린 장식이다. 진짜 타일을 쓰면 홈 화면을 열 때마다 지도 사업자에게
/// 요청이 나가고, 그러면 개인정보처리방침 10-3("지도 화면을 열지 않으면 어떤
/// 요청도 발생하지 않습니다")과 어긋난다(사용자 결정, 2026-08-10).
///
/// 카드 위에는 라벨과 큰 숫자가 얹히므로 대비를 해치지 않도록 아주 옅게만
/// 그린다.
class _MapStyleCardPainter extends CustomPainter {
  const _MapStyleCardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final blockPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.accent.withValues(alpha: 0.05);
    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.06
      ..color = Colors.white.withValues(alpha: 0.55);
    final thinRoadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.03
      ..color = Colors.white.withValues(alpha: 0.4);

    // 블록(건물 덩어리) — 도로 사이를 채워 지도처럼 보이게 한다.
    for (final rect in [
      Rect.fromLTWH(0, 0, size.width * 0.34, size.height * 0.42),
      Rect.fromLTWH(size.width * 0.44, 0, size.width * 0.28, size.height * 0.3),
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.58,
        size.width * 0.3,
        size.height * 0.42,
      ),
      Rect.fromLTWH(
        size.width * 0.62,
        size.height * 0.46,
        size.width * 0.3,
        size.height * 0.54,
      ),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        blockPaint,
      );
    }

    // 도로 — 가로세로로 가로지르는 흰 선.
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.4, 0),
      Offset(size.width * 0.4, size.height),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.78, 0),
      Offset(size.width * 0.78, size.height),
      thinRoadPaint,
    );

    // 현위치 표시 — 도로 교차점에 동심원.
    final center = Offset(size.width * 0.4, size.height * 0.5);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.accent.withValues(alpha: 0.28);
    canvas.drawCircle(center, size.height * 0.34, ringPaint);
    canvas.drawCircle(center, size.height * 0.2, ringPaint);
    canvas.drawCircle(
      center,
      size.height * 0.07,
      Paint()..color = AppColors.accent.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                // 반경 칩과 한 줄에 들어가야 해서 "지도에서 크게 보기"를
                // 줄였다. 아이콘이 함께 있어 뜻은 그대로 읽힌다.
                Text(
                  '지도 보기',
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

/// 주변 인맥 감지를 켜고 끈다. 설정 화면에 있던 스위치를 여기로 옮겼다
/// (사용자 결정, 2026-08-10) — 켜고 끈 결과가 곧바로 나타나는 화면이 여기다.
///
/// 끄는 것은 위치 이용 동의 철회라 되돌리는 데 다시 동의가 필요하므로,
/// 설정 화면과 똑같이 확인 절차를 거친다.
Future<void> _toggleNearbyDetect(
  BuildContext context,
  RadarViewModel viewModel,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!viewModel.hasLocationConsent) {
    await viewModel.acceptLocationConsent();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('주변 인맥 감지를 켰습니다.'),
        backgroundColor: AppColors.accent,
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('주변 인맥 감지를 끌까요?'),
      content: const Text('위치 이용 동의를 철회합니다. 끄면 주변 인맥과의 거리를 볼 수 없습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text(
            '끄기',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await viewModel.withdrawLocationConsent();
  messenger.showSnackBar(
    const SnackBar(
      content: Text('주변 인맥 감지를 중지했습니다.'),
      backgroundColor: AppColors.accent,
    ),
  );
}

/// 내 위치 갱신 버튼. 반경·지도 버튼과 같은 줄 맨 앞에 놓는다.
///
/// 예전에는 "위치는 사용 중에만 확인해요" 안내 줄 오른쪽에 붙어 있었고, 그
/// 줄이 화면 하나를 통째로 차지했다. 안내 문구를 빼고 아이콘만 남긴다
/// (사용자 결정, 2026-08-10).
class _RefreshLocationButton extends StatelessWidget {
  final bool isRefreshing;
  final bool usingRealGps;

  /// 주변 인맥 감지(위치 이용 동의)가 켜져 있는가.
  final bool isDetecting;
  final VoidCallback onTap;

  /// 길게 눌렀을 때 감지를 켜고 끈다.
  final VoidCallback onToggleDetect;

  const _RefreshLocationButton({
    required this.isRefreshing,
    required this.usingRealGps,
    required this.isDetecting,
    required this.onTap,
    required this.onToggleDetect,
  });

  @override
  Widget build(BuildContext context) {
    // 위치를 못 잡은 상태에서는 "설정하러 가기"가 되므로 문구를 나눈다 —
    // 같은 아이콘이라도 무엇이 일어날지는 상태마다 다르다.
    final tooltip = isRefreshing
        ? 'GPS 확인 중...'
        : usingRealGps
        ? '내 위치 갱신 · 길게 누르면 감지 끄기'
        : isDetecting
        ? '위치 설정 · 길게 누르면 감지 끄기'
        : '길게 눌러 주변 인맥 감지 켜기';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: AppColors.cardSurface,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: isRefreshing ? null : onTap,
            // 짧게 누르면 갱신, 길게 누르면 감지 켜기/끄기(사용자 결정,
            // 2026-08-10). 아이콘 하나에 두 동작을 얹는 대신 갱신 경로를
            // 없애는 안도 있었으나, 갱신은 자주 쓰는 동작이라 남겼다.
            onLongPress: isRefreshing ? null : onToggleDetect,
            customBorder: const CircleBorder(),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderFunctional),
              ),
              child: isRefreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentText,
                      ),
                    )
                  : Icon(
                      // 감지가 꺼져 있으면 회색으로 — 눌러도 주변 인맥이 안
                      // 뜨는 이유를 아이콘만 보고 알 수 있어야 한다.
                      isDetecting ? Icons.my_location : Icons.location_disabled,
                      color: isDetecting
                          ? AppColors.accentText
                          : AppColors.textMuted,
                      size: 17,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "가까운 인맥" 목록의 한 줄. 명함 지갑 목록과 같은 구성을 쓴다.
///
/// 같은 인맥을 두 화면에서 다른 모양으로 보여 줄 이유가 없어 형태를 맞췄다
/// (사용자 요청, 2026-08-10). 다만 이 화면에는 **근접 거리**가 더 붙는다 —
/// "지금 얼마나 가까운가"가 이 화면의 존재 이유다.
class _NearbyContactTile extends StatelessWidget {
  final ContactModel contact;
  final double distanceMeters;
  final VoidCallback onOpen;
  final VoidCallback onCall;

  const _NearbyContactTile({
    required this.contact,
    required this.distanceMeters,
    required this.onOpen,
    required this.onCall,
  });

  bool get _hasAnyPhone =>
      contact.phone.trim().isNotEmpty ||
      (contact.officePhone?.trim().isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      onTap: onOpen,
      child: Row(
        children: [
          ContactAvatar(
            photoPath: contact.avatarUrl,
            name: contact.name,
            radius: 22,
            cardImagePath: contact.useCardAsAvatar
                ? contact.cardImagePath
                : null,
            uid: contact.useCardAsAvatar
                ? context.read<AuthRepository>().firebaseUid
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (contact.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    contact.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.company.trim().isEmpty
                            ? '회사 정보 없음'
                            : contact.company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 근접 거리 배지. 회사명 옆에 붙여 이름 줄을 밀지 않는다.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${GeoUtils.formatDistanceLabel(distanceMeters)} 근접',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 명함 지갑과 같은 촘촘한 동작 버튼. 전화번호가 없으면 통화는
          // 비활성 — 눌러도 아무 일이 없는 것보다 낫다.
          IconButton(
            tooltip: '${contact.name}에게 전화',
            onPressed: _hasAnyPhone ? onCall : null,
            icon: AppIcon(
              AppIconId.call,
              size: 20,
              color: _hasAnyPhone ? AppColors.accentText : AppColors.textMuted,
            ),
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          ),
          IconButton(
            tooltip: '${contact.name} AI 대화 가이드',
            onPressed: onOpen,
            icon: const Icon(
              Icons.auto_awesome,
              size: 20,
              color: AppColors.accentText,
            ),
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          ),
        ],
      ),
    );
  }
}
