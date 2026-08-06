import 'package:flutter/material.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/theme/app_colors.dart';

/// AI 대화 브리핑 기능 안내 화면.
///
/// 예전에는 사용자가 Claude/ChatGPT/Gemini API 키를 직접 발급받아 연동하는
/// BYOK 방식이었지만, 진입장벽이 너무 높다는 판단에 따라 커넥션센스가 자체
/// 제공하는 AI(서버 프록시, [AiBriefingService] 참고)로 전환했다. 이제
/// 사용자가 할 일은 없고, 이 화면은 기능 소개와 사용량 한도만 안내한다.
class AiConnectionModalView extends StatelessWidget {
  const AiConnectionModalView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
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
                    color: AppColors.borderDark,
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
              const Text(
                '커넥션센스가 제공하는 AI가 자동으로 대화 포인트를 만들어드려요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),

              _StatusBanner(deployed: AiBriefingService.kAiServiceDeployed),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: '하루',
                      value: '${AiBriefingService.dailyLimit}회',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      label: '이번 달',
                      value: '${AiBriefingService.monthlyLimit}회',
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

class _StatusBanner extends StatelessWidget {
  final bool deployed;
  const _StatusBanner({required this.deployed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSlate,
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSlate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
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
