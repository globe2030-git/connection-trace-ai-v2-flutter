import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/billing_config_model.dart';
import '../../../../data/repositories/billing_config_repository.dart';
import '../../../common/glass_card.dart';

/// AI 충전 화면.
///
/// 과금 방향(무료 N회 후 충전·선불, backlog 확정)에 따라 신규 가입 무료
/// 횟수와 관리자 콘솔(`docs/admin/admin.js`)이 관리하는 `config/billing`
/// 판매 상품을 보여준다.
///
/// **이번 화면 범위에 실제 결제는 없다.** 스토어에 상품ID가 아직 등록되지
/// 않았고 `in_app_purchase` 연동도 다음 단계다 — 그래서 상품 카드의 구매
/// 자리는 항상 눌러도 아무 일도 일어나지 않는 비활성 "충전 준비 중" 버튼
/// 이다. 결제되는 척하는 가짜 동작은 이 프로젝트에서 가장 엄격히 금지하는
/// 규칙이다(CLAUDE.md 4장 "가짜 데이터를 만들지 않는다").
class AiChargeView extends StatefulWidget {
  const AiChargeView({super.key});

  @override
  State<AiChargeView> createState() => _AiChargeViewState();
}

enum _LoadState { loading, error, loaded }

class _AiChargeViewState extends State<AiChargeView> {
  final _repo = BillingConfigRepository();

  _LoadState _state = _LoadState.loading;
  BillingConfig? _config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final config = await _repo.fetchConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      // 사용자에게는 원문 예외를 보여주지 않는다 — 개발자가 원인을 찾을
      // 최소 단서(예외 타입)만 남긴다. 이 화면엔 개인정보가 없다.
      debugPrint('AI 충전 상품 조회 실패(${e.runtimeType})');
      if (!mounted) return;
      setState(() => _state = _LoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('AI 충전'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: switch (_state) {
        _LoadState.loading => const _ChargeLoading(),
        _LoadState.error => _ChargeError(onRetry: _load),
        _LoadState.loaded => _buildLoaded(),
      },
    );
  }

  Widget _buildLoaded() {
    final config = _config;
    if (config == null || config.tiers.isEmpty) {
      return const _ChargeEmpty();
    }
    return _ChargeContent(config: config);
  }
}

class _ChargeLoading extends StatelessWidget {
  const _ChargeLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.accent),
    );
  }
}

class _ChargeError extends StatelessWidget {
  final VoidCallback onRetry;

  const _ChargeError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 34,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              '충전 상품 정보를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(120, 44),
                foregroundColor: AppColors.accentText,
                side: const BorderSide(color: AppColors.borderFunctional),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargeEmpty extends StatelessWidget {
  const _ChargeEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer_outlined,
              size: 34,
              color: AppColors.textMuted,
            ),
            SizedBox(height: 12),
            Text(
              '지금은 판매 중인 충전 상품이 없어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '준비되는 대로 이 화면에서 안내해 드릴게요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargeContent extends StatelessWidget {
  final BillingConfig config;

  const _ChargeContent({required this.config});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FreeCreditsBanner(freeCredits: config.freeCredits),
            const SizedBox(height: 26),
            const _SectionTitle('충전 상품'),
            const SizedBox(height: 10),
            for (var i = 0; i < config.tiers.length; i++) ...[
              _TierCard(tier: config.tiers[i]),
              if (i < config.tiers.length - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 18),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.textMuted,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '충전 기능은 준비 중입니다. 출시 후 다시 안내드릴게요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeCreditsBanner extends StatelessWidget {
  final int freeCredits;

  const _FreeCreditsBanner({required this.freeCredits});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const AppIcon(
              AppIconId.aiChip,
              size: 22,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '가입 시 무료 $freeCredits회 제공',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  '별도 결제 없이 AI 대화 포인트를 사용해 볼 수 있어요.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final BillingTier tier;

  const _TierCard({required this.tier});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.bolt_outlined,
              size: 22,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₩${_formatWon(tier.priceKrw)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${tier.credits}회 충전',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _DisabledChargeButton(),
        ],
      ),
    );
  }
}

/// 결제 준비 전 자리표시자 버튼. **절대 실제 동작(다이얼로그·스낵바 포함)을
/// 하지 않는다** — `onPressed: null`로 고정해 시각적으로도 눌리지 않음이
/// 분명하게 만든다(회색 텍스트 + 옅은 테두리, 기본 카드 배경과 대비되게).
class _DisabledChargeButton extends StatelessWidget {
  const _DisabledChargeButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: null,
      style: OutlinedButton.styleFrom(
        disabledForegroundColor: AppColors.textMuted,
        side: const BorderSide(color: AppColors.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: const Text(
        '충전 준비 중',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 1,000 단위 콤마만 넣는 최소 헬퍼 — 이 화면은 원화 정수 가격만 다뤄서
/// `intl`의 `NumberFormat`을 새로 끌어올 필요가 없다.
String _formatWon(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
