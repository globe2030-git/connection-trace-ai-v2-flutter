import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
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
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: contacts.length,
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
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        onTap: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 92),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Row(
              children: [
                ContactAvatar(
                  photoPath: contact.avatarUrl,
                  name: contact.name,
                  radius: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: contact.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (contact.title.trim().isNotEmpty)
                              TextSpan(
                                text: ' · ${contact.title}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact.company.trim().isEmpty
                            ? '회사 정보 없음'
                            : contact.company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (contact.tags.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            contact.tags.first,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accentText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (contact.phone.trim().isNotEmpty)
                  IconButton(
                    tooltip: '${contact.name}에게 전화',
                    onPressed: onCall,
                    icon: const AppIcon(
                      AppIconId.call,
                      color: AppColors.accentText,
                    ),
                  ),
                // AI 대화 가이드는 원래 "주변" 화면에서만 열 수 있었다. 그런데
                // 주변 화면은 지금 근처에 있는 인맥만 보여주므로, 평소에 "이
                // 사람에게 연락해 볼까" 하는 순간에는 진입할 길이 없었다
                // (실사용 피드백 — 쓸 수 있는 곳이 한 곳뿐이라 잘 안 쓰게 된다).
                // 명함 지갑은 인맥 전체가 있는 곳이라 여기서 바로 열 수 있어야 한다.
                IconButton(
                  tooltip: '${contact.name} AI 대화 가이드',
                  onPressed: onBriefing,
                  icon: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.accentText,
                  ),
                ),
                // 왼쪽으로 밀어서 삭제(Dismissible)만 있으면 알아채기 어려워서,
                // 눈에 보이는 삭제 버튼도 같이 둔다.
                IconButton(
                  tooltip: '${contact.name} 명함 삭제',
                  onPressed: () async {
                    if (await _confirmDelete(context)) onDelete();
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.destructive,
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
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
