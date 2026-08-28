import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../common/call_picker_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/address_grouping.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/ai_usage_chip.dart';
import '../../../common/collapsing_list_header.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../../../common/same_address_group_header.dart';
// 주변에서 못 찾은 검색을 명함 지갑(전체 검색)으로 이어 주기 위해 탭 통로를 쓴다.
import '../../../navigation/main_tab_screen.dart';
import '../view_models/radar_view_model.dart';
import 'my_profile_edit_modal_view.dart';
import 'nearby_map_card.dart';
import 'qr_code_modal_view.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import '../../wallet/views/add_card_modal_view.dart';
import 'location_consent_sheet.dart';
import 'location_access_flow.dart';
import 'nearby_map_view.dart';
import 'reconnect_today_section.dart';

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

  // 목록 상단 고정(UI 개선 ⑦, 2026-08-21). 큰 제목·지도 카드는 접어 흘려보내고
  // 축약 제목+반경·지도 칩+검색창은 화면 위에 고정한다 — 판정 로직은 지갑
  // 화면과 같은 공용 [HeaderCollapseTracker]를 쓴다(브리프 ⑦ 순서표대로 지갑이
  // 먼저 만든 컴포넌트를 그대로 재사용).
  final HeaderCollapseTracker _headerTracker = HeaderCollapseTracker();

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

    // F-11: 검색 중에는 화면을 **결과 전용**으로 바꾼다.
    //
    // 검색창이 화면 위쪽에 있는데도, 그 아래 "지금 가까운 사람 N명" 카드와
    // 위치 조작 줄이 자리를 차지해 **정작 결과는 스크롤해야 보였다.** 둘 다
    // "지금 내 주변이 어떤가"를 알려 주는 것들이라 검색 중에는 답이 아니다 —
    // 그때 사용자가 보려는 것은 "찾는 사람이 여기 있나" 하나뿐이다.
    final isSearching = viewModel.searchTerm.trim().isNotEmpty;

    // 검색으로 결과가 다 걸러지면 스크롤할 내용이 거의 안 남는다 — 접힌
    // 채로 그렇게 되면 큰 제목·지도 카드로 돌아갈 방법이 없어진다(지갑
    // 화면의 "목록이 검색으로 다 걸러지면 접힌 채로 남지 않는다"와 같은
    // 이유로 강제로 편다).
    if (isSearching && nearbyList.isEmpty) _headerTracker.reset();
    final headerCollapsed = (isSearching && nearbyList.isEmpty)
        ? false
        : _headerTracker.collapsed;

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
                  child: Column(
                    children: [
                      // 목록 상단 고정(UI 개선 ⑦). 맨 위에서는 지금까지와
                      // 같은 큰 제목이 보이고, 스크롤하면 축약 제목+반경·지도
                      // 칩+검색창만 남아 화면 위에 고정된다.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                        child: CollapsingListHeader(
                          collapsed: headerCollapsed,
                          expandedTop: _buildExpandedTop(
                            context,
                            viewModel,
                            isSearching,
                          ),
                          collapsedTop: _buildCollapsedTop(
                            context,
                            viewModel,
                            nearbyCount,
                          ),
                          pinnedTools: _buildPinnedTools(
                            context,
                            viewModel,
                            headerCollapsed,
                          ),
                        ),
                      ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (_headerTracker.update(
                              notification.metrics.pixels,
                            )) {
                              setState(() {});
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            // ⚠️ 2026-08-28 하루 동안 이 값이 24 → 80 → 96 →
                            // (지금) 24로 왔다갔다 했다 — 전부 명함 등록
                            // FAB(하단에 떠서 이 스크롤 영역 위를 가리던)
                            // 때문이었다. 지금은 FAB이 없고 탭 바
                            // 목적지("등록")로 바뀌었다 — 탭 바는
                            // `Scaffold.bottomNavigationBar`라 body(이 스크롤
                            // 영역)와 자리를 나눠 쓸 뿐 위에 겹쳐 뜨지 않으므로,
                            // 마지막 카드를 가릴 것이 없다. 원래 값(24)으로
                            // 되돌린다(wallet_view.dart와 같은 값·같은 근거).
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (viewModel.locationAccessState !=
                                    LocationAccessState.ready) ...[
                                  _LocationStatusCard(
                                    viewModel: viewModel,
                                    onAction: () => handleLocationAccessAction(
                                      context,
                                      viewModel,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],

                                // 새 기기에서 복원한 직후에는 명함 좌표가
                                // 없어 거리 계산이 안 된다(좌표는 서버에
                                // 백업하지 않고 주소로 다시 계산한다 —
                                // backlog 추가 75). 그동안 "주변에 아무도
                                // 없음"으로 보이면 오해를 사므로 준비 중임을
                                // 알린다.
                                // 앱을 처음 깔면 내 명함이 없는데 화면
                                // 어디에도 그걸 알리는 표시가 없어서, 무엇을
                                // 먼저 해야 하는지 알 수 없었다(실사용
                                // 피드백). 위치 안내보다 아래, 인맥 목록보다
                                // 위에 둬서 "권한 → 내 명함 → 인맥"이라는
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

                                // 지도에서 기준점을 옮겨 뒀으면 그 사실을
                                // 알린다(F-13).
                                //
                                // ⚠️ 이 줄은 **검색 중에도 남긴다.** 아래
                                // F-11 분기가 감추는 것은 "지금 내 주변이
                                // 어떤가"를 말하는 조작 줄이지, **"지금
                                // 무엇을 기준으로 잰 거리인가"가 아니다.**
                                // 이걸 같이 감추면 검색 결과의 거리가 내
                                // 위치 기준이 아닌데 그 사실을 알 길이
                                // 없어져, F-11이 깨진 것처럼 보이는 결함으로
                                // 접수된다.
                                if (viewModel.isUsingCustomAnchor) ...[
                                  _AnchorNoticeBar(
                                    onReset: viewModel.clearAnchor,
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // 내 위치가 얼마나 믿을 만한지 알린다(E-12).
                                //
                                // ⚠️ 기준점 안내와 같은 이유로 **검색 중에도
                                // 남긴다** — 이것도 "지금 무엇을 기준으로 잰
                                // 거리인가"에 관한 정보다. 알릴 것이 없으면
                                // 뷰모델이 null을 주므로 줄 자체가 안
                                // 생긴다(억지로 채우지 않는다).
                                if (viewModel.locationQualityMessage !=
                                    null) ...[
                                  _LocationQualityBar(
                                    message: viewModel.locationQualityMessage!,
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // 검색 중에는 이 섹션들을 감춘다(F-11) —
                                // 전부 "지금 내 주변이 어떤가"를 말하는
                                // 것이라 검색 결과를 밀어낼 이유가 없다.
                                if (!isSearching) ...[
                                  // F-10 A — "오늘 연락하면 좋은 사람".
                                  //
                                  // 왜 여기(위치 카드보다 위)인가: 이 섹션은
                                  // 앱을 매일 여는 이유고, 나머지는 "지금
                                  // 주변이 어떤가"다. 아래에 두면 주변에
                                  // 아무도 없는 날(대부분의 날)에는 스크롤
                                  // 해야 보이는데, 그러면 매일 열 이유가
                                  // 안 된다.
                                  //
                                  // 위치와 무관하게 뜬다 — GPS를 못 잡아도
                                  // "누굴 까먹었나"에는 답할 수 있다.
                                  // 후보가 없으면 섹션 자체가 사라진다
                                  // (억지로 채우지 않는다).
                                  ReconnectTodaySection(
                                    candidates: viewModel.reconnectCandidates,
                                    onOpenGuide: viewModel.openBriefing,
                                    onSnooze: viewModel.snoozeReconnect,
                                  ),

                                  const SizedBox(height: 16),

                                  // 주변 홈 지도 카드(⑥-C, 2026-08-21
                                  // 확정). 예전 "지금 가까운 사람 N명"
                                  // 카드(map.jpg 배경)를 대신한다 — 실제
                                  // 근처 인맥을 거리·방위 기준으로 배치한
                                  // 지도풍 그래픽. 카드 자체를 탭하면
                                  // 예전과 같은 동작(위치 새로고침)을 하고,
                                  // 실제 지도 화면은 카드 안 "지도로 보기"
                                  // 버튼으로 연다.
                                  NearbyMapCard(
                                    locationAccessState:
                                        viewModel.locationAccessState,
                                    origin: viewModel.referencePosition,
                                    contactsSortedByDistance: nearbyList,
                                    radiusMeters:
                                        viewModel.settings.radiusMeters,
                                    isRefreshing:
                                        viewModel.isRefreshingLocation,
                                    onTap: () => handleLocationAccessAction(
                                      context,
                                      viewModel,
                                    ),
                                    onOpenMap: () =>
                                        NearbyMapView.show(context),
                                  ),

                                  const SizedBox(height: 8),

                                  // 위치 아이콘과 조작 안내를 지도 카드
                                  // 바로 아래 한 줄에 둔다(사용자 요청,
                                  // 2026-08-10). 아이콘이 무엇을 켜고
                                  // 끄는지가 그 카드의 숫자이므로, 상단
                                  // 버튼 줄보다 여기가 가깝다.
                                  //
                                  // 길게 누르기는 눌러 보기 전에는 알 수
                                  // 없는 동작이라 설명을 옆에 붙인다.
                                  // 툴팁만으로는 길게 눌러야 뜨는데, 그
                                  // 자체가 길게 누를 줄 아는 사람에게만
                                  // 보인다.
                                  Row(
                                    children: [
                                      _RefreshLocationButton(
                                        isRefreshing:
                                            viewModel.isRefreshingLocation,
                                        usingRealGps: viewModel.usingRealGps,
                                        isDetecting:
                                            viewModel.hasLocationConsent,
                                        onTap: () =>
                                            handleLocationAccessAction(
                                              context,
                                              viewModel,
                                            ),
                                        onToggleDetect: () =>
                                            _toggleNearbyDetect(
                                              context,
                                              viewModel,
                                            ),
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
                                ],

                                // 가장 가까운 한 명을 큰 대표 카드로 따로
                                // 보여 주던 것을 없앴다(사용자 요청,
                                // 2026-08-10). 같은 사람이 카드와 목록 두
                                // 곳에 다른 모양으로 나타나 "왜 저 사람만
                                // 다른가"를 설명해야 했고, 대표 카드가
                                // 화면 절반을 먹어 정작 목록은 스크롤해야
                                // 보였다. 이제 **가장 가까운 사람도 목록의
                                // 첫 줄**로 들어간다.
                                // 비어 있을 때 **왜 비었는지**를 밝힌다.
                                // 예전에는 이유와 상관없이 같은 문구뿐이라,
                                // 위치를 못 잡은 것인지 검색어와 맞는
                                // 사람이 없는 것인지 구분할 수 없었다 —
                                // 그래서 QA도 "빈 화면"을 정상으로 넘겼고
                                // 테스터는 "검색이 안 된다"고 느꼈다
                                // (E-07).
                                if (viewModel.filteredContacts.isEmpty)
                                  _NearbyEmptyState(
                                    hasLocation:
                                        viewModel.currentPosition != null,
                                    usingRealGps: viewModel.usingRealGps,
                                    searchTerm: viewModel.searchTerm,
                                    radiusIsUnlimited: viewModel
                                        .settings
                                        .radiusMeters
                                        .isInfinite,
                                    onOpenWallet: _openWalletTab,
                                  ),

                                const SizedBox(height: 16),

                                // 목록 제목도 화면의 성격을 따라간다(F-11)
                                // — 같은 목록이라도 검색 중에는 "주변에
                                // 있는 사람들"이 아니라 "찾은 결과"다.
                                // 제목이 그대로면 사용자는 걸러진 목록을
                                // 전체 목록으로 오해한다.
                                Text(
                                  isSearching
                                      ? '검색 결과 (${nearbyList.length}명)'
                                      : '가까운 인맥 (${nearbyList.length}명)',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // 명함 지갑 목록과 같은 형태로 맞춘다(사용자
                                // 요청, 2026-08-10) — 이름/직함/회사명 세 줄,
                                // 아바타 왼쪽, 오른쪽에 동작 버튼. 같은
                                // 인맥을 두 화면에서 다른 모양으로 보여 줄
                                // 이유가 없다.
                                //
                                // 다른 점 하나: 여기에는 **근접 거리**가
                                // 함께 붙는다. 이 화면의 존재 이유가 "지금
                                // 얼마나 가까운가"이므로 목록에서도 그 값이
                                // 보여야 한다.
                                // 같은 주소에 여러 명이 있으면 묶어서
                                // 보여 준다(F-15). 한 건물에 3명이 있는데
                                // 같은 거리가 세 줄 나열되면, 사용자가 그걸
                                // 스스로 세어야 한다. 묶음 머리글은 2명
                                // 이상일 때만 붙인다 — 1명짜리 머리글은
                                // 아무 정보도 주지 않는다.
                                ...groupContactsByAddress(nearbyList).expand((
                                  group,
                                ) {
                                  final tiles = group.contacts.map((contact) {
                                    // 내 위치가 아니라 기준점에서
                                    // 잰다(F-13). 목록 정렬도 같은 기준을
                                    // 쓰므로(뷰모델), 여기만 내 위치로
                                    // 재면 "거리는 커지는데 순서는 그대로"
                                    // 인 목록이 된다.
                                    final distance = GeoUtils.getDistanceMeters(
                                      viewModel.referencePosition,
                                      contact.geo,
                                    );
                                    return _NearbyContactTile(
                                      contact: contact,
                                      distanceMeters: distance,
                                      // 묶음 안에서는 주소를 줄마다
                                      // 반복하지 않는다 — 머리글에 이미
                                      // 있고, 같은 값이 세 번 나오면
                                      // 오히려 읽기 어렵다.
                                      showAddress: !group.isGrouped,
                                      onOpen: () =>
                                          viewModel.openBriefing(contact),
                                      onCall: () =>
                                          showCallPicker(
                                            context,
                                            contact,
                                          ),
                                    );
                                  });
                                  if (!group.isGrouped) return tiles;
                                  // 머리글만으로는 묶음이 "닫히지" 않는다 —
                                  // 아래로 이어지는 낱개 카드까지 묶음으로
                                  // 읽힌다. 그래서 속한 카드들을 들여쓰기 +
                                  // 왼쪽 세로선으로 감싼다(추가 313,
                                  // 실기기에서 "2명" 밑에 5장이 이어져
                                  // 보였다).
                                  return [
                                    SameAddressGroupHeader(
                                      address: group.address,
                                      count: group.contacts.length,
                                    ),
                                    SameAddressGroupBody(
                                      children: tiles.toList(),
                                    ),
                                  ];
                                }),

                                // ⭐ 좌표가 없어 반경 목록에 못 드는 명함을
                                // **지역별로** 이어서 보여 준다.
                                //
                                // 반경 목록은 좌표로 거르기 때문에, 좌표를
                                // 못 얻은 명함은 화면에서 **조용히
                                // 사라진다**(추가 79에서 실기기로 겪었다).
                                // 이용자는 등록한 명함이 왜 안 보이는지
                                // 알 수 없다.
                                //
                                // 📌 실측(2026-08-21): 등록 93건 중 좌표를
                                // 못 얻은 30건 **전부** 주소에서 구까지
                                // 뽑혔다.
                                //
                                // ⚠️ 거리 목록과 **섞지 않는다.** 위는
                                // "몇 m"이고 여기는 "같은 구"라, 한 목록에
                                // 섞으면 순서가 거짓이 된다.
                                if (viewModel.contactsWithoutGeoCount >
                                    0) ...[
                                  const SizedBox(height: 24),
                                  _RegionSectionHeader(
                                    count: viewModel.contactsWithoutGeoCount,
                                  ),
                                  const SizedBox(height: 8),
                                  ...viewModel.contactsByRegionWithoutGeo
                                      .expand(
                                        (entry) => [
                                          SameAddressGroupHeader(
                                            address: entry.key,
                                            count: entry.value.length,
                                          ),
                                          SameAddressGroupBody(
                                            children: entry.value
                                                .map(
                                                  (contact) =>
                                                      _NearbyContactTile(
                                                        contact: contact,
                                                        // ⚠️ 거리를 넣지
                                                        // 않는다. 좌표가
                                                        // 없어 잴 수가
                                                        // 없고, 0이나 빈
                                                        // 값을 넣으면
                                                        // "아주 가깝다"로
                                                        // 읽힌다.
                                                        distanceMeters: null,
                                                        showAddress: true,
                                                        onOpen: () => viewModel
                                                            .openBriefing(
                                                              contact,
                                                            ),
                                                        onCall: () =>
                                                            showCallPicker(
                                                              context,
                                                              contact,
                                                            ),
                                                      ),
                                                )
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Full Screen 30-Second AI Briefing Overlay
        //
        // 이 오버레이는 별도 Route가 아니라 주변 화면과 같은 Route 위에
        // Stack으로 얹힌 것이라, 뒤로가기를 여기서 막지 않으면 같은 Route에
        // 있는 MainTabScreen의 루트 뒤로가기 처리(추가 437)가 같이 반응해
        // 오버레이가 닫히면서 동시에 탭 전환/종료 안내까지 겹쳐 뜬다.
        // PopScope로 여기서 먼저 막고 오버레이만 닫는다.
        if (viewModel.selectedContactForBriefing != null)
          PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              viewModel.closeBriefing();
            },
            child: BriefingOverlayView(
              contact: viewModel.selectedContactForBriefing!,
              onClose: viewModel.closeBriefing,
            ),
          ),
      ],
    );
  }

  /// 스크롤 맨 위에서만 보이는 큰 제목 블록 — 큰 제목("주변 인맥")과 인사말/
  /// 검색 문구, QR 스캔 버튼. 브리프 ⑦ 표에서 "흘려보냄"으로 지정한 두
  /// 항목 중 하나(나머지 하나인 지도 카드는 스크롤 본문 쪽에서 `!isSearching`
  /// 조건과 함께 그린다 — 검색 중에는 원래도 숨겼던 카드라 이 자리에 두면
  /// 그 규칙과 부딪힌다).
  ///
  /// ⚠️ **"명함 등록" 아이콘은 여기 없다(2026-08-28, globe2030님 결정으로
  /// 제거).** 예전엔 이 자리와 명함 지갑 머리글 오른쪽 위, 두 곳에 자리·
  /// 모양을 맞춰 하나씩 있었다(2026-08-12 결정). globe2030님이 실사용
  /// (하루 아이폰 126장·폴드 190장 등록)에서 "위에 있어서 불편하다"고
  /// 하셨다. 같은 날 하단 FAB(가운데 도킹 → 오른쪽 아래)을 거쳐 지금은
  /// `main_tab_screen.dart`의 하단 탭 바 4번째 목적지("등록") 하나로
  /// 합쳤다 — globe2030님이 처음부터 "탭 바"를 뜻하셨다는 것을 다시
  /// 확인해 주셨다. 설계 근거:
  /// docs/planning/specs/card-add-button-placement-2026-08-28.md.
  /// [context]를 지역 매개변수로 받는다 — `State.context`(게터)를 그대로
  /// 쓰면 분석기가 `await` 뒤 `mounted` 가드를 좁혀 읽지 못해
  /// `use_build_context_synchronously`가 잘못 걸린다(2026-08-22 실측,
  /// `build(BuildContext context)`처럼 지역 매개변수여야 좁혀 읽는다).
  Widget _buildExpandedTop(
    BuildContext context,
    RadarViewModel viewModel,
    bool isSearching,
  ) {
    return Row(
      // 오른쪽 버튼 묶음의 높이가 화면마다 달라도(원형 아이콘 2개 vs 라벨
      // 있는 버튼 등) 제목이 항상 같은 높이에서 시작하도록 맨 위로 고정 —
      // 기본값인 center로 두면 제목이 버튼 높이에 따라 미묘하게 위아래로
      // 밀린다(다른 탭과 비교 시 눈에 띔).
      crossAxisAlignment: CrossAxisAlignment.start,
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
              // 제목과 인사말이 붙어 있어 머리글이 한 덩어리로 뭉쳐 보였다.
              // 줄 간격을 벌리고 인사말을 한 단계 키워 위쪽에 숨 쉴 자리를
              // 만든다 — 그만큼 아래 카드가 내려가 "가까운 인맥" 쪽으로
              // 붙는다(사용자 요청, 2026-08-10).
              const SizedBox(height: 6),
              Text(
                // 검색 중에는 인사말 대신 **무엇을 찾고 있는지**를 보여
                // 준다(F-11). 결과만 보면 어떤 말로 걸러졌는지 알 수 없고,
                // 검색창은 스크롤하면 시야에서 사라진다.
                isSearching
                    ? '"${viewModel.searchTerm.trim()}" 검색 중'
                    : _greetingForNow(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            // "명함 등록" 원형 버튼은 여기 있었다(2026-08-28에 하단 탭 바
            // "등록" 목적지로 옮기며 제거 — 위 문서 주석 참고). 남은 QR
            // 버튼의 40×40 크기 고정은 원래 "옆의 명함등록 버튼과 크기를
            // 맞추려는" 목적이었는데, 그 짝이 없어진 지금도 기본
            // IconButton(48×48)보다 이 화면의 다른 원형 아이콘들과
            // 통일된 크기라 그대로 둔다.
            IconButton(
              tooltip: 'QR 스캔',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.accentSoftStrong,
                shape: const CircleBorder(),
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
                  if (scannedContact == null || !context.mounted) {
                    return;
                  }
                  AddCardModalView.show(context, prefillData: scannedContact);
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 접혔을 때만 보이는 축약 제목 줄 — "주변"+"가까운 N명" 배지에 반경
  /// 칩·지도 버튼을 같은 줄로 흡수한다(브리프 ⑦ 표: "반경 칩·지도 버튼
  /// (제목 줄 흡수)"). 펼친 상태에서는 이 두 칩이 [_buildPinnedTools]의
  /// 별도 줄에 있다가, 접히는 순간 이 줄로 옮겨 붙는 셈이다 — 사라지는 게
  /// 아니라 위치만 바뀐다(브리프의 "고정" 요구를 지킨다).
  Widget _buildCollapsedTop(
    BuildContext context,
    RadarViewModel viewModel,
    int? nearbyCount,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: Text(
                  '주변',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _NearbyCountBadge(count: nearbyCount),
            ],
          ),
        ),
        const SizedBox(width: 6),
        RadiusSelector(
          radiusMeters: viewModel.settings.radiusMeters,
          onChanged: viewModel.updateRadius,
        ),
        const SizedBox(width: 6),
        _ExpandToMapButton(
          enabled: viewModel.usingRealGps,
          onTap: () => NearbyMapView.show(context),
        ),
      ],
    );
  }

  /// 스크롤·접힘과 무관하게 항상 보이는 검색창 — 브리프 표가 "고정"으로
  /// 못박은 유일한 항목이라 조건 없이 늘 그린다.
  ///
  /// 반경 칩·지도 버튼·AI 잔여 횟수 칩은 **펼친 상태에서만** 여기(검색창
  /// 위)에 그린다. 접히면 반경·지도 칩은 [_buildCollapsedTop]의 축약 제목
  /// 줄로 옮겨 붙으므로 여기서 또 그리면 같은 조작이 두 번 보인다 — AI
  /// 잔여 횟수 칩은 브리프 표에 고정으로 지정돼 있지 않아, 접히면 함께
  /// 접어 높이 예산(~150dp)을 지킨다(디자이너 재량).
  Widget _buildPinnedTools(
    BuildContext context,
    RadarViewModel viewModel,
    bool collapsed,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!collapsed) ...[
          const SizedBox(height: 16),
          // `Row`가 아니라 `Wrap`인 이유: 반경이 "제한 없음"일 때 라벨이
          // 가장 길어지는데, 화면이 좁거나 시스템 글자 크기를 키운
          // 기기에서는 세 버튼이 한 줄에 안 들어갈 수 있다. `Row`면 그
          // 상황에서 오버플로 줄무늬가 뜨지만 `Wrap`은 조용히 아랫줄로
          // 내려 준다.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 지도 → 반경 순서(사용자 요청, 2026-08-10). 지도를 먼저
              // 열고 그 안에서 범위를 가늠하는 흐름을 앞세운다.
              _ExpandToMapButton(
                enabled: viewModel.usingRealGps,
                onTap: () => NearbyMapView.show(context),
              ),
              RadiusSelector(
                radiusMeters: viewModel.settings.radiusMeters,
                onChanged: viewModel.updateRadius,
              ),
              // 남은 AI 생성 횟수(탭하면 상세). 서비스 미배포·미조회 시에는
              // 스스로 아무것도 그리지 않으므로 줄이 비어 보이지 않는다.
              const AiUsageChip(),
            ],
          ),
          const SizedBox(height: 14),
        ] else
          const SizedBox(height: 10),
        // Rounded Capsule Search Bar — 근접 인맥 리스트를 이름/회사/직함으로
        // 필터링
        Container(
          // 높이를 약 15% 줄인다(사용자 요청, 2026-08-10). 캡슐 자체의
          // 세로 여백을 없애고 TextField가 스스로 잡는 높이만 남긴다 —
          // 글자 크기는 건드리지 않아 읽기 어려워지지 않는다.
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // 사용자 요청으로 10% 키운다(40 → 44, 2026-08-10). 앞서 15%
          // 줄였다가 조금 낮다는 판단이라 되돌리는 셈이다. 44는 iOS 최소
          // 터치 목표와도 맞는다.
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
                    // 지우기 버튼이 나타나고 사라지는 것만 반영하면 되므로
                    // 값 자체는 뷰모델이 갖는다.
                    setState(() {});
                  },
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.capsuleInputText,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    // 기본 세로 여백(약 8)을 줄여 캡슐 높이를 낮춘다.
                    // 터치는 캡슐 전체가 받으므로 목표 크기는 minHeight
                    // 40으로 지킨다.
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                    // 이 검색은 **주변 목록 안에서만** 걸러낸다. 예전
                    // 문구('이름, 회사명, 키워드로 검색해 보세요')는 명함
                    // 전체를 찾는다고 오해하게 만들었고, 주변에 아무도
                    // 없을 때 결과가 0인 것을 "검색이 고장났다"고 느끼게
                    // 했다(테스터 E-07). 범위를 문구에 밝힌다.
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

/// 접힌 축약 제목 옆의 "가까운 N명" 배지. 명함 지갑의
/// [HeaderCountBadge](숫자만 표시)와 달리 이 화면은 숫자 하나만으로는
/// 무엇을 세는지 알 수 없어(가까운 사람? 전체 인맥?) 문구를 함께 넣는다.
class _NearbyCountBadge extends StatelessWidget {
  const _NearbyCountBadge({required this.count});

  /// 위치를 아직 못 잡았으면 null — 그때는 "0명"이 아니라 "확인 중"이라고
  /// 알려야 한다. 0으로 보이면 "왜 아무도 없지"로 오해한다.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count != null ? '가까운 $count명' : '위치 확인 중',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}

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
                  // "만들어"·"주세요" 사이 띄어쓰기를 붙였다(뜻은 그대로 —
                  // 보조 용언 붙여쓰기도 맞춤법상 허용된다). 좁은 화면에서
                  // 줄바꿈이 나면 이 공백이 끊기는 자리가 돼 "주세요"만 혼자
                  // 둘째 줄에 남는 고아 줄바꿈이 실기기에서 났다(backlog 391).
                  '내 명함을 먼저 만들어주세요',
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
/// "지금 거리 기준이 내 위치가 아니다"를 알리는 줄(F-13).
///
/// 내 위치의 품질을 알리는 줄(E-12).
///
/// ⚠️ **경고가 아니라 안내다.** 빨간색을 쓰지 않는다 — 사용자가 뭘 잘못한 것이
/// 아니고, 대부분 실내라서 생기는 정상적인 일이다. 겁을 주면 위치 기능 자체를
/// 꺼 버린다.
///
/// 되돌릴 버튼을 두지 않는 이유: **사용자가 할 수 있는 일이 없다.** 밖으로
/// 나가거나 기다리면 나아지는데, 그건 버튼으로 시키는 것이 아니다.
class _LocationQualityBar extends StatelessWidget {
  final String message;

  const _LocationQualityBar({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.my_location_outlined,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도에서 기준점을 옮기면 이 목록의 거리와 순서가 함께 바뀐다(사용자 결정,
/// 2026-08-16). 바뀐 사실을 화면에 적지 않으면 사용자는 거리가 이상해진 것을
/// 결함으로 읽는다 — 지도에서 한 조작과 목록의 숫자를 연결 짓기 어렵다.
class _AnchorNoticeBar extends StatelessWidget {
  final VoidCallback onReset;

  const _AnchorNoticeBar({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.center_focus_strong,
            size: 16,
            color: AppColors.accentText,
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              '지도에서 지정한 위치 기준으로 거리를 보여 주고 있습니다',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.accentText,
              ),
            ),
          ),
          // 되돌리는 방법을 같은 줄에 둔다. 지도를 다시 열어야만 풀 수 있으면
          // 목록에서 이상을 발견한 사람이 갈 곳을 잃는다.
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: AppColors.accentText,
            ),
            child: const Text(
              '내 위치로',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// 좌표가 없는 명함들을 모아 보여 주는 구획의 머리글.
///
/// ⚠️ **왜 있는지 한 줄로 말해 준다.** 그냥 목록만 이어 붙이면 이용자는
/// "왜 이 사람들은 거리가 없지?"에서 멈춘다. 거리를 못 잰 것이 명함의
/// 문제가 아니라 **주소로 위치를 못 찾은 것**임을 밝힌다.
class _RegionSectionHeader extends StatelessWidget {
  final int count;

  const _RegionSectionHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '위치를 못 찾은 인맥 ($count명)',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '주소로 정확한 위치를 찾지 못해 거리는 표시하지 못하지만, 지역별로 모아 두었어요.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _NearbyContactTile extends StatelessWidget {
  final ContactModel contact;

  /// 기준점에서의 거리. ⚠️ **좌표가 없으면 `null`** 이다 — 0이나 빈 값을
  /// 넣으면 "아주 가깝다"로 읽힌다. 지역 묶음(좌표 없음)에서 그렇다.
  final double? distanceMeters;
  final VoidCallback onOpen;
  final VoidCallback onCall;

  /// 주소 줄(F-12)을 보여 줄지. 같은 주소 묶음(F-15) 안에서는 머리글에 주소가
  /// 이미 있어 `false`로 준다 — 같은 값이 줄마다 반복되면 오히려 읽기 어렵다.
  final bool showAddress;

  const _NearbyContactTile({
    required this.contact,
    required this.distanceMeters,
    required this.onOpen,
    required this.onCall,
    this.showAddress = true,
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
                // 주소 한 줄(F-12) — 이 화면의 목적이 "지금 어디쯤 가까이 있는가"라
                // 회사명만으로는 부족했다. 주소가 없는 명함은 애초에 좌표가 없어
                // 이 목록에 뜨지 않지만, 혹시 비어 있으면 줄 자체를 숨긴다.
                if (showAddress &&
                    (contact.address ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 12.5,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          contact.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
              // 거리를 모르면 뱃지를 아예 그리지 않는다 — 빈 뱃지는
              // "가깝다"로도 "멀다"로도 읽혀서 없느니만 못하다.
              if (distanceMeters != null)
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
                    GeoUtils.formatDistanceLabel(distanceMeters!),
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
