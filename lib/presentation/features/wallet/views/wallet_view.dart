import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import '../view_models/wallet_view_model.dart';
import '../../briefing/views/briefing_overlay_view.dart';
import 'add_card_modal_view.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WalletViewModel>();
    final contacts = viewModel.filteredContacts;

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
              const SizedBox(height: 14),
              Expanded(
                child: contacts.isEmpty
                    ? _WalletEmptyState(
                        hasSavedContacts: viewModel.contacts.isNotEmpty,
                        onAdd: () => _openCardEditor(context),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: contacts.length,
                        // 카드마다 그림자를 주는 대신 얇은 구분선으로 나눈다 —
                        // 한 화면에 더 많은 인맥이 들어오고, 이름·직함·회사명
                        // 세 줄이 카드 테두리와 경쟁하지 않는다(사용자 요청,
                        // 2026-08-10).
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.borderSubtle,
                        ),
                        itemBuilder: (context, index) => _ContactCard(
                          contact: contacts[index],
                          onEdit: () => _openCardEditor(
                            context,
                            contact: contacts[index],
                          ),
                          onCall: () => PhoneCallService.showCallPicker(
                            context,
                            contacts[index],
                          ),
                          onDelete: () =>
                              viewModel.deleteContact(contacts[index].id),
                          onBriefing: () =>
                              _openBriefing(context, contacts[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onBriefing;

  const _ContactCard({
    required this.contact,
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
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: AppColors.destructive,
          borderRadius: BorderRadius.circular(22),
        ),
        // 밀어서 삭제할 때만 잠깐 드러나는 장식 아이콘 — 스크린리더가 카드마다
        // "삭제"를 중복해 읽지 않도록 접근성 트리에서 제외한다(P1-12).
        child: const ExcludeSemantics(
          child: Icon(Icons.delete_outline, color: Colors.white),
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
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
                            // 날짜는 회사명 줄 오른쪽 끝에 둔다. 이름 줄에
                            // 붙이면 긴 이름이 날짜에 밀려 잘리는데, 회사명은
                            // 이름보다 짧은 경우가 많아 여유가 생긴다.
                            if (_savedOn != null) ...[
                              const SizedBox(width: 8),
                              // ⚠️ 이 날짜는 "등록일"이 아니라 마지막으로
                              // 저장한 시각(updatedAt)이다 — 모델에 등록일이
                              // 없다. 화면에는 날짜만 뜨므로 등록일로 오해할
                              // 수 있어, 스크린리더에는 무엇인지 밝혀 준다.
                              Semantics(
                                label: '마지막 저장 $_savedOn',
                                child: ExcludeSemantics(
                                  child: Text(
                                    _savedOn!,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 동작 버튼은 촘촘하게 — 세 줄짜리 본문이 들어오면서 예전
                  // 크기로는 이름이 들어갈 자리가 남지 않는다.
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
                  // AI 대화 가이드는 원래 "주변" 화면에서만 열 수 있었다. 그런데
                  // 주변 화면은 지금 근처에 있는 인맥만 보여주므로, 평소에 "이
                  // 사람에게 연락해 볼까" 하는 순간에는 진입할 길이 없었다
                  // (실사용 피드백 — 쓸 수 있는 곳이 한 곳뿐이라 잘 안 쓰게 된다).
                  // 명함 지갑은 인맥 전체가 있는 곳이라 여기서 바로 열 수 있어야 한다.
                  _CompactAction(
                    tooltip: '${contact.name} AI 대화 가이드',
                    onPressed: onBriefing,
                    icon: const Icon(
                      Icons.auto_awesome,
                      size: 20,
                      color: AppColors.accentText,
                    ),
                  ),
                  // 왼쪽으로 밀어서 삭제(Dismissible)만 있으면 알아채기 어려워서,
                  // 눈에 보이는 삭제 버튼도 같이 둔다.
                  _CompactAction(
                    tooltip: '${contact.name} 명함 삭제',
                    onPressed: () async {
                      if (await _confirmDelete(context)) onDelete();
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppColors.destructive,
                    ),
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
