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
// 주변에서 못 찾은 검색을 명함 지갑(전체 검색)으로 이어 주기 위해 탭 통로를 쓴다.
import '../../../navigation/main_tab_screen.dart';
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

  /// 검색 입력칸. 지우기(X) 버튼을 두려면 컨트롤러가 있어야 한다 —
  /// 예전에는 `onChanged`만 있어서 **입력한 글자를 한 자씩 지워야 했다**
  /// (테스터 빌드6 피드백, backlog B6-01). 관리자 문의 화면엔 이미 있는데
  /// 여기만 빠져 있었다.
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                          image: AssetImage('assets/images/brand/splash.png'),
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
                                  // 제목과 인사말이 붙어 있어 머리글이 한
                                  // 덩어리로 뭉쳐 보였다. 줄 간격을 벌리고
                                  // 인사말을 한 단계 키워 위쪽에 숨 쉴 자리를
                                  // 만든다 — 그만큼 아래 카드가 내려가
                                  // "가까운 인맥" 쪽으로 붙는다(사용자 요청,
                                  // 2026-08-10).
                                  const SizedBox(height: 6),
                                  Text(
                                    _greetingForNow(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
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
                          spacing: 6,
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
                            RadiusSelector(
                              radiusMeters: viewModel.settings.radiusMeters,
                              onChanged: viewModel.updateRadius,
                            ),
                            // 남은 AI 생성 횟수(탭하면 상세). 제목 아래 →
                            // 위치 줄을 거쳐 반경 칩 옆으로 옮겼다(사용자
                            // 요청, 2026-08-10). 셋 다 "이 화면을 어떻게 쓸
                            // 것인가"를 정하는 칩이라 한 줄에 모인다.
                            //
                            // 서비스 미배포·미조회 시에는 스스로 아무것도
                            // 그리지 않으므로 줄이 비어 보이지 않는다.
                            const AiUsageChip(),
                          ],
                        ),
                        const SizedBox(height: 14),

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
                          // 사용자 요청으로 10% 키운다(40 → 44, 2026-08-10).
                          // 앞서 15% 줄였다가 조금 낮다는 판단이라 되돌리는
                          // 셈이다. 44는 iOS 최소 터치 목표와도 맞는다.
                          constraints: const BoxConstraints(minHeight: 44),
                          decoration: BoxDecoration(
                            color: AppColors.capsuleInputBg,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (value) {
                                    viewModel.setSearchTerm(value);
                                    // 지우기 버튼이 나타나고 사라지는 것만
                                    // 반영하면 되므로 값 자체는 뷰모델이 갖는다.
                                    setState(() {});
                                  },
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
                                      vertical: 6,
                                    ),
                                    border: InputBorder.none,
                                    // 이 검색은 **주변 목록 안에서만** 걸러낸다.
                                    // 예전 문구('이름, 회사명, 키워드로 검색해
                                    // 보세요')는 명함 전체를 찾는다고 오해하게
                                    // 만들었고, 주변에 아무도 없을 때 결과가 0인
                                    // 것을 "검색이 고장났다"고 느끼게 했다
                                    // (테스터 E-07). 범위를 문구에 밝힌다.
                                    hintText: '주변 인맥 중에서 검색',
                                    hintStyle: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              if (_searchController.text.isNotEmpty)
                                Semantics(
                                  button: true,
                                  label: '검색어 지우기',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: () {
                                      _searchController.clear();
                                      viewModel.setSearchTerm('');
                                      setState(() {});
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.close,
                                        color: AppColors.textMuted,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                )
                              else
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
                          ],
                        ),

                        const SizedBox(height: 10),

                        // 가장 가까운 한 명을 큰 대표 카드로 따로 보여 주던
                        // 것을 없앴다(사용자 요청, 2026-08-10). 같은 사람이
                        // 카드와 목록 두 곳에 다른 모양으로 나타나 "왜 저
                        // 사람만 다른가"를 설명해야 했고, 대표 카드가 화면
                        // 절반을 먹어 정작 목록은 스크롤해야 보였다.
                        // 이제 **가장 가까운 사람도 목록의 첫 줄**로 들어간다.
                        // 비어 있을 때 **왜 비었는지**를 밝힌다. 예전에는 이유와
                        // 상관없이 같은 문구뿐이라, 위치를 못 잡은 것인지 검색어와
                        // 맞는 사람이 없는 것인지 구분할 수 없었다 — 그래서 QA도
                        // "빈 화면"을 정상으로 넘겼고 테스터는 "검색이 안 된다"고
                        // 느꼈다(E-07).
                        if (viewModel.filteredContacts.isEmpty)
                          _NearbyEmptyState(
                            hasLocation: viewModel.currentPosition != null,
                            usingRealGps: viewModel.usingRealGps,
                            searchTerm: viewModel.searchTerm,
                            radiusIsUnlimited:
                                viewModel.settings.radiusMeters.isInfinite,
                            onOpenWallet: _openWalletTab,
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

  /// 명함 지갑 탭으로 보낸다. 주변 검색은 '지금 주변에 있는 인맥'만 대상으로
  /// 하므로, 전체에서 찾고 싶을 때 갈 곳을 말로만 알려 주지 않고 실제로 연다.
  void _openWalletTab() {
    MainTabScreen.openTab(MainTabScreen.walletTabIndex);
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
          // 배경이 사진처럼 바뀌면서 카드 경계가 페이지 배경에 묻혀 흐릿해
          // 보였다(사용자 보고). 또렷한 테두리로 경계를 세운다.
          border: Border.all(color: AppColors.borderFunctional),
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
              // 사용자가 준 지도 일러스트를 배경으로 깐다(2026-08-10).
              // **실제 지도 타일이 아니라 앱에 번들한 그림**이다 — 홈 화면에
              // 진짜 지도를 깔면 앱을 켤 때마다 지도 사업자에게 요청이 나가는데,
              // 개인정보처리방침 10-3이 "지도 화면을 열지 않으면 어떤 요청도
              // 발생하지 않는다"고 적고 있다. 그림이면 요청이 아예 없다.
              const Positioned.fill(
                child: ExcludeSemantics(
                  child: Image(
                    image: AssetImage('assets/images/nearby/map.jpg'),
                    fit: BoxFit.cover,
                    // 카드가 가로로 길어 정사각형 원본의 가운데 위쪽을 쓴다 —
                    // 그림 한가운데의 파란 현위치 점이 살아 있어야 "지금 내
                    // 주변"이라는 뜻이 전달된다.
                    alignment: Alignment.center,
                  ),
                ),
              ),
              // 글자가 얹히는 자리만 흰 막으로 덮어 대비를 지킨다.
              //
              // 처음에는 카드 전체에 55% 막을 씌웠는데 지도가 통째로 흐려
              // 보였다(사용자 보고, 2026-08-10). 막을 옅게(22%) 하되, 글자가
              // 실제로 놓이는 **아래쪽에만** 흰색이 짙어지는 그라데이션을
              // 얹는다 — 지도는 선명하게 남고 글자 대비는 지켜진다.
              Positioned.fill(
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.22),
                          Colors.white.withValues(alpha: 0.62),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                // 대표 카드를 없앤 자리를 이 카드가 대신한다(사용자 요청,
                // 2026-08-10). 여백과 아이콘·숫자를 키워 예전 대표 카드와
                // 비슷한 덩치를 갖게 했다 — 화면 위쪽이 허전해지지 않도록.
                // 카드를 "가까운 인맥" 목록 바로 앞까지 키운다(사용자 요청,
                // 2026-08-10). 대표 카드를 없앤 자리가 이 카드로 온전히
                // 채워지도록 세로 여백을 크게 잡았다.
                // ⚠️ 가로 여백을 31까지 키웠더니 iPhone(논리 폭 393)에서
                // "지금 가까운 사람"이 두 줄로 깨졌다(사용자 캡처, 2026-08-10).
                // 세로는 그대로 두고 **가로만** 줄여 라벨 폭을 되찾는다.
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 68,
                ),
                child: Row(
                  children: [
                    // 흰 원 안의 레이더 아이콘은 뺐다(사용자 요청,
                    // 2026-08-10). 배경 지도 그림 한가운데에 이미 파란 현위치
                    // 점이 있어 같은 뜻을 두 번 그리고 있었고, 흰 원이 지도를
                    // 가려 배경을 넣은 의미도 반감됐다.
                    //
                    // 위치를 새로 읽는 중일 때만 진행 표시기를 띄운다 —
                    // 이건 상태를 알리는 것이라 지도 그림이 대신할 수 없다.
                    if (isRefreshing) ...[
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // 라벨은 왼쪽, 숫자는 오른쪽 끝(사용자 요청, 2026-08-10). 예전에는
                    // 둘이 왼쪽에 붙어 있어 카드 오른쪽 절반이 통째로 비어 있었다.
                    const Expanded(
                      child: Text(
                        '지금 가까운 사람',
                        // 폭이 모자라도 **두 줄로 깨지지 않게** 한 줄로 못박고,
                        // 정 안 들어가면 줄여서 그린다. 두 줄로 접히면 카드
                        // 높이까지 흔들려 아래 요소가 밀린다.
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      count != null ? '$count명' : '--',
                      style: const TextStyle(
                        fontSize: 34,
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
/// 주변 목록이 비었을 때 **왜 비었는지**와 다음에 할 일을 알려 준다.
///
/// 예전에는 이유와 상관없이 한 문장뿐이라, 위치를 못 잡은 것인지 검색어에
/// 맞는 사람이 없는 것인지 구분할 수 없었다. 그래서 테스터는 "검색 기능이
/// 작동하지 않는다"(E-07)고 느꼈고, QA도 빈 화면을 정상으로 넘겼다.
class _NearbyEmptyState extends StatelessWidget {
  final bool hasLocation;
  final bool usingRealGps;
  final String searchTerm;
  final bool radiusIsUnlimited;
  final VoidCallback onOpenWallet;

  const _NearbyEmptyState({
    required this.hasLocation,
    required this.usingRealGps,
    required this.searchTerm,
    required this.radiusIsUnlimited,
    required this.onOpenWallet,
  });

  @override
  Widget build(BuildContext context) {
    final query = searchTerm.trim();
    final String title;
    String? hint;
    var showWalletButton = false;

    if (!hasLocation) {
      // 위치가 없으면 반경·검색어와 무관하게 목록이 비게 된다. 이 경우를 먼저
      // 가려내지 않으면 "검색이 안 된다"는 오해가 그대로 남는다.
      title = usingRealGps ? '현재 위치를 확인하지 못했어요' : '위치 권한이 없어 주변 인맥을 찾을 수 없어요';
      hint = usingRealGps
          ? '위의 위치 아이콘을 눌러 다시 시도해 보세요.'
          : '위의 위치 아이콘을 눌러 위치 사용을 허용해 주세요.';
    } else if (query.isNotEmpty) {
      title = '‘$query’와 일치하는 주변 인맥이 없어요';
      hint = '이 검색은 지금 주변에 있는 인맥만 찾아요. 전체 명함에서 찾으려면 명함 지갑을 이용해 주세요.';
      showWalletButton = true;
    } else {
      title = '주변에 감지된 인맥이 없어요';
      hint = radiusIsUnlimited
          // 반경이 이미 '전체'인데도 비었다면 남는 이유는 좌표뿐이다.
          ? '주소가 없거나 위치를 찾지 못한 명함은 주변에 표시되지 않아요.'
          : '반경을 넓히면 더 멀리 있는 인맥까지 볼 수 있어요.';
    }

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (showWalletButton) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenWallet,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('명함 지갑에서 전체 검색'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentText,
                side: const BorderSide(color: AppColors.accentText),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 감지 반경 선택 칩. 주변 화면과 **지도 화면이 함께 쓴다**(사용자 요청,
/// 2026-08-12) — 지도에서 반경 원을 보다가 바로 바꾸고 싶다는 요구라, 옵션
/// 목록·라벨·선택 시트를 한 곳에 두고 양쪽이 같은 것을 쓰게 한다.
class RadiusSelector extends StatelessWidget {
  final double radiusMeters;
  final ValueChanged<double> onChanged;

  const RadiusSelector({
    super.key,
    required this.radiusMeters,
    required this.onChanged,
  });

  /// 3km·5km는 사용자 요청으로 추가했다(추가 139). 도보권(500m)과 같은 동네
  /// (1km) 사이만으로는 "차로 잠깐 가는 거리"를 담을 수 없었다.
  static const options = <double>[500, 1000, 3000, 5000, double.infinity];

  /// 칩에 넣을 짧은 라벨. "제한 없음"은 이 줄에서 가장 긴 문구라 **전체**로
  /// 줄였다 — 지도·반경·잔여 횟수 세 칩이 한 줄에 안 들어가 잔여 칩이 아랫줄로
  /// 밀렸다(사용자 보고, 2026-08-10). 선택 시트 안에서는 뜻이 분명해야 하므로
  /// [sheetLabel]로 원래 문구를 그대로 쓴다.
  static String label(double meters) {
    if (meters.isInfinite) return '전체';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(0)}km';
  }

  static String sheetLabel(double meters) {
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.expand_more,
                size: 16,
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
      // 내용이 화면 높이를 넘으면 **잘리지 않고 스크롤되게** 한다.
      //
      // 예전에는 고정 높이라 마지막 항목("제한 없음")이 5픽셀 넘쳐 오버플로
      // 줄무늬에 가려졌다(2026-08-14 실기기 제보). 5픽셀이라 "거의 맞는" 상태로
      // 보이지만, 글자 크기를 키운 기기나 항목이 하나만 더 늘어도 그대로
      // 깨진다 — 여유를 두는 대신 스크롤이 되게 고쳤다.
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
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
                    title: Text(sheetLabel(option)),
                    trailing: radiusMeters == option
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.accent,
                          )
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                // 반경·잔여 칩과 한 줄에 들어가야 해서 "지도에서 크게 보기"를
                // 두 번에 걸쳐 줄였다. 아이콘이 함께 있어 뜻은 읽힌다.
                Text(
                  '지도',
                  style: TextStyle(
                    fontSize: 12,
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
                Text(
                  contact.company.trim().isEmpty ? '회사 정보 없음' : contact.company,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // 오른쪽 묶음: 위에 동작 버튼, 아래에 근접 거리.
          //
          // 거리 배지를 본문 칼럼(회사명 줄) 안에 두었더니 **동작 버튼 폭만큼
          // 안쪽에서 끝났다.** 사용자가 "위줄 AI 가이드 아이콘처럼 우측부터
          // 채워 달라"고 한 지점이다(2026-08-10). 버튼과 같은 묶음으로 옮겨
          // 두 줄의 오른쪽 끝이 맞는다.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 명함 지갑과 같은 촘촘한 동작 버튼. 전화번호가 없으면
                  // 통화는 비활성 — 눌러도 아무 일이 없는 것보다 낫다.
                  IconButton(
                    tooltip: '${contact.name}에게 전화',
                    onPressed: _hasAnyPhone ? onCall : null,
                    icon: AppIcon(
                      AppIconId.call,
                      size: 20,
                      color: _hasAnyPhone
                          ? AppColors.accentText
                          : AppColors.textMuted,
                    ),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 36,
                    ),
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
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 36,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    // `formatDistanceLabel`이 이미 "근접"까지 붙여 준다.
                    // 여기서 한 번 더 붙여 "823m 근접 근접"이 됐었다.
                    GeoUtils.formatDistanceLabel(distanceMeters),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accentText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
