import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../view_models/wallet_view_model.dart';
import 'add_card_modal_view.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WalletViewModel>();
    final contacts = viewModel.filteredContacts;

    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '명함 지갑',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.7,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${viewModel.contacts.length}명의 인맥',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // "+"와 하단 "명함 스캔" 버튼이 같은 기능이라 하나로
                  // 합쳤다 — 새 명함 등록 진입점은 이거 하나만 남긴다.
                  ElevatedButton.icon(
                    onPressed: () => _openCardEditor(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(
                      Icons.document_scanner_outlined,
                      size: 18,
                    ),
                    label: const Text(
                      '명함 스캔',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
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
                              : AppColors.borderDark,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddCardModalView(contactToEdit: contact),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onEdit;
  final VoidCallback onCall;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.onEdit,
    required this.onCall,
    required this.onDelete,
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
                    icon: const Icon(
                      Icons.phone_outlined,
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
                icon: const Icon(Icons.add),
                label: const Text('첫 명함 등록'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
