import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/ai_credentials_repository.dart';
import '../../../common/glass_card.dart';
import '../../radar/view_models/radar_view_model.dart';
import '../../radar/views/location_consent_sheet.dart';
import '../../radar/views/location_access_flow.dart';
import 'ai_connection_modal_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final radarViewModel = context.watch<RadarViewModel>();
    final aiCredentials = context.watch<AiCredentialsRepository>();
    final (statusTitle, statusMessage, statusColor) = _locationStatus(
      radarViewModel.locationAccessState,
    );

    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '설정',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 20),
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: radarViewModel.isRefreshingLocation
                              ? const SizedBox(
                                  width: 21,
                                  height: 21,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                  ),
                                )
                              : const Icon(
                                  Icons.location_on,
                                  color: AppColors.accent,
                                  size: 26,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      '위치 서비스',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    statusTitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                statusMessage,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: radarViewModel.isRefreshingLocation
                            ? null
                            : () => handleLocationAccessAction(
                                context,
                                radarViewModel,
                                openSettingsWhenReady: true,
                              ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(
                            color: AppColors.borderFunctional,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _locationActionLabel(
                            radarViewModel.locationAccessState,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('위치'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  _SettingsRow(
                    icon: Icons.radar_outlined,
                    title: '감지 반경',
                    subtitle: '가까운 인맥 목록에 표시할 거리',
                    value: _radiusLabel(radarViewModel.settings.radiusMeters),
                    onTap: () => _showRadiusPicker(context, radarViewModel),
                  ),
                  _SettingsRow(
                    icon: Icons.policy_outlined,
                    title: '위치정보 이용 안내',
                    subtitle: '이용 목적·저장 여부·동의 철회 확인',
                    onTap: () => showLocationUsePolicy(context),
                  ),
                  if (radarViewModel.hasLocationConsent)
                    _SettingsRow(
                      icon: Icons.location_disabled_outlined,
                      title: '위치 이용 동의 철회',
                      subtitle: _consentRecordedAt(radarViewModel),
                      titleColor: AppColors.destructive,
                      onTap: () =>
                          _confirmConsentWithdrawal(context, radarViewModel),
                    ),
                ],
              ),
              const SizedBox(height: 26),
              const _SectionTitle('데이터 및 개인정보'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  const _SettingsRow(
                    icon: Icons.badge_outlined,
                    title: '명함 데이터',
                    subtitle: '저장된 명함은 이 기기에 보관',
                    value: '로컬 저장',
                  ),
                  _SettingsRow(
                    icon: Icons.psychology_outlined,
                    title: 'AI 연결',
                    subtitle: aiCredentials.activeProvider == null
                        ? 'AI 기능을 사용하지 않는 상태'
                        : '${aiCredentials.activeProvider!.displayName} API 사용 중',
                    value: aiCredentials.activeProvider == null
                        ? '연결 안 됨'
                        : '연결됨',
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const AiConnectionModalView(),
                      );
                    },
                  ),
                  const _SettingsRow(
                    icon: Icons.info_outline,
                    title: 'AI 데이터 안내',
                    subtitle:
                        'AI 기능 실행 시 선택된 인맥 정보가 사용자가 연결한 AI 제공사로 전송될 수 있습니다.',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '현재 위치와 위치 이력은 서버에 저장하지 않습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
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

class _GroupedCard extends StatelessWidget {
  final List<Widget> children;

  const _GroupedCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              const Divider(height: 1, indent: 76, color: AppColors.borderDark),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: value == null ? '$title. $subtitle' : '$title. $value. $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  child: Icon(icon, color: AppColors.accentText, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: titleColor ?? AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    value!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showRadiusPicker(
  BuildContext context,
  RadarViewModel viewModel,
) async {
  final selected = await showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '감지 반경',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '가까운 인맥 목록에 표시할 최대 거리를 선택하세요.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            for (final option in const [500.0, 1000.0, double.infinity])
              ListTile(
                minTileHeight: 52,
                title: Text(_radiusLabel(option)),
                trailing: viewModel.settings.radiusMeters == option
                    ? const Icon(Icons.check_circle, color: AppColors.accent)
                    : const Icon(
                        Icons.circle_outlined,
                        color: AppColors.textMuted,
                      ),
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected != null) viewModel.updateRadius(selected);
}

Future<void> _confirmConsentWithdrawal(
  BuildContext context,
  RadarViewModel viewModel,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('위치 이용 동의를 철회할까요?'),
      content: const Text(
        '철회하면 현재 위치를 더 이상 조회하지 않고 주변 거리 기능을 중지합니다. 운영체제 권한은 기기 설정에서 별도로 변경할 수 있습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '동의 철회',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true) await viewModel.withdrawLocationConsent();
}

(String, String, Color) _locationStatus(LocationAccessState state) {
  return switch (state) {
    LocationAccessState.ready => (
      '사용 중',
      '주변 인맥과의 거리 계산에만 사용',
      const Color(0xFF2D7D46),
    ),
    LocationAccessState.loading || LocationAccessState.locating => (
      '확인 중',
      '기기의 위치 상태를 확인하고 있습니다.',
      AppColors.textSecondary,
    ),
    LocationAccessState.consentRequired => (
      '동의 필요',
      '앱의 위치 이용 안내를 확인해 주세요.',
      AppColors.accentText,
    ),
    LocationAccessState.consentDeclined => (
      '사용 안 함',
      '현재 명함 기능만 사용하고 있습니다.',
      AppColors.textSecondary,
    ),
    LocationAccessState.serviceDisabled => (
      '기기 위치 꺼짐',
      '기기 설정에서 위치 서비스를 켜 주세요.',
      AppColors.destructive,
    ),
    LocationAccessState.permissionDenied => (
      '권한 필요',
      '위치 권한이 없어 거리를 표시할 수 없습니다.',
      AppColors.destructive,
    ),
    LocationAccessState.permissionDeniedForever => (
      '권한 차단됨',
      '기기 설정에서 위치 권한을 허용해 주세요.',
      AppColors.destructive,
    ),
    LocationAccessState.unavailable => (
      '확인 실패',
      '현재 위치를 확인하지 못했습니다.',
      AppColors.destructive,
    ),
  };
}

String _locationActionLabel(LocationAccessState state) {
  return switch (state) {
    LocationAccessState.ready => '기기 권한 설정 열기',
    LocationAccessState.consentRequired ||
    LocationAccessState.consentDeclined => '위치 사용 안내 보기',
    LocationAccessState.permissionDenied => '위치 권한 허용',
    LocationAccessState.permissionDeniedForever => '앱 권한 설정 열기',
    LocationAccessState.serviceDisabled => '기기 위치 설정 열기',
    LocationAccessState.loading || LocationAccessState.locating => '확인 중',
    LocationAccessState.unavailable => '다시 확인',
  };
}

String _radiusLabel(double meters) {
  if (meters.isInfinite) return '제한 없음';
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(0)} km';
}

String _consentRecordedAt(RadarViewModel viewModel) {
  final date = viewModel.locationConsent.recordedAt;
  if (date == null) return '설정에서 언제든 철회할 수 있습니다.';
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} 동의';
}
