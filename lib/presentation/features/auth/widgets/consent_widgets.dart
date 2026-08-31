/// `AdConsentView`(스탠드얼론 광고 동의 화면)와 `SignupConsentView`(⑨, 통합
/// 동의 화면)가 함께 쓰는 동의 선택 UI 부품.
///
/// ## 🚨 왜 한 파일로 뽑았나
///
/// 처음에는 두 화면이 각자 그렸다. 그러면 **어긋난다** — 두 화면이 다른
/// 시점에 다른 사람이 고치면 한쪽만 `[선택]` 배지가 빠지거나, 한쪽만
/// 일괄 체크가 선택 항목까지 켜는 식으로 **법 요건이 갈릴 수 있다**
/// (`docs/planning/specs/email-signup-unified-consent-2026-08-31.md` §5-1).
/// 그래서 **부품을 하나로 두고 두 화면이 조립만 다르게 한다**(리팩터링,
/// 동작 변경 없음 — 원래 `ad_consent_view.dart`에 있던 위젯을 그대로 옮겼다).
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// `[선택]` 배지. 시행령 §17④가 **선택할 수 있다는 사실을 명확히 표시**하도록
/// 요구한다.
class OptionalBadge extends StatelessWidget {
  const OptionalBadge({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 11,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '선택',
        style: TextStyle(
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}

/// `[필수]` 배지. `OptionalBadge`와 짝을 이룬다 — 색만 다르다(강조색).
class MandatoryBadge extends StatelessWidget {
  const MandatoryBadge({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 11,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentSoftStrong,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '필수',
        style: TextStyle(
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}

class ConsentCard extends StatelessWidget {
  const ConsentCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class RowDivider extends StatelessWidget {
  const RowDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 15),
    color: const Color(0xFFF0F2F5),
  );
}

/// 동의 항목 한 줄(체크박스 + 제목 + 부제). `[선택]` 배지를 항상 붙인다 —
/// 필수 항목(만14세·약관 등)은 별도 위젯을 쓴다.
class ChannelRow extends StatelessWidget {
  const ChannelRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 잠긴 상태를 흐리게 보여 준다. 숨기지 않는 이유는, 무엇을 고를 수 있는지
    // 먼저 보여야 위 항목에 동의할지 판단할 수 있기 때문이다.
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: InkWell(
        onTap: enabled ? () => onChanged(!checked) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          child: Row(
            children: [
              ConsentCheckbox(checked: checked, enabled: enabled),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const OptionalBadge(dense: true),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsentCheckbox extends StatelessWidget {
  const ConsentCheckbox({super.key, required this.checked, required this.enabled});

  final bool checked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 23,
      height: 23,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: checked ? AppColors.accent : AppColors.cardSurface,
        border: checked
            ? null
            : Border.all(color: const Color(0xFFC9CFD9), width: 1.8),
        borderRadius: BorderRadius.circular(7),
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}
