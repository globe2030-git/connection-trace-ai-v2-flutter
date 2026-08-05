import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';

enum CommunicationSourceAction { gmail, callNote, smsPaste, kakaoPaste }

class CommunicationSourceSheet extends StatelessWidget {
  final ContactModel contact;

  const CommunicationSourceSheet({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '소통 기록 추가',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                '${contact.name} 님과 주고받은 정보 중 사용자가 선택한 내용만 기기에 저장합니다.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              _SourceTile(
                icon: AppIconId.emailLink,
                title: 'Gmail에서 가져오기',
                subtitle: contact.email.trim().isEmpty
                    ? '먼저 명함에 이메일 주소를 등록해 주세요.'
                    : '${contact.email}과 주고받은 메일을 직접 선택',
                enabled: contact.email.trim().isNotEmpty,
                onTap: () =>
                    Navigator.pop(context, CommunicationSourceAction.gmail),
              ),
              _SourceTile(
                icon: AppIconId.call,
                title: '통화 후 메모',
                subtitle: '통화 기록을 읽지 않고 기억할 내용을 직접 작성',
                onTap: () =>
                    Navigator.pop(context, CommunicationSourceAction.callNote),
              ),
              _SourceTile(
                icon: AppIconId.message,
                title: '문자 내용 붙여넣기',
                subtitle: '필요한 대화만 선택해 직접 붙여넣기',
                onTap: () =>
                    Navigator.pop(context, CommunicationSourceAction.smsPaste),
              ),
              _SourceTile(
                icon: AppIconId.chatSend,
                title: '카카오톡 내용 붙여넣기',
                subtitle: '카카오톡에서 복사한 필요한 대화만 붙여넣기',
                onTap: () => Navigator.pop(
                  context,
                  CommunicationSourceAction.kakaoPaste,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 17,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '문자·통화기록·카카오톡 대화를 앱이 자동으로 읽지 않습니다. iOS 제한과 스토어 심사 정책을 준수하는 방식입니다.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final AppIconId icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.bgDarkSlate,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AppIcon(
                      icon,
                      color: enabled
                          ? AppColors.accentText
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: enabled
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
