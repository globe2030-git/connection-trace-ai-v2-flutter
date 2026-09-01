import 'package:flutter/material.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/services/ai_usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import 'ai_charge_view.dart';

/// AI 대화 브리핑 기능 안내 화면.
///
/// 예전에는 사용자가 Claude/ChatGPT/Gemini API 키를 직접 발급받아 연동하는
/// BYOK 방식이었지만, 진입장벽이 너무 높다는 판단에 따라 커넥션센스가 자체
/// 제공하는 AI(서버 프록시, [AiBriefingService] 참고)로 전환했다. 이제
/// 사용자가 할 일은 없고, 이 화면은 기능 소개와 사용량 한도만 안내한다.
class AiConnectionModalView extends StatefulWidget {
  const AiConnectionModalView({super.key});

  @override
  State<AiConnectionModalView> createState() => _AiConnectionModalViewState();
}

class _AiConnectionModalViewState extends State<AiConnectionModalView> {
  // 서버가 세는 잔여 횟수(uid 기준). 같은 계정이면 기기 간 공유된다.
  AiUsage? _usage;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final usage = await AiUsageService.fetch();
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
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

              Row(
                children: [
                  const Text(
                    'AI 연동',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: AppIcon(
                    AppIconId.aiChip,
                    size: 24,
                    color: AppColors.accentText,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'AI 대화 브리핑',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              // 왼쪽 정렬 + 전체 폭(SizedBox)로 늘려야 실제로 카드 왼쪽 끝에
              // 붙는다 — 가운데 정렬은 자동 줄바꿈 시 두 번째 줄이 첫 줄과
              // 안 맞아 보였다(사용자 제보, 2026-08-12).
              const SizedBox(
                width: double.infinity,
                child: Text(
                  '커넥션센스가 제공하는 AI가 자동으로 대화 포인트를 만들어드려요.',
                  textAlign: TextAlign.left,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              _StatusBanner(deployed: AiBriefingService.kAiServiceDeployed),
              const SizedBox(height: 16),

              // 잔여 횟수를 서버에서 읽어 상시 표시한다(동의 화면 말고도 여기서
              // 언제든 확인 가능). 아직 못 읽었으면(로딩/오프라인) 한도만 안내.
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: usage == null ? '하루 한도' : '오늘 사용',
                      value: usage == null
                          ? '${AiBriefingService.dailyLimit}회'
                          : '${usage.dailyUsed}회',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: usage == null ? '이번 달 한도' : '잔여',
                      value: usage == null
                          ? '${AiBriefingService.monthlyLimit}회'
                          : '${usage.totalRemaining}회',
                    ),
                  ),
                ],
              ),
              if (usage != null) ...[
                // 무료/보너스 분리 문구는 reset 모드 전용이다 — wallet
                // 모드는 두 버킷(무료체험/충전)을 화면 어디에도 분리
                // 노출하지 않는다(스펙 §5, 합산 숫자 하나만).
                if (!usage.isWalletMode && usage.bonusCredits > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '무료 ${usage.remaining}회 + 충전/보너스 ${usage.bonusCredits}회',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const SizedBox(
                  width: double.infinity,
                  child: Text(
                    '같은 계정이면 기기와 상관없이 함께 차감돼요.',
                    textAlign: TextAlign.left,
                    style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                  ),
                ),
                if (usage.lowBalance || usage.exhausted) ...[
                  const SizedBox(height: 12),
                  _LowBalanceBanner(exhausted: usage.exhausted),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool deployed;
  const _StatusBanner({required this.deployed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderFunctional),
      ),
      child: Text(
        deployed
            ? '무료로 제공돼요 — 별도 설정 없이 바로 사용할 수 있어요.'
            : '서비스 준비 중 — 곧 제공될 예정이에요.',
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    );
  }
}

/// 잔여 회차가 얼마 없거나 소진됐을 때 보여주는 인라인 안내(스낵바 대신).
/// reset/wallet 두 모드 공통으로 쓴다 — reset 모드에서도 잔여가 적으면
/// 충전 화면으로 보내는 게 자연스럽고, [AiChargeView] 자체가 아직 결제는
/// 비활성인 "상품 안내" 화면이라 두 모드 모두에서 지금 열어도 문제가 없다.
class _LowBalanceBanner extends StatelessWidget {
  final bool exhausted;
  const _LowBalanceBanner({required this.exhausted});

  @override
  Widget build(BuildContext context) {
    final text = exhausted
        ? '잔여 회차를 모두 사용했어요. 충전 화면에서 상품을 확인해 보세요.'
        : '잔여 회차가 얼마 남지 않았어요. 충전 화면에서 상품을 확인해 보세요.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.warningText,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AiChargeView(),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                foregroundColor: AppColors.warningText,
                side: const BorderSide(color: AppColors.warningText),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                '충전하러 가기',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
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
