import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/app_version.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../../data/services/data_backup_service.dart';
import '../../../common/auth_gate.dart';
import '../../../common/glass_card.dart';
import '../../../common/legal_document_view.dart';
import 'open_source_notice_view.dart';
import '../../radar/view_models/radar_view_model.dart';
import '../../radar/views/location_consent_sheet.dart';
import '../../radar/views/location_access_flow.dart';
import '../../radar/views/my_profile_edit_modal_view.dart';
import 'ai_connection_modal_view.dart';
import 'inquiry_view.dart';
import 'notices_view.dart';

/// 전자상거래법 제10조에 따른 사업자 정보 표시. 웹(법적 고지 인덱스)에도
/// 같은 내용이 있고, 여기서는 앱 안에서 바로 볼 수 있게 한다.
Future<void> _showBusinessInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('사업자 정보'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('크림하우스주식회사', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('대표자  최우진'),
          Text('사업자등록번호  220-86-89511'),
          SizedBox(height: 8),
          Text('서울특별시 영등포구 양평로21가길 19,\n208·209호(양평동5가)'),
          SizedBox(height: 8),
          Text('문의  connectionsense@creamhouse.net'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final radarViewModel = context.watch<RadarViewModel>();
    final auth = context.watch<AuthRepository>();
    final myProfile = context.watch<MyProfileRepository>().profile;
    final (statusTitle, statusMessage, statusColor) = _locationStatus(
      radarViewModel.locationAccessState,
    );

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '설정',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              const _SectionTitle('계정'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  // 최초 설정 후에는 QR 코드 화면의 "내 프로필 설정하기" 버튼도
                  // 사라져서(이미 설정된 프로필엔 그 버튼 자체가 안 보임) 내
                  // 프로필을 다시 수정할 진입점이 앱 전체에 하나도 없었다
                  // (실기기 테스트로 발견) — 여기에 상시 진입점을 둔다.
                  _SettingsRow(
                    icon: const AppIcon(
                      AppIconId.editCard,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    title: '내 프로필',
                    subtitle: myProfile.isSetUp
                        ? [
                            myProfile.title,
                            myProfile.company,
                          ].where((s) => s.trim().isNotEmpty).join(' · ')
                        : '아직 설정하지 않았습니다',
                    onTap: () => MyProfileEditModalView.show(context),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.account_circle_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: auth.displayName ?? '로그인됨',
                    subtitle: [
                      if (auth.provider != null) auth.provider!.displayName,
                      if (auth.email != null) auth.email!,
                    ].join(' · '),
                  ),
                  _SettingsRow(
                    icon: const AppIcon(
                      AppIconId.logout,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    title: '로그아웃',
                    subtitle: '이 기기에 저장된 로그인 정보를 지웁니다',
                    titleColor: AppColors.destructive,
                    onTap: () => _confirmSignOut(context, auth),
                  ),
                  _SettingsRow(
                    icon: const AppIcon(
                      AppIconId.accountDelete,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    // "회원 탈퇴"를 함께 적는다(사용자 요청, 2026-08-10).
                    // 스토어 심사와 이용약관은 "탈퇴"라는 말을 쓰고, 사용자도
                    // 그 말로 찾는다. 반면 실제로 일어나는 일은 계정과 서버
                    // 데이터 삭제라 두 표현을 한 줄에 붙여 둔다.
                    title: '계정 삭제 (회원 탈퇴)',
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
                  // "주변 인맥 감지" 스위치는 여기 없다. "주변" 화면의 위치
                  // 아이콘을 **길게 눌러** 켜고 끈다(사용자 결정, 2026-08-10).
                  // 켜고 끈 결과가 곧바로 나타나는 화면이 그쪽이라, 설정에서
                  // 켜 놓고 다른 화면으로 옮겨 확인할 이유가 없었다.
                  // 감지 반경 행은 여기 없다. "주변" 화면 위쪽에 선택 버튼이
                  // 있고, 그 화면이 바로 결과(주변 인맥 목록)를 보여 준다.
                  // 처음에는 현재 값만 알려주는 행을 남겼는데, 바꾸지도 못하는
                  // 항목이 설정에 앉아 있으면 오히려 "여기서 바꾸는 것"으로
                  // 오해하게 만든다는 판단으로 아예 뺐다(추가 140).
                  _SettingsRow(
                    icon: const AppIcon(
                      AppIconId.locationInfo,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    title: '위치정보 이용 안내',
                    subtitle: '이용 목적·저장 여부·동의 철회 확인',
                    onTap: () => showLocationUsePolicy(context),
                  ),
                  if (radarViewModel.hasLocationConsent)
                    _SettingsRow(
                      icon: const AppIcon(
                        AppIconId.consentRevoke,
                        size: 22,
                        color: AppColors.accentText,
                      ),
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
                    icon: AppIcon(
                      AppIconId.cardData,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    title: '명함 데이터',
                    subtitle: '이 기기와 서버에 암호화하여 보관',
                    value: '로컬 + 서버 백업',
                  ),
                  _SettingsRow(
                    icon: const AppIcon(
                      AppIconId.aiChip,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    // "AI 연결"은 개발자 용어였다 — 사용자가 이 항목에서 실제로
                    // 확인하는 것은 남은 생성 횟수다(사용자 요청, 2026-08-10).
                    title: 'AI 잔여 횟수',
                    subtitle: AiBriefingService.kAiServiceDeployed
                        ? '커넥션센스 AI가 대화 포인트를 만들어드려요'
                        : '서비스 준비 중이에요',
                    value: AiBriefingService.kAiServiceDeployed
                        ? '이용 가능'
                        : '준비 중',
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
                    icon: AppIcon(
                      AppIconId.aiDataInfo,
                      size: 22,
                      color: AppColors.accentText,
                    ),
                    title: 'AI 데이터 안내',
                    subtitle: 'AI 기능 실행 시 선택된 인맥 정보가 회사 서버를 거쳐 AI로 전송될 수 있습니다.',
                  ),
                ],
              ),
              const SizedBox(height: 26),
              // 앱 안에서 약관·방침으로 갈 수 있는 경로가 없으면 이용자가
              // 확인할 방법이 사실상 없다(스토어 심사에서도 요구된다).
              // 문서 본문은 Firebase Hosting에 올려 두고 웹뷰로 띄운다 —
              // 앱에 문안을 복사해 두면 개정 시 두 벌이 어긋난다.
              const _SectionTitle('약관 및 정책'),
              const SizedBox(height: 10),
              _GroupedCard(
                children: [
                  _SettingsRow(
                    icon: const Icon(
                      Icons.description_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: LegalDocument.terms.title,
                    subtitle: '서비스 이용 조건과 회사·이용자의 권리·의무',
                    onTap: () =>
                        showLegalDocument(context, LegalDocument.terms),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.privacy_tip_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: LegalDocument.privacy.title,
                    subtitle: '수집 항목, 보유 기간, 국외 이전, 이용자의 권리',
                    onTap: () =>
                        showLegalDocument(context, LegalDocument.privacy),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: LegalDocument.permissions.title,
                    subtitle: '위치·카메라·사진 접근 사유와 철회 방법',
                    onTap: () =>
                        showLegalDocument(context, LegalDocument.permissions),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.code_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: '오픈소스 라이선스',
                    subtitle: '이 앱이 사용하는 오픈소스 목록',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OpenSourceNoticeView(
                          applicationName: '커넥션센스',
                          applicationVersion: AppVersion.versionOnly,
                          applicationLegalese: '© 2026 크림하우스주식회사',
                        ),
                      ),
                    ),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.business_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: '사업자 정보',
                    subtitle: '상호·대표자·사업자등록번호·문의처',
                    onTap: () => _showBusinessInfo(context),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.info_outline,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: '앱 버전',
                    subtitle: '커넥션센스',
                    // 실행 중인 빌드를 그대로 보여준다 — 낡은 빌드를 버그로
                    // 오인하는 일을 막기 위함(backlog 추가 77).
                    value: AppVersion.display,
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
                    icon: const Icon(
                      Icons.campaign_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: '공지사항',
                    subtitle: '업데이트·점검 안내를 확인하세요',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NoticesView()),
                    ),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.support_agent_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
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
              const Divider(
                height: 1,
                indent: 76,
                color: AppColors.borderSubtle,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  /// [Icon] 또는 [AppIcon] — 크기/색은 호출부에서 직접 지정한다(22px,
  /// [AppColors.accentText]) 두 위젯 모두 동일 규칙을 따르게 하기 위해서다.
  final Widget icon;
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
                  child: icon,
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
///
/// **어느 계정이 지워지는지 반드시 화면에 보여준다.** 예전에는 "이 계정"이라고만
/// 적혀 있었는데, 2026-08-08에 실제로 사고가 났다 — Google과 Apple 두 계정을
/// 오가며 테스트하던 중 의도와 다른 계정이 삭제돼 서버 명함 9건이 사라졌다.
/// 계정 삭제는 서버 데이터뿐 아니라 **암호화 키(`users/{uid}.encryptionKeyB64`)도
/// 함께 지우기 때문에**, 다른 기기에 남아 있던 로컬 사본까지 열 수 없게 된다.
/// 즉 잘못 누르면 되돌릴 방법이 없다.
Future<void> _confirmDeleteAccount(
  BuildContext context,
  AuthRepository auth,
) async {
  // 이메일이 가장 알아보기 쉽지만 항상 있지는 않다 — Apple은 "이메일 가리기"를
  // 쓰거나 최초 1회 이후로는 이메일을 내려주지 않는다(auth_repository 주석).
  // 그래서 이름 → uid 앞자리 순으로 물러난다. 무엇이든 화면에 보여야 한다.
  final accountLabel =
      auth.email ?? auth.displayName ?? '${auth.firebaseUid?.substring(0, 8)}…';
  final providerName = auth.provider?.displayName;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('계정을 삭제할까요?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.destructive.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '삭제할 계정',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  accountLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.destructive,
                  ),
                ),
                if (providerName != null)
                  Text(
                    '$providerName 로그인',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '이 계정으로 서버에 백업된 명함·프로필 데이터가 함께 영구적으로 '
            '삭제됩니다. 다른 기기에 남아 있는 데이터도 열 수 없게 됩니다.\n\n'
            '이 작업은 되돌릴 수 없습니다.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          // 버튼 라벨은 "무엇이 일어나는지"를 말해야 한다. 예전 라벨
          // ("정말 삭제하시겠습니까")은 질문형이라 버튼으로 어색했고, 확인
          // 다이얼로그에서 취소와 실행을 순간적으로 헷갈리게 만든다.
          child: const Text(
            '영구 삭제',
            style: TextStyle(
              color: AppColors.destructive,
              fontWeight: FontWeight.w700,
            ),
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
    // 다른 기기에서 이미 삭제된 계정이면 서버엔 지울 게 없다. 이 경우 서버
    // 요청(토큰 갱신 실패로 "네트워크 오류"처럼 보임)을 아예 건너뛰고, 이
    // 기기의 로컬 데이터만 정리한 뒤 로그아웃시킨다.
    if (await auth.isAccountAlreadyDeleted()) {
      await contactsRepo.clearLocal();
      await profileRepo.clearLocal();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(kLastSignedInUidPrefsKey);
      } catch (e) {
        debugPrint('계정 삭제 후 마지막 로그인 uid 정리 실패: $e');
      }
      await auth.signOut();
      if (context.mounted) _dismissLoadingDialog(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('이미 다른 기기에서 삭제된 계정이에요. 이 기기에서도 로그아웃했어요.'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
      return;
    }

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

String _consentRecordedAt(RadarViewModel viewModel) {
  final date = viewModel.locationConsent.recordedAt;
  if (date == null) return '설정에서 언제든 철회할 수 있습니다.';
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} 동의';
}
