import 'package:flutter/material.dart';

import '../../../../core/services/reconnect_priority_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';

/// 사용자가 C에서 실제로 고른 것. 아무것도 안 골랐으면 이 값 자체가 없다(null).
class ReconnectOutcomeResult {
  final ReconnectOutcome outcome;

  /// "언제 다시?"에서 고른 간격. "안 정함"이면 null — 날짜를 지어내지 않는다.
  final Duration? followUpAfter;

  const ReconnectOutcomeResult({required this.outcome, this.followUpAfter});
}

/// F-10 **C. 연락 후 후속** — "연락 어땠어요?"를 한 탭으로 묻는다.
///
/// ## ⚠️ 강요하지 않는다 — 이 원칙을 못 지키면 C는 죽는다
///
/// - **한 탭**이면 끝난다. 반응만 고르면 그대로 저장되고 닫힌다.
/// - **안 눌러도 된다.** 바깥을 누르거나 닫기를 누르면 아무것도 저장하지 않는다.
///   `null`이 돌아가고 호출자는 아무 일도 하지 않는다.
/// - "언제 다시?"는 반응이 **[좋음]일 때만** 이어서 묻는다. 반응이 보통이거나
///   못 닿았는데 다음 약속을 묻는 것은 사용자를 몰아세우는 것이다.
/// - [안 정함]도 **동등한 선택지**다. 넷 중 하나를 고르게 강제하지 않는다.
///
/// 여기서 모은 것이 A의 우선순위를 정확하게 만든다(C→A 되먹임). 하지만 그건
/// 앱의 사정이지 사용자의 의무가 아니다 — 안 누르면 A는 방치 기간만으로
/// 계속 돈다.
class ReconnectOutcomeSheet extends StatefulWidget {
  final ContactModel contact;

  const ReconnectOutcomeSheet({super.key, required this.contact});

  /// 시트를 띄우고 사용자가 고른 값을 돌려준다. 안 고르고 닫으면 null.
  static Future<ReconnectOutcomeResult?> show(
    BuildContext context,
    ContactModel contact,
  ) {
    return showModalBottomSheet<ReconnectOutcomeResult>(
      context: context,
      backgroundColor: Colors.transparent,
      // 바깥을 눌러 닫을 수 있어야 "안 해도 된다"가 말이 된다.
      isDismissible: true,
      enableDrag: true,
      builder: (_) => ReconnectOutcomeSheet(contact: contact),
    );
  }

  @override
  State<ReconnectOutcomeSheet> createState() => _ReconnectOutcomeSheetState();
}

class _ReconnectOutcomeSheetState extends State<ReconnectOutcomeSheet> {
  /// [좋음]을 고른 뒤에만 두 번째 질문으로 넘어간다.
  bool _askingFollowUp = false;

  void _choose(ReconnectOutcome outcome) {
    if (outcome == ReconnectOutcome.good) {
      setState(() => _askingFollowUp = true);
      return;
    }
    Navigator.pop(context, ReconnectOutcomeResult(outcome: outcome));
  }

  void _chooseFollowUp(Duration? after) {
    Navigator.pop(
      context,
      ReconnectOutcomeResult(
        outcome: ReconnectOutcome.good,
        followUpAfter: after,
      ),
    );
  }

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
                  Expanded(
                    child: Text(
                      _askingFollowUp
                          ? '언제 다시 연락할까요?'
                          : '${widget.contact.name} 님과 연락 어땠어요?',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
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
              const SizedBox(height: 2),
              Text(
                _askingFollowUp
                    ? '고른 시점이 되면 "오늘 연락하면 좋은 사람"에 다시 올라옵니다.'
                    : '안 눌러도 됩니다. 누르면 다음에 누구부터 연락할지 정하는 데 쓰입니다.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (_askingFollowUp)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChoiceChip(
                      label: '1주',
                      onTap: () => _chooseFollowUp(const Duration(days: 7)),
                    ),
                    _ChoiceChip(
                      label: '2주',
                      onTap: () => _chooseFollowUp(const Duration(days: 14)),
                    ),
                    _ChoiceChip(
                      label: '1달',
                      onTap: () => _chooseFollowUp(const Duration(days: 30)),
                    ),
                    // 정하지 않는 것도 동등한 선택지다.
                    _ChoiceChip(
                      label: '안 정함',
                      muted: true,
                      onTap: () => _chooseFollowUp(null),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _OutcomeButton(
                        label: '좋음',
                        emphasized: true,
                        onTap: () => _choose(ReconnectOutcome.good),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OutcomeButton(
                        label: '보통',
                        onTap: () => _choose(ReconnectOutcome.normal),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OutcomeButton(
                        label: '없음',
                        onTap: () => _choose(ReconnectOutcome.none),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '이 기록은 명함 정보와 같이 암호화되어 저장되고, AI로 보내지 않습니다.',
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

class _OutcomeButton extends StatelessWidget {
  final String label;
  final bool emphasized;
  final VoidCallback onTap;

  const _OutcomeButton({
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized ? AppColors.accentSoft : AppColors.bgBase,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          // 44는 손가락으로 정확히 누를 수 있는 최소 높이다.
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: emphasized
                  ? AppColors.accentSoftStrong
                  : AppColors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: emphasized
                  ? AppColors.accentText
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool muted;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: muted ? AppColors.bgBase : AppColors.accentSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: muted
                  ? AppColors.borderSubtle
                  : AppColors.accentSoftStrong,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: muted ? AppColors.textSecondary : AppColors.accentText,
            ),
          ),
        ),
      ),
    );
  }
}
