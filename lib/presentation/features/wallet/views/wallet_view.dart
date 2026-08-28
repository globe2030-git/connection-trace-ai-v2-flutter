import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/geo_backfill_service.dart';
import '../../../common/call_picker_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/korean_initial.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/group_model.dart' show kGroupsFeatureEnabled;
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/collapsing_list_header.dart';
import '../../../common/contact_avatar.dart';
import '../view_models/groups_view_model.dart';
import '../view_models/wallet_view_model.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import 'add_card_modal_view.dart';
import 'contact_detail_view.dart';

class WalletView extends StatefulWidget {
  const WalletView({super.key});

  @override
  State<WalletView> createState() => _WalletViewState();
}

class _WalletViewState extends State<WalletView> {
  // 초성 인덱스 바에서 특정 위치로 점프하기 위한 컨트롤러. State에 두어야
  // 리빌드에도 유지된다.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // "위치값 없음"(주소는 있는데 지오코딩 포기) 명함 id 집합. 시도 기록을
  // 비동기로 읽어 채우고, 확정된 명함에만 아이콘을 붙여 깜빡임을 막는다.
  final GeoBackfillService _geoService = GeoBackfillService();
  Set<String> _givenUpGeoIds = {};
  // 마지막으로 판정에 쓴 명함 목록의 서명 — 바뀔 때만 다시 계산한다.
  String _givenUpSig = '';

  // 목록 상단 고정(UI 개선 ⑦). 큰 제목은 스크롤하면 접히고, 검색·정렬은
  // 계속 화면 위에 남는다 — 판정 로직은 공용 [HeaderCollapseTracker]로
  // 뽑아 뒀다(주변 탭도 같은 패턴을 쓸 예정, 브리프 ⑦ 순서표).
  final HeaderCollapseTracker _headerTracker = HeaderCollapseTracker();

  // 선택 삭제 모드(F-06). 평소 목록은 깨끗하게 두고(스와이프 삭제만), "선택"을
  // 누르면 각 행에 체크박스가 뜨고 하단에 "N개 삭제" 바가 나온다. 과거 "목록에
  // 삭제 버튼을 두지 않는다"는 결정(2026-08-10)과 부딪히지 않도록, 삭제 UI는
  // 이 모드에 들어갔을 때만 드러난다.
  //
  // ⚠️ 예전엔 이 모드에 들어갈 때 `MainTabScreen.hideFab`을 켜서 명함 등록
  // FAB을 숨겼다(2026-08-28, FAB이 하단에 떠 있던 동안). 명함 등록이 다시
  // 탭 바 목적지("등록")로 바뀌면서 그 신호는 지웠다 — **직접 확인한
  // 이유**: 이 화면(`WalletView`)은 자체 `Scaffold`가 있고 `_buildDeleteBar`
  // (아래)는 그 안 `Column`의 평범한 마지막 자식이라, 실제 탭 바
  // (`main_tab_screen.dart`의 `bottomNavigationBar`) 바로 위에 나란히
  // 놓일 뿐 겹치지 않는다 — FAB처럼 `Stack`으로 그 위에 떠서 가리는
  // 방식이 아니었다. 겹칠 일이 없으니 숨길 신호도 필요 없다.
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  /// 명함 목록이 바뀌었을 때만 지오코딩 포기 집합을 다시 구한다. 결과가
  /// 오면 setState로 아이콘을 반영한다(서명은 목록 기준이라 setState가
  /// 루프를 돌지 않는다).
  void _maybeRefreshGivenUp(List<ContactModel> contacts) {
    final sig = contacts
        .map((c) => '${c.id}|${c.address ?? ''}|${c.geo == null}')
        .join(';');
    if (sig == _givenUpSig) return;
    _givenUpSig = sig;
    _geoService.resolveGivenUpIds(contacts).then((ids) {
      if (!mounted) return;
      setState(() => _givenUpGeoIds = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WalletViewModel>();
    final groupsVm = context.watch<GroupsViewModel>();
    // 선택돼 있던 그룹이 삭제되면(다른 곳에서, 또는 관리 시트에서) 그
    // id가 더는 존재하지 않는다 — 그대로 두면 모든 명함의 groupIds가 그
    // id를 안 가지므로 목록이 조용히 텅 비어 버린다("검색 결과 없음"과
    // 구분이 안 감). 다음 프레임에 "전체"로 되돌린다.
    if (viewModel.selectedGroupId != null &&
        !groupsVm.groups.any((g) => g.id == viewModel.selectedGroupId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) viewModel.setSelectedGroup(null);
      });
    }
    final contacts = viewModel.filteredContacts;
    _maybeRefreshGivenUp(viewModel.contacts);

    // 목록이 비어 스크롤할 것이 없어지면(검색·태그로 다 걸러졌거나 전부
    // 지웠거나) 접힌 채로 남지 않게 강제로 편다 — 스크롤 없이 접혀 있으면
    // 큰 제목이 왜 안 보이는지 알 길이 없다.
    if (contacts.isEmpty) _headerTracker.reset();
    final headerCollapsed = contacts.isEmpty ? false : _headerTracker.collapsed;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 목록 상단 고정(UI 개선 ⑦, 2026-08-21). 맨 위에서는 지금까지와
              // 같은 큰 제목이 보이고, 스크롤하면 축약 제목+검색+정렬만 남아
              // 화면 위에 고정된다 — 명함이 많을 때 도구를 쓰려고 매번 맨
              // 위로 되돌아가지 않게 하려는 것이다.
              CollapsingListHeader(
                collapsed: headerCollapsed,
                expandedTop: _buildExpandedTop(viewModel, groupsVm, contacts),
                collapsedTop: _buildCollapsedTop(viewModel, contacts),
                pinnedTools: _buildPinnedTools(viewModel),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: contacts.isEmpty
                    ? _WalletEmptyState(
                        hasSavedContacts: viewModel.contacts.isNotEmpty,
                        onAdd: () => _openCardEditor(context),
                      )
                    // 목록 자체의 스크롤 알림만 여기서 받는다 — 아래
                    // 스와이프 삭제(Dismissible)나 선택 모드 체크박스 탭은
                    // ScrollNotification이 아니라 영향이 없다.
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (_headerTracker.update(notification.metrics.pixels)) {
                            setState(() {});
                          }
                          return false;
                        },
                        child: _buildContactList(
                          context,
                          viewModel,
                          groupsVm,
                          contacts,
                        ),
                      ),
              ),
              if (_selectionMode) _buildDeleteBar(context, viewModel),
            ],
          ),
        ),
      ),
    );
  }

  /// 스크롤 맨 위에서만 보이는 큰 제목 블록. 태그 칩도 여기 함께 넣어
  /// 스크롤하면 제목과 함께 흘려보낸다(브리프 ⑦ 표: "큰 제목 블록·신규
  /// 칩"이 같은 칸에 묶여 있다) — 검색창처럼 계속 눌러야 하는 도구가
  /// 아니라, 위에서 한 번 훑고 나면 다시 안 볼 때가 많은 필터라서 접어도
  /// 손해가 적다.
  Widget _buildExpandedTop(
    WalletViewModel viewModel,
    GroupsViewModel groupsVm,
    List<ContactModel> contacts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          // 오른쪽 동작 버튼의 높이가 왼쪽 제목 칼럼과 달라도 제목이 항상
          // 같은 높이에서 시작하도록 맨 위로 고정.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '명함 지갑',
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
                    _selectionMode
                        ? '${_selectedIds.length}개 선택'
                        : '${viewModel.contacts.length}명의 인맥',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _buildHeaderTrailingActions(viewModel, contacts),
          ],
        ),
        // 그룹 칩(추가 427) — 명함이 하나도 없으면(빈 지갑) 굳이 보여주지
        // 않는다. 태그 칩과 같은 자리(스크롤하면 함께 흘려간다)에 두되,
        // 캔버스 확정안에서 그룹이 더 앞선 개념이라 태그보다 위에 둔다.
        // ⚠️ 빌드 스위치(kGroupsFeatureEnabled) — 방침 v2.3 시행 후
        // 전에는 통째로 숨긴다(group_model.dart 주석 참고). 데이터는 그대로
        // 두고 화면만 뺀다.
        if (kGroupsFeatureEnabled && viewModel.contacts.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildGroupChips(context, viewModel, groupsVm),
          if (groupsVm.groups.isNotEmpty &&
              groupsVm.contactsWithoutGroupCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '그룹이 없는 명함은 "전체"에서만 보여요.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
        if (viewModel.allTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildTagChips(viewModel),
        ],
      ],
    );
  }

  /// 그룹(필터) 칩 가로 목록 — [전체][그룹A n][그룹B n]…[+ 그룹].
  Widget _buildGroupChips(
    BuildContext context,
    WalletViewModel viewModel,
    GroupsViewModel groupsVm,
  ) {
    final groups = groupsVm.groups;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _GroupFilterChip(
            label: '전체',
            selected: viewModel.selectedGroupId == null,
            onTap: () => viewModel.setSelectedGroup(null),
          ),
          for (final g in groups) ...[
            const SizedBox(width: 8),
            _GroupFilterChip(
              label: '${g.name} ${groupsVm.memberCountOf(g.id)}',
              selected: viewModel.selectedGroupId == g.id,
              onTap: () => viewModel.setSelectedGroup(g.id),
            ),
          ],
          const SizedBox(width: 8),
          _GroupFilterChip(
            // ⚠️ 라벨에 '+'를 넣지 않는다 — 이 칩은 icon 이 있으면 아이콘을
            // 앞에 그리므로 "+ + 그룹"이 된다(2026-08-26 실기기에서 드러남).
            // 그룹 기능이 꺼져 있는 동안에는 이 칩 자체가 안 보여서 몰랐다.
            label: '그룹',
            selected: false,
            icon: Icons.add,
            onTap: () => _promptCreateGroup(context, groupsVm),
          ),
        ],
      ),
    );
  }

  /// "+ 그룹" 칩 — 특정 명함이 아니라 그룹 자체를 새로 만든다(빈 이름은
  /// [GroupsRepository.createGroup] 쪽에서 무시하지 않으므로 여기서 미리
  /// 막는다).
  Future<void> _promptCreateGroup(
    BuildContext context,
    GroupsViewModel groupsVm,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('새 그룹 만들기'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 삼성전자, 보험설계사'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    groupsVm.createGroup(trimmed);
  }

  /// 접혔을 때만 보이는 축약 제목 줄 — "명함 지갑"+개수 배지(선택 모드면
  /// 선택 개수)만 남기고 태그 칩은 뺀다. 오른쪽 동작(선택, 또는 선택
  /// 모드의 전체선택·취소)은 스크롤 중에도 계속 쓸 수 있어야 해서 그대로
  /// 남긴다 — 브리프 표는 "축약 제목+개수 배지"까지만 못 박았지만, 선택
  /// 진입로가 스크롤하면 사라지는 쪽이 더 불편하다고 판단했다(디자이너
  /// 재량, 높이 예산 안에서 여유 있게 들어간다).
  Widget _buildCollapsedTop(
    WalletViewModel viewModel,
    List<ContactModel> contacts,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _selectionMode ? '${_selectedIds.length}개 선택' : '명함 지갑',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (!_selectionMode) ...[
                const SizedBox(width: 8),
                HeaderCountBadge(count: viewModel.contacts.length),
              ],
            ],
          ),
        ),
        _buildHeaderTrailingActions(viewModel, contacts),
      ],
    );
  }

  /// 제목 줄 오른쪽 동작 — 선택 모드면 전체선택/취소, 아니면 "선택" 진입
  /// 아이콘 하나뿐이다. 접힌 줄·펼친 줄이 같은 동작을 그대로 공유한다.
  ///
  /// ⚠️ **"명함 등록" 아이콘은 여기 없다(2026-08-28, globe2030님 결정으로
  /// 제거).** 예전엔 이 자리(머리글 오른쪽 위)와 주변 화면의 같은 자리에
  /// 각각 하나씩, 자리·모양을 맞춰 두 벌 있었다(2026-08-12 결정). 그런데
  /// globe2030님이 실사용(하루 아이폰 126장·폴드 190장 등록)에서 "위에
  /// 있어서 불편하다"고 하셨다. 같은 날 하단 FAB(가운데 도킹 → 오른쪽
  /// 아래)을 거쳐 지금은 **`main_tab_screen.dart`의 하단 탭 바 4번째
  /// 목적지("등록") 하나로 합쳤다** — globe2030님이 처음부터 "탭 바"를
  /// 뜻하셨다는 것을 다시 확인해 주셨다. 두 곳에 남기지 않은 이유: 같은
  /// 동작이 위·아래 두 곳에 있으면 "이전 습관대로 위쪽을 계속 누르는"
  /// 경우가 남아 정작 옮긴 효과가 옅어진다. 설계 근거는
  /// docs/planning/specs/card-add-button-placement-2026-08-28.md.
  ///
  /// 다만 **빈 지갑 상태의 "첫 명함 등록" 버튼(아래 `_WalletEmptyState`,
  /// ~1130행)은 그대로 남긴다** — 그건 항상 떠 있는 진입점의 중복이 아니라
  /// "지갑이 비어 있다"는 안내 문구에 붙은 그 자리 한정 행동 유도이고,
  /// 목록이 비었을 때만 보인다.
  Widget _buildHeaderTrailingActions(
    WalletViewModel viewModel,
    List<ContactModel> contacts,
  ) {
    if (_selectionMode) return _buildSelectionHeaderActions(contacts);
    // "선택" 진입점(F-06)뿐이다. 명함이 있을 때만 보인다 — 빈 지갑에서는
    // 고를 것이 없다. 스와이프 삭제는 그대로 두고, 이 버튼으로 다건 선택
    // 삭제에 들어간다. 명함이 하나도 없으면 이 Row는 빈 채로 그려진다
    // (mainAxisSize.min이라 자리를 차지하지 않는다) — 그 상태의 등록
    // 진입점은 하단 탭 바의 "등록"과 `_WalletEmptyState`의 "첫 명함 등록"
    // 버튼이 맡는다.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewModel.contacts.isNotEmpty)
          IconButton(
            tooltip: '선택 삭제',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.cardSurface,
              shape: const CircleBorder(),
              side: const BorderSide(color: AppColors.borderSubtle),
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 40),
              maximumSize: const Size(40, 40),
            ),
            icon: const Icon(
              Icons.checklist_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: _enterSelectionMode,
          ),
      ],
    );
  }

  /// 태그(필터) 칩 가로 목록 — 큰 제목과 함께 스크롤하면 흘려간다.
  Widget _buildTagChips(WalletViewModel viewModel) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: viewModel.allTags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = viewModel.allTags[index];
          final selected = viewModel.selectedTags.contains(tag);
          return FilterChip(
            label: Text(tag),
            selected: selected,
            onSelected: (_) => viewModel.toggleTag(tag),
            selectedColor: AppColors.accentSoft,
            checkmarkColor: AppColors.accentText,
            side: BorderSide(
              color: selected ? AppColors.accent : AppColors.borderSubtle,
            ),
            labelStyle: TextStyle(
              color: selected ? AppColors.accentText : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    );
  }

  /// 검색창 + 정렬 칩 — 스크롤·접힘과 무관하게 항상 화면 위에 고정된다
  /// (브리프 ⑦ 표가 이 둘을 명시적으로 "고정"으로 지정했다). 태그 칩과
  /// 달리 이 둘은 지금 보는 목록을 계속 좁혀 나가는 도구라 손에서 놓지
  /// 않는 편이 낫다고 판단했다.
  Widget _buildPinnedTools(WalletViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        TextField(
          onChanged: viewModel.setSearchTerm,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '이름, 회사, 직함 검색',
            hintStyle: TextStyle(color: AppColors.textMuted),
            prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
          ),
        ),
        // 정렬 칩은 검색 아래에 둔다(기존 배치 유지, 2026-08-11 결정).
        const SizedBox(height: 10),
        _buildSortSelector(viewModel),
        // 거리순을 골랐는데 위치 기준이 없으면(동의 전/측위 실패) 최근등록순
        // 으로 대신 보여주고 있다는 것을 알린다 — 안 알리면 "거리순을
        // 눌렀는데 왜 거리순이 아니지"로 보인다.
        if (viewModel.distanceSortFallbackActive) ...[
          const SizedBox(height: 6),
          const Text(
            '위치 정보가 없어 최근 등록순으로 보여줘요. 주변 탭에서 위치 이용에 '
            '동의하면 거리순으로 정렬돼요.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  /// 선택 모드일 때 헤더 오른쪽에 뜨는 동작 — 전체 선택/해제 + 취소.
  /// "전체"는 지금 화면에 보이는(검색·태그로 걸러진) 명함을 기준으로 한다.
  Widget _buildSelectionHeaderActions(List<ContactModel> contacts) {
    final allSelected =
        contacts.isNotEmpty &&
        contacts.every((c) => _selectedIds.contains(c.id));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              for (final c in contacts) {
                if (allSelected) {
                  _selectedIds.remove(c.id);
                } else {
                  _selectedIds.add(c.id);
                }
              }
            });
          },
          child: Text(allSelected ? '전체 해제' : '전체 선택'),
        ),
        TextButton(
          onPressed: _exitSelectionMode,
          child: const Text('취소'),
        ),
      ],
    );
  }

  // ⚠️ 2026-08-23 사용자 확정: 추가 427에서 캔버스 확정안(넷)에 맞춰
  // "소통일순"을 지웠다가, "기존 기능과 상충하면 갈아엎지 않고 공존시킨다"
  // (2026-08-20 원칙)에 따라 되살렸다 — 지금은 다섯 개다.
  static const _sortLabels = {
    ContactSort.recent: '최근등록순',
    ContactSort.name: '이름순',
    ContactSort.company: '회사명순',
    ContactSort.lastComm: '소통일순',
    ContactSort.distance: '가까운 거리순',
  };

  /// 정렬 기준 선택 칩. 다섯 개를 한 화면에 균등 분할로 모두 보여준다.
  /// ⚠️ 다섯 번째(거리순)가 추가되며 칸이 좁아졌다 — 각 칩 내부가
  /// FittedBox로 줄어들게 돼 있어(_SortChip) 잘리지는 않지만, 실기기에서
  /// 라벨이 너무 빽빽해 보이면 UI 담당에게 넘길 것.
  Widget _buildSortSelector(WalletViewModel viewModel) {
    final entries = _sortLabels.entries.toList();
    return Row(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _SortChip(
              label: entries[i].value,
              selected: viewModel.sort == entries[i].key,
              onTap: () => viewModel.setSort(entries[i].key),
            ),
          ),
        ],
      ],
    );
  }

  /// 명함 목록 + (이름/회사명 정렬이고 충분히 많을 때) 오른쪽 초성 인덱스 바.
  Widget _buildContactList(
    BuildContext context,
    WalletViewModel viewModel,
    GroupsViewModel groupsVm,
    List<ContactModel> contacts,
  ) {
    // 인덱스 바에 실제로 존재하는 그룹만 순서대로 모은다. 그룹 점프가 의미
    // 없는 정렬(최근등록·거리)이나 항목이 적으면 바를 숨긴다.
    final groups = <String>[];
    for (final c in contacts) {
      final g = viewModel.sortGroupOf(c);
      if (g.isNotEmpty && !groups.contains(g)) groups.add(g);
    }
    final showIndexBar = groups.length >= 2 && contacts.length >= 10;

    // id → 그룹 이름. 카드마다 groupsVm.groups를 순회하지 않도록 한 번만 만든다.
    final groupNameById = {for (final g in groupsVm.groups) g.id: g.name};

    final list = ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      // ⚠️ 2026-08-28 하루 동안 이 값이 24 → 80 → 96 → (지금) 24로
      // 왔다갔다 했다 — 전부 명함 등록 FAB(하단에 떠서 목록 위를 가리던)
      // 때문이었다. 지금은 FAB이 없고 탭 바 목적지("등록")로 바뀌었다 —
      // 탭 바는 `Scaffold.bottomNavigationBar`라 body(이 목록)와 자리를
      // 나눠 쓸 뿐 위에 겹쳐 뜨지 않으므로, 마지막 행을 가릴 것이 없다.
      // 원래 값(24)으로 되돌린다.
      padding: EdgeInsets.only(bottom: 24, right: showIndexBar ? 22 : 0),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final cardDate = viewModel.cardDateFor(contact);
        final groupNames = contact.groupIds
            .map((id) => groupNameById[id])
            .whereType<String>()
            .toList();
        // .separated 대신 .builder를 쓰고 구분선을 항목 안에 넣는다 —
        // 인덱스 점프(scrollTo)의 index가 구분선 없이 항목과 1:1로 맞아야
        // 원하는 위치로 정확히 이동한다.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ContactCard(
              contact: contact,
              groupNames: groupNames,
              geoNotFound: _givenUpGeoIds.contains(contact.id),
              cardDate: cardDate.date,
              cardDateLabel: cardDate.label,
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(contact.id),
              onToggleSelected: () => _toggleSelected(contact.id),
              // 2026-08-19(추가 330): 목록을 누르면 **상세 보기**가 뜬다.
              // 예전에는 곧장 편집 폼이었다 — 읽으려는 사람에게 입력 화면을
              // 준 셈이었고, 값을 실수로 건드릴 위험도 있었다.
              // 편집은 상세 화면의 [편집] 버튼으로 간다.
              onEdit: () => ContactDetailView.show(context, contact),
              onCall: () => showCallPicker(context, contact),
              onDelete: () => viewModel.deleteContact(contact.id),
              onBriefing: () => _openBriefing(context, contact),
            ),
            if (index < contacts.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSubtle,
              ),
          ],
        );
      },
    );

    if (!showIndexBar) return list;
    return Stack(
      children: [
        list,
        // ⚠️ 이 인덱스 바도 FAB이 있던 동안(centerDocked·endFloat 두 시도
        // 모두) `bottom`을 96까지 올렸었다 — FAB이 이 화면 오른쪽 아래
        // 모서리와 같은 자리를 썼기 때문이다. 확인해 보니 지금은 `bottom:
        // 0`, 즉 손댄 적 없는 원래 값 그대로다 — FAB 관련 수정은 전부
        // main_tab_screen.dart의 FAB 자체를 되돌리는 과정에서 이미 걷어
        // 냈고(PR #632로 분리), 이 화면은 그 되돌림 이후 상태에서
        // 시작했다. 지금(탭 바)은 FAB이 아예 없으니 다시 올릴 이유도
        // 없다 — 그대로 0으로 둔다.
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: _InitialIndexBar(
            groups: groups,
            onSelect: (group) => _jumpToGroup(group, viewModel, contacts),
          ),
        ),
      ],
    );
  }

  /// 인덱스 바에서 그룹을 누르면 그 그룹의 첫 명함으로 스크롤한다.
  void _jumpToGroup(
    String group,
    WalletViewModel viewModel,
    List<ContactModel> contacts,
  ) {
    final targetRank = KoreanInitial.rankOfGroup(group);
    for (var i = 0; i < contacts.length; i++) {
      if (KoreanInitial.rank(_sortKeyText(viewModel, contacts[i])) >=
          targetRank) {
        _itemScrollController.scrollTo(
          index: i,
          alignment: 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        return;
      }
    }
  }

  String _sortKeyText(WalletViewModel viewModel, ContactModel c) =>
      viewModel.sort == ContactSort.company ? c.company : c.name;

  /// 선택 모드 하단의 삭제 실행 바. 아무것도 안 골랐으면 비활성.
  Widget _buildDeleteBar(BuildContext context, WalletViewModel viewModel) {
    final count = _selectedIds.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.borderSubtle,
              disabledForegroundColor: AppColors.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: count == 0
                ? null
                : () => _confirmBulkDelete(context, viewModel),
            icon: const Icon(Icons.delete_outline, size: 20),
            label: Text(
              count == 0 ? '삭제할 명함을 선택하세요' : '$count개 삭제',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  /// 선택한 명함을 한꺼번에 삭제한다 — 실행 전 한 번 확인한다.
  Future<void> _confirmBulkDelete(
    BuildContext context,
    WalletViewModel viewModel,
  ) async {
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('$count개의 명함을 삭제할까요?'),
        // ⚠️ "기기에서"라고만 적으면 이 폰에서만 지우는 것으로 읽힌다.
        // 실제로는 서버(Firestore)와 다른 기기에서도 사라지고 되돌릴 수
        // 없다 — 명함을 지우면 삭제 기록(묘비)이 남아 다른 기기도 따라
        // 지운다(P1-39 A안). 사진 서버 사본은 플래그를 켠 뒤 여기 문구에
        // 함께 넣는다(2026-08-16, 지금은 올라간 사진이 없어 사실이 아니다).
        content: const Text(
          '선택한 명함과 기록이 기기와 서버에서 모두 삭제됩니다.\n'
          '되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    viewModel.deleteContacts(_selectedIds);
    _exitSelectionMode();
  }

  void _openCardEditor(BuildContext context, {ContactModel? contact}) {
    AddCardModalView.show(context, contact: contact);
  }

  /// AI 대화 가이드를 전체 화면으로 연다.
  ///
  /// 주변 화면은 이 위젯을 자기 `Stack` 위에 겹쳐 놓지만, 지갑 화면에는 그런
  /// 스택이 없다. 화면 구조를 바꾸는 대신 라우트로 밀어 올린다 — 뒤로 가기
  /// 제스처와 시스템 뒤로 가기가 그대로 동작하는 이점도 있다.
  void _openBriefing(BuildContext context, ContactModel contact) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => Scaffold(
          backgroundColor: AppColors.bgBase,
          body: BriefingOverlayView(
            contact: contact,
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ContactModel contact;
  // 소속 그룹 이름들(추가 427) — 이미 삭제된 그룹 id는 조회 단계에서
  // 걸러져 여기 들어오지 않는다(wallet_view.dart의 groupNameById 조회).
  final List<String> groupNames;
  // 주소는 있는데 지오코딩을 포기해 좌표가 없는 상태(= "위치값 없음").
  final bool geoNotFound;
  // 카드에 표시할 날짜와 라벨 — 정렬 기준에 맞춘다(등록일/마지막 소통일).
  final DateTime? cardDate;
  final String cardDateLabel;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onBriefing;
  // 선택 삭제 모드(F-06). 켜지면 왼쪽에 체크박스가 붙고, 행을 누르면 편집
  // 대신 선택이 토글되며, 스와이프 삭제·동작 버튼은 잠긴다.
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelected;

  const _ContactCard({
    required this.contact,
    required this.groupNames,
    required this.geoNotFound,
    required this.cardDate,
    required this.cardDateLabel,
    required this.onEdit,
    required this.onCall,
    required this.onDelete,
    required this.onBriefing,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(contact.id),
      // 선택 모드에서는 스와이프 삭제를 잠근다 — 체크박스로 골라 하단 바에서
      // 지운다. 두 삭제 경로가 동시에 열려 있으면 헷갈린다.
      direction: selectionMode
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        // 목록이 카드에서 구분선 방식으로 바뀌면서 바깥 여백과 둥근 모서리를
        // 뺐다 — 남겨 두면 미는 동안 행 아래에 흰 틈이 보인다.
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerRight,
        color: AppColors.destructive,
        // 휴지통 아이콘 대신 "삭제" 글자를 쓴다(사용자 결정, 2026-08-10).
        // 아이콘은 무슨 동작인지 한 번 더 해석해야 하지만 글자는 바로 읽힌다.
        // 스크린리더가 행마다 "삭제"를 중복해 읽지 않도록 접근성 트리에서는
        // 제외한다(P1-12) — 미는 동작 자체는 스크린리더 사용자에게 보이지
        // 않으므로 이 글자도 읽힐 필요가 없다.
        child: const ExcludeSemantics(
          child: Text(
            '삭제',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: selected ? AppColors.accentSoft : AppColors.cardSurface,
        child: InkWell(
          onTap: selectionMode ? onToggleSelected : onEdit,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (selectionMode) ...[
                    // 탭은 행 전체(InkWell)가 받으므로 체크박스는 표시용 —
                    // onChanged도 같은 토글로 연결해 어디를 눌러도 동작 일치.
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelected(),
                      activeColor: AppColors.accent,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                  ContactAvatar(
                    photoPath: contact.avatarUrl,
                    name: contact.name,
                    radius: 26,
                    // "명함을 대표 이미지로" 켠 인맥은 암호화된 명함 이미지를
                    // 아바타로 보여준다(추가 133).
                    contactId: contact.id,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 이름 / 직함 / 회사명을 각각 한 줄씩 — 예전에는 이름과
                        // 직함을 "이름 · 직함"으로 한 줄에 붙였는데, 직함이 긴
                        // 사람은 이름까지 잘려 나갔다.
                        Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (contact.title.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            contact.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
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
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 그룹 꼬리표(추가 427) — 최대 2개 + "n" 뱃지. 셋 이상을
                        // 다 펼치면 좁은 카드에서 이름·회사가 더 밀려 잘린다.
                        // 빌드 스위치는 위 그룹 칩과 동일(group_model.dart 참고).
                        if (kGroupsFeatureEnabled && groupNames.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _GroupTagsRow(groupNames: groupNames),
                        ],
                      ],
                    ),
                  ),
                  // 날짜와 동작 버튼을 오른쪽 세로 묶음으로 둔다. 날짜를 본문
                  // 칼럼 안(회사명 줄)에 두면 버튼 폭만큼 안쪽으로 들어가 앉아
                  // 정작 오른쪽 끝에 붙지 않는다 — 사용자가 "우측 정렬"을
                  // 요청한 지점이다(2026-08-10).
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_dateText != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 2),
                          // 날짜만 보이면 무슨 날짜인지 모호하니 스크린리더에는
                          // 정렬에 맞춘 라벨(등록/마지막 소통)을 함께 읽어 준다.
                          child: Semantics(
                            label: '$cardDateLabel $_dateText',
                            child: ExcludeSemantics(
                              child: Text(
                                _dateText!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // 선택 모드에서는 동작 버튼(전화·AI)을 숨긴다 — 그 줄은
                      // 선택이 목적이므로 탭이 선택 토글에만 반응해야 한다.
                      if (!selectionMode)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          // 동작 버튼은 촘촘하게 — 세 줄짜리 본문이 들어오면서
                          // 예전 크기로는 이름이 들어갈 자리가 남지 않는다.
                          if (contact.phone.trim().isNotEmpty)
                            _CompactAction(
                              tooltip: '${contact.name}에게 전화',
                              onPressed: onCall,
                              icon: const AppIcon(
                                AppIconId.call,
                                size: 20,
                                color: AppColors.accentText,
                              ),
                            ),
                          // AI 대화 가이드는 원래 "주변" 화면에서만 열 수
                          // 있었다. 그런데 주변 화면은 지금 근처에 있는 인맥만
                          // 보여주므로, 평소에 "이 사람에게 연락해 볼까" 하는
                          // 순간에는 진입할 길이 없었다(실사용 피드백 — 쓸 수
                          // 있는 곳이 한 곳뿐이라 잘 안 쓰게 된다). 명함 지갑은
                          // 인맥 전체가 있는 곳이라 여기서 바로 열려야 한다.
                          _CompactAction(
                            tooltip: '${contact.name} AI 대화 가이드',
                            onPressed: onBriefing,
                            icon: const Icon(
                              Icons.auto_awesome,
                              size: 20,
                              color: AppColors.accentText,
                            ),
                          ),
                          // 삭제 버튼은 목록에 두지 않는다(사용자 결정,
                          // 2026-08-10). 빨간 휴지통은 줄마다 노출돼 산만했고,
                          // 더보기 메뉴(⋮)로 옮겨도 보기 좋지 않다는 판단이라
                          // **왼쪽으로 밀어서 삭제**만 남긴다. 미는 동작은
                          // 위 Dismissible이 처리하며, 밀면 빨간 배경과 휴지통
                          // 아이콘이 드러나 무엇을 하는 동작인지 보인다.
                        ],
                      ),
                      // 위치 상태 아이콘 — AI 가이드 아래 우측(사용자 요청).
                      // 크기는 AI 가이드 아이콘과 동일(20). 두 경우를 색으로
                      // 확실히 구분한다: 주소 없음=회색(주소칸이 빔),
                      // 위치값 없음=주황(주소는 있으나 좌표를 못 받음). OS
                      // 지오코더는 "좌표 받음/못 받음"만 알려줘 실패 원인은
                      // 구분할 수 없으므로 ②는 하나로 합쳐 "위치값 없음"으로 둔다.
                      if ((contact.address ?? '').trim().isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(right: 10, top: 3),
                          child: _LocationWarnIcon(
                            icon: Icons.location_off_outlined,
                            tooltip: '주소 없음',
                            color: AppColors.textMuted,
                          ),
                        )
                      else if (geoNotFound)
                        const Padding(
                          padding: EdgeInsets.only(right: 10, top: 3),
                          child: _LocationWarnIcon(
                            icon: Icons.wrong_location_outlined,
                            tooltip: '위치값 없음',
                            color: AppColors.warningText,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 목록에 표시할 날짜 문자열. 어떤 날짜인지(등록일/마지막 소통일)는 정렬
  /// 기준에 따라 호출부(WalletViewModel.cardDateFor)가 정해 [cardDate]로
  /// 넘겨준다. 값이 없으면 표시하지 않는다.
  String? get _dateText {
    final at = cardDate;
    if (at == null) return null;
    return '${at.year}.${at.month.toString().padLeft(2, '0')}.'
        '${at.day.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('명함을 삭제할까요?'),
            // 위 일괄 삭제와 같은 이유로 "기기와 서버"라고 적는다.
            content: Text(
              '${contact.name}님의 명함과 기록이 기기와 서버에서 모두 '
              '삭제됩니다.\n되돌릴 수 없습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  '삭제',
                  style: TextStyle(color: AppColors.destructive),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// 명함 목록에서 위치 상태를 알리는 아이콘. AI 가이드 아이콘과 같은 크기(20)로
/// 오른쪽 묶음에 둔다. 두 경우는 색으로 구분하고, 뜻은 툴팁으로 안내한다.
/// - 주소 없음(주소칸이 빔): 회색 [Icons.location_off_outlined]
/// - 검색DB없음(주소는 있으나 지오코딩 검색 실패): 주황 [Icons.wrong_location_outlined]
class _LocationWarnIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;

  const _LocationWarnIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _WalletEmptyState extends StatelessWidget {
  final bool hasSavedContacts;
  final VoidCallback onAdd;

  const _WalletEmptyState({
    required this.hasSavedContacts,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSavedContacts ? Icons.search_off : Icons.badge_outlined,
                size: 34,
                color: AppColors.accentText,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasSavedContacts ? '검색 결과가 없습니다' : '아직 등록된 명함이 없습니다',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSavedContacts
                  ? '다른 이름이나 회사명으로 검색해 보세요.'
                  : '실제 명함을 촬영하거나 직접 입력해 첫 인맥을 등록해 보세요.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            if (!hasSavedContacts) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const AppIcon(AppIconId.addCard),
                label: const Text('첫 명함 등록'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 목록 행에 들어가는 촘촘한 아이콘 버튼.
///
/// 기본 `IconButton`은 48×48을 잡아 세 개만 놓아도 가로 144를 먹는다. 이름·
/// 직함·회사명 세 줄이 들어오면서 그 폭을 감당할 수 없어 40×40으로 줄였다.
/// 40은 터치 목표 최소치(iOS 44 / Material 48)보다 작지만, 행 전체가 이미
/// 탭 가능(명함 편집)하고 삭제는 밀어서도 되므로 여기서만 예외로 둔다.
class _CompactAction extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;

  const _CompactAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      iconSize: 20,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }
}

/// 정렬 기준 선택 칩. 선택된 것만 강조한다.
/// 명함 카드에 붙는 그룹 꼬리표(추가 427) — 최대 2개까지 이름을 보여주고,
/// 그 이상은 "+n"으로 뭉친다(브리프 인수 기준 "최대 2+n").
class _GroupTagsRow extends StatelessWidget {
  final List<String> groupNames;

  const _GroupTagsRow({required this.groupNames});

  @override
  Widget build(BuildContext context) {
    const maxShown = 2;
    final shown = groupNames.take(maxShown).toList();
    final overflow = groupNames.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final name in shown) _tag(name),
        if (overflow > 0) _tag('+$overflow'),
      ],
    );
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: AppColors.accentText,
      ),
    ),
  );
}

/// 그룹 필터 칩(추가 427) — "전체"/각 그룹/"+ 그룹" 공용. [_SortChip]과
/// 비슷하지만 가로 스크롤 목록 안에서 내용에 맞게 폭이 늘어나야 해서
/// (`Expanded` 균등분할이 아니라) 별도 위젯으로 둔다.
class _GroupFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _GroupFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? AppColors.accentText : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accentText : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderSubtle,
          ),
        ),
        // 균등 분할 폭이 좁아도 잘리지 않게 필요하면 살짝 줄인다.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              // 기존 13에서 10% 축소(사용자 요청, 2026-08-11).
              fontSize: 11.7,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accentText : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 명함이 많을 때 오른쪽 가장자리에서 초성(ㄱㄴㄷ)·영문(A~Z)·기타(#)로
/// 점프하는 인덱스 바. 실제 존재하는 그룹만 순서대로 보여준다. 그룹 수가
/// 화면 높이보다 많아도 FittedBox가 줄여서 넘치지 않게 한다.
class _InitialIndexBar extends StatelessWidget {
  final List<String> groups;
  final ValueChanged<String> onSelect;

  const _InitialIndexBar({required this.groups, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // 폭을 명확히 고정한다 — Positioned(top/bottom/right)만으로는 가로 제약이
    // 무한대라 Center/FittedBox 레이아웃이 불안정해질 수 있다(터치 영역 어긋남).
    return SizedBox(
      width: 28,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            width: 26,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in groups)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(g),
                    child: Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        g,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentText,
                        ),
                      ),
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
