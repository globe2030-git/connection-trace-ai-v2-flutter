import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/reconnect_priority_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';

/// F-10 **A. "오늘 연락하면 좋은 사람"** — '주변' 탭 상단 섹션.
///
/// 이 섹션의 목적은 "무슨 말을 할까"가 아니라 **"누굴 까먹었나"**에 답하는
/// 것이다. 영업직의 1번 고통이 그쪽이고, 이게 매일 앱을 여는 이유가 된다.
///
/// 순위와 이유는 전부 [ReconnectPriorityService]가 기기 안에서 정한다 —
/// 여기서는 **받은 것을 그리기만 한다.** 화면에서 이유 문구를 새로 조합하면
/// 그 문장이 어떤 데이터에서 나왔는지 추적할 수 없어진다
/// (`test/no_fabricated_reconnect_reason_test.dart`가 이를 막는다).
///
/// 후보가 없으면 **아무것도 그리지 않는다.** 최근에 연락한 사람을 억지로
/// 끌어와 자리를 채우지 않는다 — 그러면 이 섹션의 뜻이 "연락할 때가 된 사람"이
/// 아니라 "아무나"가 되고, 한 번 그렇게 느끼면 다시는 안 본다.
class ReconnectTodaySection extends StatelessWidget {
  final List<ReconnectCandidate> candidates;

  /// [연락 가이드] — 기존 AI 브리핑을 연다. AI는 이 시점에만 개입한다.
  final void Function(ContactModel contact) onOpenGuide;

  /// "이번엔 넘김" — 7일 뒤에 다시 후보가 된다.
  final void Function(ContactModel contact) onSnooze;

  const ReconnectTodaySection({
    super.key,
    required this.candidates,
    required this.onOpenGuide,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppIcon(
              AppIconId.recentContact,
              size: 18,
              color: AppColors.accentText,
            ),
            const SizedBox(width: 6),
            Text(
              '오늘 연락하면 좋은 사람 (${candidates.length}명)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...candidates.map(
          (candidate) => _ReconnectTile(
            candidate: candidate,
            onOpenGuide: () => onOpenGuide(candidate.contact),
            onSnooze: () => onSnooze(candidate.contact),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _ReconnectTile extends StatelessWidget {
  final ReconnectCandidate candidate;
  final VoidCallback onOpenGuide;
  final VoidCallback onSnooze;

  const _ReconnectTile({
    required this.candidate,
    required this.onOpenGuide,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    final contact = candidate.contact;
    final reason = candidate.reason;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      // 근거가 강한 줄만 액센트 테두리로 살짝 구분한다. 전부 강조하면 아무것도
      // 강조되지 않고, 근거 없는 줄까지 강조하면 그게 곧 과장이 된다.
      borderColor: reason.isStrong ? AppColors.accentSoftStrong : null,
      onTap: onOpenGuide,
      child: Row(
        children: [
          ContactAvatar(
            photoPath: contact.avatarUrl,
            name: contact.name,
            radius: 20,
            contactId: contact.id,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (contact.company.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          contact.company,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // 이유 — 서비스가 만든 문구를 그대로 쓴다.
                Text(
                  reason.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: reason.isStrong
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: reason.isStrong
                        ? AppColors.accentText
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // "넘김"을 눌러도 사라지는 것뿐 — 무엇도 지워지지 않는다.
          Semantics(
            button: true,
            label: '${contact.name} 이번엔 넘기기',
            child: Tooltip(
              message: '이번엔 넘김 (7일 뒤 다시)',
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onSnooze,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.schedule,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
