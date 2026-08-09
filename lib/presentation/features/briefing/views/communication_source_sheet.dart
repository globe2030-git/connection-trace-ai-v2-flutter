import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';

enum CommunicationSourceAction { gmail, callNote, smsPaste, kakaoPaste }

/// Gmail 가져오기 노출 여부. **v1에서는 꺼 둔다**(2026-08-09 결정-2, backlog
/// 추가 128 / HANDOFF P1-41).
///
/// 기능을 지우는 게 아니라 입구만 막는 것이다 — `EmailSyncService`와
/// `email_import_sheet.dart`는 그대로 두고 이 플래그만 `true`로 되돌리면
/// 다시 열린다. 끄는 이유는 `gmail.readonly`가 Google의 "제한된 범위"라
/// 보안평가(CASA)를 받아야 하는데, 그 비용과 심사 기간을 v1 일정에 걸
/// 근거가 아직 없기 때문이다.
///
/// ⚠️ 이 플래그만으로는 부족하다. **Google Cloud Console 동의 화면에서
/// `gmail.readonly` 범위도 함께 빼야 한다** — 쓰지도 않는 제한된 범위를
/// 요구하는 상태로 두면 검증에서 반려될 수 있다.
const bool kGmailImportEnabled = false;

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
                icon: AppIconId.emailLink,
                title: 'Gmail에서 가져오기',
                subtitle: !kGmailImportEnabled
                    ? '다음 업데이트에서 제공할 예정입니다.'
                    : contact.email.trim().isEmpty
                    ? '먼저 명함에 이메일 주소를 등록해 주세요.'
                    : '${contact.email}과 주고받은 메일을 직접 선택',
                enabled: kGmailImportEnabled && contact.email.trim().isNotEmpty,
                badge: kGmailImportEnabled ? null : '준비 중',
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

  /// 오른쪽 화살표 대신 보여 줄 상태 배지(예: '준비 중'). null이면 화살표.
  final String? badge;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.bgBase,
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
                    if (badge == null)
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.borderFunctional),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
