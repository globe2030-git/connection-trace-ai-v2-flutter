import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/geo_backfill_service.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/korean_initial.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import '../view_models/wallet_view_model.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import 'add_card_modal_view.dart';

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
    final contacts = viewModel.filteredContacts;
    _maybeRefreshGivenUp(viewModel.contacts);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // 오른쪽 "명함 스캔" 버튼의 높이가 주변 화면의 원형 아이콘
                // 버튼과 달라도 제목이 항상 같은 높이에서 시작하도록 맨
                // 위로 고정 — 기본값인 center로 두면 제목이 버튼 높이에
                // 따라 미묘하게 위아래로 밀려 다른 탭과 위치가 안 맞는다.
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
                          '${viewModel.contacts.length}명의 인맥',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // "+"와 하단 "명함 스캔" 버튼이 같은 기능이라 하나로
                  // 합쳤다 — 새 명함 등록 진입점은 이거 하나만 남긴다.
                  // 내 명함 등록 화면의 "내 명함 카메라 스캔" 버튼과 같은
                  // 아웃라인 스타일로 통일(꽉 채운 배경은 부담스럽다는 피드백).
                  OutlinedButton.icon(
                    onPressed: () => _openCardEditor(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.accentText),
                      foregroundColor: AppColors.accentText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const AppIcon(
                      AppIconId.scanCard,
                      size: 18,
                      color: AppColors.accentText,
                    ),
                    label: const Text(
                      '명함 스캔',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.accentText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: viewModel.setSearchTerm,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: '이름, 회사, 직함 검색',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (viewModel.allTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
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
                          color: selected
                              ? AppColors.accent
                              : AppColors.borderSubtle,
                        ),
                        labelStyle: TextStyle(
                          color: selected
                              ? AppColors.accentText
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
              ],
              // 정렬 칩은 태그 아래에 둔다(사용자 요청, 2026-08-11).
              const SizedBox(height: 12),
              _buildSortSelector(viewModel),
              // 위치 진단 배너. **필터가 아닌 전체 명함**(`viewModel.contacts`)을
              // 기준으로 센다 — 태그·검색으로 걸러진 화면 목록이 아니라 "내
              // 명함 전체 중 몇 개가 주변 인맥에 안 뜨는가"가 알고 싶은 값이다.
              _LocationDiagnosticBanner(
                contacts: viewModel.contacts,
                givenUpGeoIds: _givenUpGeoIds,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: contacts.isEmpty
                    ? _WalletEmptyState(
                        hasSavedContacts: viewModel.contacts.isNotEmpty,
                        onAdd: () => _openCardEditor(context),
                      )
                    : _buildContactList(context, viewModel, contacts),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _sortLabels = {
    ContactSort.recent: '최근등록순',
    ContactSort.name: '이름순',
    ContactSort.company: '회사명순',
    ContactSort.lastComm: '소통일순',
  };

  /// 정렬 기준 선택 칩. 네 개를 한 화면에 균등 분할로 모두 보여준다(가로
  /// 스크롤을 없애 "소통일순"이 잘려 보이던 문제 해결).
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
    List<ContactModel> contacts,
  ) {
    // 인덱스 바에 실제로 존재하는 그룹만 순서대로 모은다. 그룹 점프가 의미
    // 없는 시간 기준 정렬(최근등록·소통일)이나 항목이 적으면 바를 숨긴다.
    final groups = <String>[];
    for (final c in contacts) {
      final g = viewModel.sortGroupOf(c);
      if (g.isNotEmpty && !groups.contains(g)) groups.add(g);
    }
    final showIndexBar = groups.length >= 2 && contacts.length >= 10;

    final list = ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: EdgeInsets.only(bottom: 24, right: showIndexBar ? 22 : 0),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        // .separated 대신 .builder를 쓰고 구분선을 항목 안에 넣는다 —
        // 인덱스 점프(scrollTo)의 index가 구분선 없이 항목과 1:1로 맞아야
        // 원하는 위치로 정확히 이동한다.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ContactCard(
              contact: contact,
              geoNotFound: _givenUpGeoIds.contains(contact.id),
              onEdit: () => _openCardEditor(context, contact: contact),
              onCall: () => PhoneCallService.showCallPicker(context, contact),
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
  // 주소는 있는데 지오코딩을 포기해 좌표가 없는 상태(= "위치값 없음").
  final bool geoNotFound;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onBriefing;

  const _ContactCard({
    required this.contact,
    required this.geoNotFound,
    required this.onEdit,
    required this.onCall,
    required this.onDelete,
    required this.onBriefing,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(contact.id),
      direction: DismissDirection.endToStart,
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
        color: AppColors.cardSurface,
        child: InkWell(
          onTap: onEdit,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 92),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ContactAvatar(
                    photoPath: contact.avatarUrl,
                    name: contact.name,
                    radius: 26,
                    // "명함을 대표 이미지로" 켠 인맥은 암호화된 명함 이미지를
                    // 아바타로 보여준다(추가 133).
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
                            // 주소가 없거나 위치를 못 찾으면 주변 인맥(레이더)에
                            // 안 뜬다 — 왜 안 뜨는지 목록에서 아이콘으로 미리
                            // 알려 채워/고쳐 넣게 한다. 두 경우를 구분한다:
                            // ① 주소 없음: 주소 문자열이 비었다(안정된 값이라
                            //    깜빡임 없음). ② 위치값 없음: 주소는 있는데
                            //    지오코딩을 여러 번 시도하고도 좌표를 못 만든
                            //    확정 상태(geoNotFound). geo==null만으로 판단하면
                            //    backfill 도중 깜빡이므로 "포기 확정"만 쓴다.
                            if ((contact.address ?? '').trim().isEmpty) ...[
                              const SizedBox(width: 6),
                              const _LocationWarnIcon(
                                icon: Icons.location_off_outlined,
                                tooltip: '주소 없음',
                              ),
                            ] else if (geoNotFound) ...[
                              const SizedBox(width: 6),
                              const _LocationWarnIcon(
                                icon: Icons.wrong_location_outlined,
                                tooltip: '위치값 없음',
                              ),
                            ],
                          ],
                        ),
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
                      if (_savedOn != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6, bottom: 2),
                          // ⚠️ 등록일이 아니라 마지막 저장 시각(updatedAt)이다 —
                          // 모델에 등록일이 없다. 날짜만 보이면 등록일로 오해할
                          // 수 있어 스크린리더에는 무엇인지 밝혀 준다.
                          child: Semantics(
                            label: '마지막 저장 $_savedOn',
                            child: ExcludeSemantics(
                              child: Text(
                                _savedOn!,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
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

  /// 목록에 표시할 날짜. 모델에 등록일이 없어 `updatedAt`(마지막 저장 시각)을
  /// 쓴다 — 예전 데이터에는 없을 수 있어 그때는 아예 표시하지 않는다.
  String? get _savedOn {
    final at = contact.updatedAt;
    if (at == null) return null;
    return '${at.year}.${at.month.toString().padLeft(2, '0')}.'
        '${at.day.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('명함을 삭제할까요?'),
            content: Text('${contact.name}님의 명함과 기록이 기기에서 삭제됩니다.'),
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

/// 명함 목록에서 위치 상태를 알리는 작은 아이콘. 텍스트 대신 아이콘으로 —
/// 목록이 깔끔하고, 뜻은 길게 누르면 뜨는 툴팁으로 안내한다.
/// - 주소 없음: [Icons.location_off_outlined]
/// - 위치값 없음(주소는 있으나 좌표 못 찾음): [Icons.wrong_location_outlined]
class _LocationWarnIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;

  const _LocationWarnIcon({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppColors.warningText),
      ),
    );
  }
}

/// 명함첩 상단에 뜨는 위치 진단 배너 — 주변 인맥에 안 뜨는 명함 수를 알린다.
///
/// 두 원인을 나눠 센다(사용자 요청 B, 2026-08-10):
/// - **주소 없음**: 사용자가 주소를 안 넣음 → 명함을 눌러 채우면 된다.
/// - **위치 못 찾음**: 주소는 있는데 지오코딩이 좌표를 못 만듦 → 주소 형태
///   문제일 수 있다. 탭하면 실패 형태 집계(C안)를 보여 준다.
///
/// 좌표(geo)는 서버에 없고 기기에서 주소로 계산하는 파생값이라, 이 수는
/// **이 기기의 현재 명함 목록**에서만 셀 수 있다 — 그래서 서버 조회가 아니라
/// 화면에서 실시간으로 센다.
class _LocationDiagnosticBanner extends StatelessWidget {
  final List<ContactModel> contacts;
  // 카드 아이콘과 **같은 기준**을 쓰도록 지오코딩 포기 집합을 받아 센다 —
  // geo==null로 세면 backfill 도중 값이 카드 아이콘과 어긋난다.
  final Set<String> givenUpGeoIds;

  const _LocationDiagnosticBanner({
    required this.contacts,
    required this.givenUpGeoIds,
  });

  @override
  Widget build(BuildContext context) {
    var noAddress = 0;
    var noGeo = 0;
    for (final c in contacts) {
      final hasAddress = (c.address ?? '').trim().isNotEmpty;
      if (!hasAddress) {
        noAddress++;
      } else if (givenUpGeoIds.contains(c.id)) {
        // 주소는 있는데 여러 번 시도하고도 좌표를 못 만든 확정 상태.
        noGeo++;
      }
    }
    if (noAddress == 0 && noGeo == 0) return const SizedBox.shrink();

    final parts = <String>[
      if (noAddress > 0) '주소 없는 명함 $noAddress개',
      if (noGeo > 0) '위치값 없는 명함 $noGeo개',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(context, noAddress, noGeo),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.location_off_outlined,
                  size: 17,
                  color: AppColors.warningText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${parts.join(' · ')} — 주변 인맥에 표시되지 않아요',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warningText,
                      height: 1.3,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.warningText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    int noAddress,
    int noGeo,
  ) async {
    // 지오코딩 실패 형태 집계(C안)를 함께 보여 준다 — "왜 위치를 못 찾는가"의
    // 실마리. 주소 원문은 담기지 않은, 형태 코드별 건수다.
    final shapes = await GeoBackfillService.readFailureShapeStats();
    if (!context.mounted) return;
    final sorted = shapes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('위치를 못 찾는 명함'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (noAddress > 0)
              Text('· 주소가 없는 명함: $noAddress개\n  명함을 열어 주소를 넣으면 주변 인맥에 표시됩니다.'),
            if (noAddress > 0 && noGeo > 0) const SizedBox(height: 8),
            if (noGeo > 0)
              Text(
                '· 주소는 있지만 위치를 못 찾은 명함: $noGeo개\n  주소가 정확한지 확인해 주세요(건물명만 있으면 못 찾을 수 있어요).',
              ),
            if (sorted.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                '실패한 주소 형태(개발 참고)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              for (final e in sorted.take(6))
                Text(
                  '${e.value}건  ${e.key}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
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
