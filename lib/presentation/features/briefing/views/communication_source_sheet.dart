import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';

/// 소통 기록을 추가할 수 있는 경로.
///
/// v1에는 Gmail 가져오기가 없다. 2026-08-09 결정-2(backlog 추가 128 /
/// HANDOFF P1-41)로 "준비 중" 배지를 단 비활성 항목으로 남겨 뒀었는데,
/// 제공 계획이 서지 않은 기능을 목록에 계속 보여 주는 것이 오히려 혼란을
/// 준다고 판단해 항목과 관련 문구를 전부 뺐다(2026-08-10).
///
/// 코드까지 지운 것은 아니다 — `EmailSyncService`와 `email_import_sheet.dart`는
/// 남아 있으므로, 되살릴 때는 이 enum에 `gmail`을 되돌리고 아래 목록에 타일을
/// 다시 넣은 뒤 `BriefingOverlayView._addCommunicationRecord`에서
/// `EmailImportSheet`를 열면 된다.
///
/// ⚠️ 되살릴 때 코드만으로는 부족하다. `gmail.readonly`는 Google의 "제한된
/// 범위"라 보안평가(CASA)를 통과해야 하고, **Google Cloud Console 동의
/// 화면에도 범위를 다시 넣어야 한다**. 반대로 지금처럼 쓰지 않는 동안에는
/// 동의 화면에서 `gmail.readonly`를 빼 두어야 검증에서 반려되지 않는다.
enum CommunicationSourceAction { callNote, smsPaste, kakaoPaste }

class CommunicationSourceSheet extends StatelessWidget {
  final ContactModel contact;

  const CommunicationSourceSheet({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
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

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
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
                    AppIcon(icon, color: AppColors.accentText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
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
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                    ),
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
