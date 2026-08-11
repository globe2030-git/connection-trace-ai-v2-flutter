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
            _TierGrid(tiers: config.tiers),
            const SizedBox(height: 26),
            const _SectionTitle('충전 안내'),
            const SizedBox(height: 10),
            const _GuideSection(),
          ],
        ),
      ),
    );
  }
}

/// 티어 카드를 세로로 나열하던 예전 방식은 7개 상품에서 화면을 지나치게
/// 많이 썼다(사용자 피드백, 2026-08-12). 2열 그리드로 압축해 대부분의
/// 화면 높이에서 스크롤 없이 한 번에 들어오게 한다. 티어 개수는 관리자
/// 콘솔이 늘리거나 줄일 수 있으므로 `itemCount`를 하드코딩하지 않는다.
class _TierGrid extends StatelessWidget {
  final List<BillingTier> tiers;

  const _TierGrid({required this.tiers});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiers.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, i) => _TierTile(tier: tiers[i]),
    );
  }
}

/// 압축 타일 하나 = 상품 하나. 개별 "구매" 버튼 대신 타일 자체가 비활성
/// 상태다(GlassCard 기본값인 `onTap: null` — 눌러도 반응이 없다). 우측 상단
/// 배지가 "충전 준비 중"을 알려 예전의 큰 아웃라인 버튼을 줄인 자리를
/// 대신한다.
class _TierTile extends StatelessWidget {
  final BillingTier tier;

  const _TierTile({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '₩${_formatWon(tier.priceKrw)}, ${tier.credits}회 충전, 충전 준비 중',
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bolt_outlined,
                    size: 16,
                    color: AppColors.accentText,
                  ),
                ),
                const _MiniBadge('준비중'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '₩${_formatWon(tier.priceKrw)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${tier.credits}회 충전',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 타일 우측 상단의 작은 상태 배지. 예전 `_DisabledChargeButton`(세로 44px
/// 아웃라인 버튼)을 그리드 타일 안에 그대로 넣으면 다시 커져 압축 효과가
/// 사라지므로, 같은 "비활성 = 회색 텍스트 + 옅은 테두리" 언어를 유지한 채
/// 훨씬 작은 알약 배지로 줄였다.
class _MiniBadge extends StatelessWidget {
  final String text;

  const _MiniBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

/// 충전 관련 사실 안내. 사용자 요청(2026-08-12)에 따라 화면 하단에 추가.
/// **여기 적힌 내용은 전부 현재 서버 동작·정책과 일치하는 사실만 담는다** —
/// 미구현 기능이나 확정되지 않은 정책은 쓰지 않는다(CLAUDE.md 4장).
class _GuideSection extends StatelessWidget {
  const _GuideSection();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _GuideItem(
            icon: Icons.cloud_done_outlined,
            text: '충전한 회차는 계정 기준으로 저장돼요. 기기를 바꿔도 그대로 유지됩니다.',
          ),
          SizedBox(height: 10),
          _GuideItem(
            icon: Icons.stacked_line_chart_outlined,
            text: '무료 제공 회차를 먼저 사용하고, 다 쓴 뒤에 충전한 회차가 차감돼요.',
          ),
          SizedBox(height: 10),
          _GuideItem(
            icon: Icons.campaign_outlined,
            text: '결제 기능은 아직 준비 중이에요. 오픈되면 앱 공지로 안내해 드릴게요.',
          ),
          // 환불 규정 확정 시 이 안내 섹션에 추가(검토 중) — 지금은 결제
          // 기능 자체가 없어 환불 규정도 미정이다. 확정 전까지 문구를
          // 지어내지 않는다(CLAUDE.md 4장 "가짜 데이터를 만들지 않는다").
        ],
      ),
    );
  }
}

class _GuideItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _GuideItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
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
