import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../../data/services/data_backup_service.dart';
import '../../../common/auth_gate.dart';
import '../../../common/glass_card.dart';
import '../../radar/view_models/radar_view_model.dart';
import '../../radar/views/location_consent_sheet.dart';
import '../../radar/views/location_access_flow.dart';
import 'ai_connection_modal_view.dart';
import 'inquiry_view.dart';
import 'notices_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final radarViewModel = context.watch<RadarViewModel>();
    final auth = context.watch<AuthRepository>();
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
              const _SectionTitle('계정'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  _SettingsRow(
                    icon: Icons.account_circle_outlined,
                    title: auth.displayName ?? '로그인됨',
                    subtitle: [
                      if (auth.provider != null) auth.provider!.displayName,
                      if (auth.email != null) auth.email!,
                    ].join(' · '),
                  ),
                  _SettingsRow(
                    icon: Icons.logout,
                    title: '로그아웃',
                    subtitle: '이 기기에 저장된 로그인 정보를 지웁니다',
                    titleColor: AppColors.destructive,
                    onTap: () => _confirmSignOut(context, auth),
                  ),
                  _SettingsRow(
                    icon: Icons.person_remove_outlined,
                    title: '계정 삭제',
                    subtitle: '계정과 서버에 백업된 명함·프로필 데이터를 영구 삭제합니다',
                    titleColor: AppColors.destructive,
                    onTap: () => _confirmDeleteAccount(context, auth),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: radarViewModel.isRefreshingLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accent,
                                  ),
                                )
                              : const Icon(
                                  Icons.location_on,
                                  color: AppColors.accent,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '위치 서비스',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '주변 인맥과의 거리 계산에만 사용',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
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
                    if (radarViewModel.locationAccessState !=
                        LocationAccessState.ready) ...[
                      const SizedBox(height: 10),
                      Text(
                        statusMessage,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                            minimumSize: const Size.fromHeight(46),
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
                  ],
                ),
              ),
              const SizedBox(height: 26),
              const _SectionTitle('위치 및 알림'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  _SettingsSwitchRow(
                    icon: Icons.podcasts_outlined,
                    title: '주변 인맥 감지',
                    subtitle: radarViewModel.hasLocationConsent
                        ? '위치 사용에 동의했습니다'
                        : '꺼져 있으면 주변 거리 기능을 쓸 수 없습니다',
                    value: radarViewModel.hasLocationConsent,
                    onChanged: radarViewModel.isRefreshingLocation
                        ? null
                        : (turnOn) => turnOn
                              ? radarViewModel.acceptLocationConsent()
                              : _confirmConsentWithdrawal(
                                  context,
                                  radarViewModel,
                                ),
                  ),
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
                    subtitle: AiBriefingService.kAiServiceDeployed
                        ? '커넥션센스 AI가 대화 포인트를 만들어드려요'
                        : '서비스 준비 중이에요',
                    value: AiBriefingService.kAiServiceDeployed ? '이용 가능' : '준비 중',
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
                        'AI 기능 실행 시 선택된 인맥 정보가 회사 서버를 거쳐 AI로 전송될 수 있습니다.',
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
              const SizedBox(height: 26),
              const _SectionTitle('지원'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  _SettingsRow(
                    icon: Icons.campaign_outlined,
                    title: '공지사항',
                    subtitle: '업데이트·점검 안내를 확인하세요',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NoticesView()),
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.support_agent_outlined,
                    title: '1:1 문의',
                    subtitle: '궁금한 점을 남겨주시면 답변드립니다',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InquiryView()),
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

/// `_SettingsRow`와 같은 시각적 스타일이지만 끝에 스위치가 붙는 행. 실제
/// 상태(예: 위치 이용 동의 여부)와 연결해서만 쓸 것 — 아무 상태도 바꾸지
/// 않는 장식용 토글은 절대 추가하지 않는다.
class _SettingsSwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
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
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.accent,
            ),
          ],
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

Future<void> _confirmSignOut(BuildContext context, AuthRepository auth) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('로그아웃할까요?'),
      content: const Text('다시 사용하려면 SNS 계정으로 다시 로그인해야 합니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '로그아웃',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true) await auth.signOut();
}

/// 계정 삭제(backlog #49) 확인 다이얼로그. 로그아웃과 달리 되돌릴 수 없고
/// 서버 데이터까지 함께 지워진다는 점을 명시적으로 안내한다.
Future<void> _confirmDeleteAccount(
  BuildContext context,
  AuthRepository auth,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('계정을 삭제할까요?'),
      content: const Text(
        '계정을 삭제하면 이 계정으로 서버에 백업된 명함·프로필 데이터가 함께 '
        '영구적으로 삭제됩니다.\n\n이 작업은 되돌릴 수 없습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '정말 삭제하시겠습니까',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  await _performAccountDeletion(context, auth);
}

/// 실제 삭제 흐름 — 순서가 중요하다:
/// 1) Firestore 서버 데이터 삭제(아직 인증된 상태일 때만 보안 규칙 통과)
/// 2) Firebase Auth 계정 삭제(재인증 필요 시 사용자에게 안내 후 재시도)
/// 3) 로컬 저장 데이터(명함/프로필) 초기화
///
/// 기존 백업 로직과 달리 실패를 조용히 삼키지 않는다 — 각 단계 실패는
/// 사용자에게 명확한 에러 메시지로 알린다(서버에 데이터가 남았는데 사용자는
/// 삭제됐다고 믿는 상황을 방지).
Future<void> _performAccountDeletion(
  BuildContext context,
  AuthRepository auth,
) async {
  final contactsRepo = context.read<ContactsRepository>();
  final profileRepo = context.read<MyProfileRepository>();
  final uid = auth.firebaseUid;

  _showLoadingDialog(context);

  try {
    if (uid != null) {
      await DataBackupService.deleteAllUserData(uid);
    }

    try {
      await auth.deleteFirebaseAccountAndLocalSession();
    } on AuthException catch (e) {
      if (!e.requiresReauth) rethrow;

      if (context.mounted) _dismissLoadingDialog(context);
      if (!context.mounted) return;
      // provider별 재인증 메서드(Google/Apple)로 갈라 부르지 않고
      // reauthenticateCurrentProvider() 하나로 통일 — 로그인 수단이 늘어나도
      // 이 화면은 분기를 추가할 필요가 없다.
      final providerName = auth.provider?.displayName ?? 'SNS';
      final wantsReauth = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('다시 로그인이 필요합니다'),
          content: Text(
            '보안을 위해 계정을 삭제하려면 다시 로그인해야 합니다. 지금 $providerName 계정으로 '
            '다시 로그인할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('다시 로그인'),
            ),
          ],
        ),
      );
      if (wantsReauth != true) return;
      if (!context.mounted) return;

      _showLoadingDialog(context);
      await auth.reauthenticateCurrentProvider();
      await auth.deleteFirebaseAccountAndLocalSession();
    }

    await contactsRepo.clearLocal();
    await profileRepo.clearLocal();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLastSignedInUidPrefsKey);
    } catch (e) {
      debugPrint('계정 삭제 후 마지막 로그인 uid 정리 실패: $e');
    }

    if (context.mounted) _dismissLoadingDialog(context);
    // 성공 시 auth.isSignedIn이 false가 되어 AuthGate가 자동으로 로그인
    // 화면으로 전환한다(로그아웃과 동일한 종착점).
  } catch (e) {
    if (context.mounted) _dismissLoadingDialog(context);
    if (context.mounted) _showAccountDeletionError(context, e);
  }
}

void _showLoadingDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

void _dismissLoadingDialog(BuildContext context) {
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

void _showAccountDeletionError(BuildContext context, Object error) {
  final message = error is AuthException
      ? error.message
      : '계정 삭제 중 오류가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AppColors.destructive),
  );
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
