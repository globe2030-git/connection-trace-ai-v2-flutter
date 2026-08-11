import 'package:flutter/material.dart';

import '../../core/services/ai_briefing_service.dart';
import '../../core/services/ai_usage_service.dart';
import '../../core/theme/app_colors.dart';

/// "오늘 N회" 형태로 남은 AI 생성 횟수를 보여주는 공용 칩.
///
/// 여러 화면(홈·설정·AI 브리핑)이 같은 칩을 쓰고, [AiUsageService.latest]를
/// 구독하므로 어느 화면에서 AI를 써서 사용량을 다시 읽으면 모든 칩이 함께
/// 갱신된다. **탭하면** 오늘/이번 달 잔여와 안내를 담은 상세 시트를 연다
/// (길게 누르는 툴팁은 사용자가 인지하기 어렵다는 피드백에 따라 탭으로 바꿈).
///
/// 서비스가 아직 배포 안 됐거나([AiBriefingService.kAiServiceDeployed]=false)
/// 사용량을 한 번도 못 읽었으면 아무것도 그리지 않는다.
class AiUsageChip extends StatefulWidget {
  const AiUsageChip({super.key});

  @override
  State<AiUsageChip> createState() => _AiUsageChipState();
}

class _AiUsageChipState extends State<AiUsageChip> {
  @override
  void initState() {
    super.initState();
    // 최신값을 읽어 온다(성공하면 latest에 방송돼 이 칩도 갱신됨).
    AiUsageService.fetch();
  }

  @override
  Widget build(BuildContext context) {
    if (!AiBriefingService.kAiServiceDeployed) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<AiUsage?>(
      valueListenable: AiUsageService.latest,
      builder: (context, usage, _) {
        if (usage == null) return const SizedBox.shrink();
        final exhausted = usage.exhausted;
        final lowBalance = usage.lowBalance;
        final fg = exhausted
            ? AppColors.destructive
            : lowBalance
                ? AppColors.warningText
                : AppColors.accentText;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _showDetails(context, usage),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 14, color: fg),
                  const SizedBox(width: 3),
                  Text(
                    exhausted ? '한도 소진' : '잔여 ${usage.totalRemaining}회',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: fg),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDetails(BuildContext context, AiUsage usage) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _UsageDetailSheet(usage: usage),
    );
  }
}

class _UsageDetailSheet extends StatelessWidget {
  final AiUsage usage;
  const _UsageDetailSheet({required this.usage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.bolt, size: 20, color: AppColors.accentText),
                SizedBox(width: 6),
                Text(
                  'AI 사용량',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: '오늘 사용',
                    value: '${usage.dailyUsed}회',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    label: '잔여',
                    value: '${usage.totalRemaining}회',
                  ),
                ),
              ],
            ),
            if (usage.bonusCredits > 0) ...[
              const SizedBox(height: 6),
              Text(
                '무료 ${usage.remaining}회 + 충전/보너스 ${usage.bonusCredits}회',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '같은 계정이면 기기와 상관없이 함께 차감돼요. 한도는 시간이 지나면 자동으로 다시 채워집니다.\n'
              '충전·보너스로 받은 회차는 시간이 지나도 사라지지 않아요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (usage.lowBalance || usage.exhausted) ...[
              const SizedBox(height: 12),
              _LowBalanceBanner(exhausted: usage.exhausted),
            ],
          ],
        ),
      ),
    );
  }
}

/// 잔여 회차가 얼마 없거나 소진됐을 때 시트 안에 보여주는 인라인 안내.
/// 바텀시트 안에서는 스낵바가 가려져 안 보이므로 인라인으로 그린다.
// TODO: 충전 화면(config/billing 기반) 완성되면 여기 CTA 버튼 연결 예정
class _LowBalanceBanner extends StatelessWidget {
  final bool exhausted;
  const _LowBalanceBanner({required this.exhausted});

  @override
  Widget build(BuildContext context) {
    final text = exhausted
        ? '잔여 회차를 모두 사용했어요. 충전 기능은 준비 중이에요 — 출시되면 여기서 바로 충전할 수 있도록 준비하고 있어요.'
        : '잔여 회차가 얼마 남지 않았어요. 충전 기능은 준비 중이에요 — 출시되면 여기서 바로 충전할 수 있도록 준비하고 있어요.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11.5,
          color: AppColors.warningText,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
