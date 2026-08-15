import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/app_version.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/seeded_memo_cleanup.dart';
import '../../../../core/utils/seeded_tag_cleanup.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/services/card_photo_backup_service.dart';
import '../../../../core/services/contact_image_service.dart';
import '../../../../core/services/encryption_key_service.dart';
import '../../../../core/services/photo_improvement_consent_service.dart';
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
import 'ai_charge_view.dart';
import 'ai_connection_modal_view.dart';
import 'inquiry_view.dart';
import 'notices_view.dart';
import 'ocr_stats_view.dart';
import 'admin_inquiry_view.dart';
import 'ocr_batch_scan_view.dart';

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
                  // 사진 개선 동의는 **선택**이다 — 꺼도 명함 등록·복원·보정이
                  // 전부 그대로 동작한다. 이 토글이 정하는 것은 "내 사진을
                  // 인식 개선용 표본에 넣어도 되는가" 하나뿐이다(추가 218).
                  //
                  // ⚠️ 사진 서버 저장이 꺼져 있으면 이 토글도 **보이지 않는다.**
                  // 이유 둘:
                  // 1) 저장하지 않는 사진에 대한 개선 동의는 **아무 뜻이 없다.**
                  // 2) 동의 필드를 허용하는 `firestore.rules`가 아직 배포 전이라,
                  //    켜면 서버 쓰기가 거부돼 "저장하지 못했어요"만 뜬다. 테스터
                  //    빌드에 그대로 나가면 **고장난 기능으로 보인다**(2026-08-15,
                  //    빌드 직전에 발견).
                  // 플래그를 켤 때 rules 배포도 함께 해야 이 토글이 동작한다.
                  if (CardPhotoBackupService.kCardPhotoBackupEnabled)
                    _PhotoImprovementConsentRow(uid: auth.firebaseUid),
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
                  // "AI 데이터 안내" 행은 뺐다(사용자 요청, 2026-08-10).
                  // 같은 내용이 **개인정보처리방침 11조**에 더 정확하게 들어
                  // 있다 — 전달 경로(기기 → 회사 서버 → Gemini), 요청마다
                  // 동의를 받는다는 것, 전송 항목의 한정, 서버가 내용을
                  // 저장하지 않는다는 것까지. 설정의 한 줄은 그 일부를 요약한
                  // 것이라 두 벌을 관리하면 개정할 때 어긋난다.
                  //
                  // 방침으로 가는 경로는 바로 아래 "약관 및 정책"에 있고,
                  // AI 전송 동의 화면에도 "자세히" 버튼이 있다.
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
                    // 앱에 값을 복사해 두지 않고 법적 고지 페이지를 연다
                    // (2026-08-10). 예전에는 여기서 하드코딩한 다이얼로그를
                    // 띄웠는데, 주소나 대표자가 바뀌면 **앱을 고쳐 다시
                    // 배포해야** 값이 맞았다. 약관·방침 본문을 앱에 복사하지
                    // 않는 것과 같은 이유다.
                    onTap: () =>
                        showLegalDocument(context, LegalDocument.legalIndex),
                  ),
                  _SettingsRow(
                    icon: const Icon(
                      Icons.document_scanner_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: '명함 인식 진단',
                    subtitle: '자동 인식 품질을 값 없이 형태로만 확인',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OcrStatsView()),
                    ),
                  ),
                  // 관리자 계정에서만 보인다. 조건 없이 두면 일반 사용자에게도
                  // 메뉴가 보이고, 눌러도 서버 규칙이 막아 권한 오류만 뜬다
                  // (2026-08-13 실기기 확인, backlog 추가 178).
                  if (auth.isAdmin)
                    _SettingsRow(
                      icon: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: AppColors.accentText,
                        size: 22,
                      ),
                      title: '관리자 1:1 문의 관리',
                      subtitle: '사용자 이름 및 이메일로 문의 검색·답변',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AdminInquiryManagementView(),
                        ),
                      ),
                    ),
                  if (auth.isAdmin)
                    _SettingsRow(
                      icon: const Icon(
                        Icons.grid_view_outlined,
                        color: AppColors.accentText,
                        size: 22,
                      ),
                      title: '명함 일괄 스캔 (관리자)',
                      subtitle: '여러 장을 한 번에 스캔해 인식 결과를 표로 확인',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OcrBatchScanView(),
                        ),
                      ),
                    ),
                  if (auth.isAdmin)
                    _SettingsRow(
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        color: AppColors.accentText,
                        size: 22,
                      ),
                      title: '잘못 채워진 태그 정리 (관리자)',
                      subtitle: '기본값 "AI, IT"만 그대로 남은 명함의 태그를 비움',
                      onTap: () => _confirmSeededTagCleanup(context),
                    ),
                  if (auth.isAdmin)
                    _SettingsRow(
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        color: AppColors.accentText,
                        size: 22,
                      ),
                      title: '자동 삽입된 메모 정리 (관리자)',
                      subtitle: '스캔이 넣던 안내 문구만 그대로 남은 명함의 메모를 비움',
                      onTap: () => _confirmSeededMemoCleanup(context),
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
                  _SettingsRow(
                    icon: const Icon(
                      Icons.bolt_outlined,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    title: 'AI 충전',
                    subtitle: '무료 횟수 소진 후 충전 상품 안내',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AiChargeView()),
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

/// "명함 사진을 인식 기능 개선에 써도 된다"는 **별도 동의** 토글.
///
/// ## 이 토글이 정하지 *않는* 것
///
/// 사진의 서버 저장·복원, 그리고 **내 명함 정보가 잘못 인식됐을 때 원본과
/// 대조해 바로잡는 일**은 계약 이행이라 이 토글과 무관하게 동작한다. 여기서
/// 정하는 것은 오직 **"여러 이용자의 사진을 함께 이용한 인식 알고리즘 개선에
/// 내 사진을 포함해도 되는가"** 하나다(개인정보처리방침 v2.2 2-1/2-2,
/// backlog 추가 218).
///
/// 그래서 부제에 "끄셔도 모든 기능을 그대로 쓰실 수 있어요"를 항상 보여준다 —
/// 동의하지 않으면 손해를 본다는 인상을 주면 그건 자유로운 동의가 아니다.
///
/// ## 로그인 전에는 끄고 잠근다
///
/// 동의는 계정에 붙는 기록이라 [uid]가 없으면 서버에 남길 수 없다. 그 상태에서
/// 켜지게 두면 **기기에만 켜진 동의**가 생겨, 회사는 동의를 못 받았는데
/// 사용자 화면에는 동의한 것처럼 보인다. 그래서 로그인 전에는 스위치를
/// 비활성화한다.
class _PhotoImprovementConsentRow extends StatefulWidget {
  const _PhotoImprovementConsentRow({required this.uid});

  final String? uid;

  @override
  State<_PhotoImprovementConsentRow> createState() =>
      _PhotoImprovementConsentRowState();
}

class _PhotoImprovementConsentRowState
    extends State<_PhotoImprovementConsentRow> {
  final _service = PhotoImprovementConsentService();
  bool _consented = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 서버 값을 우선한다 — 기기를 바꾸면 로컬은 비어 있는데 서버에는 동의가
    // 남아 있어, 이미 동의한 사용자에게 토글이 꺼진 것처럼 보인다.
    final uid = widget.uid;
    final value = uid == null
        ? await _service.load()
        : await _service.sync(uid);
    if (!mounted) return;
    setState(() => _consented = value);
  }

  Future<void> _toggle(bool next) async {
    final uid = widget.uid;
    if (uid == null || _busy) return;

    // 낙관적으로 먼저 바꾼다 — 스위치가 손가락을 따라오지 않으면 고장으로
    // 보인다. 실패하면 되돌리고 이유를 알린다.
    setState(() {
      _consented = next;
      _busy = true;
    });
    final ok = await _service.setConsent(uid: uid, consented: next);
    if (!mounted) return;
    setState(() {
      if (!ok) _consented = !next;
      _busy = false;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.uid != null;
    final subtitle = signedIn
        ? '끄셔도 모든 기능을 그대로 쓰실 수 있어요'
        : '로그인하면 설정할 수 있어요';

    return Semantics(
      toggled: _consented,
      label: '명함 인식 개선에 사진 제공. $subtitle',
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
                child: const AppIcon(
                  AppIconId.scanCard,
                  size: 22,
                  color: AppColors.accentText,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '명함 인식 개선에 사진 제공',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: _consented,
                onChanged: signedIn && !_busy ? _toggle : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
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

/// 로그아웃과 계정 삭제는 서로 배타적인 동작이라 동시에 진행되면 안 된다.
///
/// `AuthRepository.signOut()`은 Google/Firebase 서버 호출을 기다린 **뒤에야**
/// `isSignedIn`을 false로 바꾼다 — 즉 로그아웃이 진행되는 동안에도
/// `auth.isSignedIn`은 한동안 true로 남아 있고, 설정 화면은 여전히 탭 가능한
/// 상태다. 실기기에서 로그아웃을 누른 직후, 화면이 로그인 화면으로 전환되는
/// 1초 미만의 찰나에 "계정 삭제"를 눌러 삭제 절차가 함께 시작된 사례가
/// 있었다(2026-08-12). `isSignedIn` 값만으로는 이 구간을 못 잡기 때문에, 로그아웃/
/// 삭제 중임을 직접 표시하는 이 플래그로 재진입을 막는다.
bool _accountActionInProgress = false;

Future<void> _confirmSignOut(BuildContext context, AuthRepository auth) async {
  if (!auth.isSignedIn || _accountActionInProgress) return;
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
  if (confirmed != true) return;
  // 다이얼로그가 떠 있는 사이 다른 경로(예: 계정 삭제)로 이미 로그아웃 처리가
  // 시작됐을 수 있다 — 재확인 후 진행한다.
  if (_accountActionInProgress) return;
  _accountActionInProgress = true;
  try {
    await auth.signOut();
  } finally {
    _accountActionInProgress = false;
  }
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
  // 로그아웃이 진행 중(또는 이미 완료)이면 삭제를 시작하지 않는다 — 위
  // `_accountActionInProgress` 문서 참고. 확인 다이얼로그조차 띄우지 않고
  // 조용히 무시한다: 사용자가 의도적으로 누른 게 아니라 화면 전환 중 오탭일
  // 가능성이 높아, "이미 로그아웃 중입니다" 같은 안내를 띄우면 오히려
  // 혼란스럽다.
  if (!auth.isSignedIn || _accountActionInProgress) return;
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
            '이 계정으로 서버에 백업된 명함·프로필 데이터와 이 기기에 저장된 '
            '명함 사진·프로필 사진·암호화 키가 함께 영구적으로 삭제됩니다. '
            '다른 기기에 남아 있는 데이터도 열 수 없게 됩니다.\n\n'
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
  // 확인 다이얼로그가 떠 있는 사이(사용자가 "영구 삭제"를 누르기 전) 로그아웃이
  // 끝났을 수도 있다 — 실행 직전에 다시 확인한다.
  if (!auth.isSignedIn || _accountActionInProgress) return;
  _accountActionInProgress = true;
  try {
    await _performAccountDeletion(context, auth);
  } finally {
    _accountActionInProgress = false;
  }
}

/// 계정 삭제 후 **이 기기에 남는 것**을 정리한다.
///
/// `clearLocal()`은 SharedPreferences만 비운다. 2026-08-10 점검에서 세 가지가
/// 기기에 그대로 남는 것을 확인했다 — 명함 이미지 암호문 파일, 프로필 아바타
/// 사진(평문 JPG), 보안 저장소의 암호화 키. 방침은 "영구 삭제"라고 적고 있고
/// 남는 것 중 명함 이미지는 **제3자(명함 주인)의 개인정보**다.
///
/// **순서가 안전을 결정한다.** 암호화 키를 가장 마지막에 지운다 — 키가 먼저
/// 사라지면 남은 암호문 파일을 열 수도 지울 수도 없는 상태가 된다.
///
/// 하나가 실패해도 **나머지는 계속 진행한다**(멈추면 더 많이 남는다).
/// 실패가 하나라도 있으면 true를 반환해 호출부가 사용자에게 알리게 한다.
Future<bool> _cleanUpLocalArtifacts(
  ContactsRepository contactsRepo,
  MyProfileRepository profileRepo,
  String? uid,
) async {
  var hadFailure = false;

  // 1) 명함 이미지 — 명함 목록을 비우기 전에 지워야 한다. 목록이 먼저 비면
  //    경로를 잃어 고아 파일이 된다.
  //    uid를 넘겨 **서버 사본까지** 지운다 — 방침이 약속한 "회원 탈퇴 시 전부
  //    파기"는 기기만 비워서는 지켜지지 않는다(2026-08-15, 추가 218).
  final failedImages = await ContactImageService().deleteAllCardImages(
    uid: uid,
  );
  if (failedImages > 0) hadFailure = true;

  // 1-1) 사진 개선 동의(기기 캐시). 남으면 같은 기기에서 다음 계정이 앞
  //      사람의 동의를 물려받는다.
  await PhotoImprovementConsentService().clearLocal();

  // 2) 내 프로필 사진. 이건 암호화도 안 돼 있어(평문 JPG) 남으면 재가입 시
  //    이전 사진이 그대로 보인다.
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final avatar = File('${docsDir.path}/my_profile_avatar.jpg');
    if (avatar.existsSync()) await avatar.delete();
  } catch (e) {
    hadFailure = true;
    debugPrint('프로필 사진 삭제 실패: ${e.runtimeType}');
  }

  // 3) SharedPreferences(명함 목록·프로필) 정리.
  await contactsRepo.clearLocal();
  await profileRepo.clearLocal();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kLastSignedInUidPrefsKey);
  } catch (e) {
    hadFailure = true;
    debugPrint('계정 삭제 후 마지막 로그인 uid 정리 실패: $e');
  }

  // 4) 암호화 키 — 반드시 마지막.
  if (uid != null) {
    final ok = await EncryptionKeyService().deleteLocalKey(uid);
    if (!ok) hadFailure = true;
  }

  return hadFailure;
}

/// 정리 중 일부가 실패했을 때 알린다. 계정은 이미 지워졌고 되돌릴 수 없으므로
/// **에러가 아니라 사실 안내**로 쓴다 — 사용자가 할 수 있는 다음 행동(앱 삭제)
/// 까지 함께 알려 준다.
///
/// `BuildContext`가 아니라 미리 잡아 둔 [ScaffoldMessengerState]를 받는다 —
/// 계정 삭제가 성공하면 이 스낵바를 띄우기 전에 이미 SettingsView가
/// unmount됐을 수 있어서다(아래 `_performAccountDeletion` 주석 참고).
void _showLocalCleanupWarning(ScaffoldMessengerState messenger) {
  messenger.showSnackBar(
    const SnackBar(
      content: Text('계정은 삭제됐지만 이 기기에 일부 파일이 남았을 수 있어요. 앱을 삭제하면 함께 지워집니다.'),
      backgroundColor: AppColors.destructive,
      duration: Duration(seconds: 6),
    ),
  );
}

/// 실제 삭제 흐름 — 순서가 중요하다:
/// 1) Firestore 서버 데이터 삭제(아직 인증된 상태일 때만 보안 규칙 통과)
/// 2) Firebase Auth 계정 삭제(재인증 필요 시 사용자에게 안내 후 재시도)
/// 3) 로컬 저장 데이터(명함/프로필) 초기화
///
/// 기존 백업 로직과 달리 실패를 조용히 삼키지 않는다 — 각 단계 실패는
/// 사용자에게 명확한 에러 메시지로 알린다(서버에 데이터가 남았는데 사용자는
/// 삭제됐다고 믿는 상황을 방지).
///
/// **await 뒤에 이 함수의 `context`(SettingsView)를 다시 쓰면 안전하지
/// 않다.** `auth.deleteFirebaseAccountAndLocalSession()`이 성공하는 순간
/// `AuthRepository` 상태가 바뀌고, 이를 듣고 있는 `AuthGate`가 곧바로
/// `MainTabScreen`을 로그인 화면으로 갈아치운다 — 그 아래 있던 SettingsView가
/// 통째로 unmount된다(실기기 제보, 2026-08-12). 그 시점 이후 `context.mounted`는
/// false가 되어, "닫아야 하는데 context가 죽어서 못 닫는" 상황이 된다 — 로딩
/// 다이얼로그가 화면에 영원히 남는다.
///
/// 그래서 시작 시점에 루트 [NavigatorState]와 [ScaffoldMessengerState]를
/// 미리 잡아 둔다. 둘 다 앱 최상단(MaterialApp 바로 아래)에 있어 SettingsView가
/// 사라져도 살아 있다 — `briefing_overlay_view.dart`에서 이미 쓰는 것과 같은
/// 관용구다. 로딩 다이얼로그를 띄울 때도 SettingsView의 context 대신 이
/// NavigatorState 자신의 context를 쓴다 — 화면 전환과 무관하게 유효하다.
/// 이미 닫은 다이얼로그를 또 pop해 엉뚱한 화면(로그인 화면 등)이 닫히는 일이
/// 없도록 `isLoadingDialogShown` 플래그로 표시 여부를 추적한다.
Future<void> _performAccountDeletion(
  BuildContext context,
  AuthRepository auth,
) async {
  // `_confirmDeleteAccount`가 이미 같은 조건을 확인하지만, 이 함수는 그 흐름의
  // 유일한 진입점이 아니게 바뀔 수 있으므로(예: 재인증 재시도 경로 추가) 방어적으로
  // 한 번 더 막는다 — 비용이 거의 없고, 로그인 상태가 아닌데 삭제 절차가 시작되는
  // 구멍을 원천 차단한다.
  if (!auth.isSignedIn) return;

  final contactsRepo = context.read<ContactsRepository>();
  final profileRepo = context.read<MyProfileRepository>();
  final uid = auth.firebaseUid;

  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final rootContext = rootNavigator.context;
  final messenger = ScaffoldMessenger.of(context);

  var isLoadingDialogShown = false;
  void showLoading() {
    if (isLoadingDialogShown) return;
    isLoadingDialogShown = true;
    _showLoadingDialog(rootContext);
  }

  void dismissLoading() {
    if (!isLoadingDialogShown) return;
    isLoadingDialogShown = false;
    rootNavigator.pop();
  }

  showLoading();

  try {
    // 다른 기기에서 이미 삭제된 계정이면 서버엔 지울 게 없다. 이 경우 서버
    // 요청(토큰 갱신 실패로 "네트워크 오류"처럼 보임)을 아예 건너뛰고, 이
    // 기기의 로컬 데이터만 정리한 뒤 로그아웃시킨다.
    if (await auth.isAccountAlreadyDeleted()) {
      // 다기기 사용자가 두 번째 기기에서 정리를 못 받는 일이 없도록, 이 경로도
      // 같은 정리를 거친다.
      final hadFailure = await _cleanUpLocalArtifacts(
        contactsRepo,
        profileRepo,
        uid,
      );
      await auth.signOut();
      dismissLoading();
      if (hadFailure) _showLocalCleanupWarning(messenger);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('이미 다른 기기에서 삭제된 계정이에요. 이 기기에서도 로그아웃했어요.'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    if (uid != null) {
      await DataBackupService.deleteAllUserData(uid);
    }

    try {
      await auth.deleteFirebaseAccountAndLocalSession();
    } on AuthException catch (e) {
      if (!e.requiresReauth) rethrow;

      dismissLoading();

      // 여기 도달했다는 것은 계정 삭제가 아직 완료되지 않았다는(재인증 필요로
      // 실패했다는) 뜻이라 auth 상태는 그대로다 — SettingsView는 아직 살아
      // 있으므로 이 확인 다이얼로그는 원래 context를 그대로 써도 안전하다.
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

      showLoading();
      await auth.reauthenticateCurrentProvider();
      await auth.deleteFirebaseAccountAndLocalSession();
    }

    // 여기까지 왔다는 것은 서버 데이터와 Firebase 계정 삭제가 모두 성공했다는
    // 뜻이다. 그 전에 로컬 파일을 지우면, 서버 삭제나 재인증이 실패했을 때
    // 계정은 살아 있는데 기기 데이터만 날아간다 — 명함 이미지는 서버 백업이
    // 없어 영구 손실이다.
    final hadFailure = await _cleanUpLocalArtifacts(
      contactsRepo,
      profileRepo,
      uid,
    );

    dismissLoading();
    if (hadFailure) _showLocalCleanupWarning(messenger);
    // 성공 시 auth.isSignedIn이 false가 되어 AuthGate가 자동으로 로그인
    // 화면으로 전환한다(로그아웃과 동일한 종착점).
  } catch (e) {
    dismissLoading();
    _showAccountDeletionError(messenger, e);
  }
}

/// 예전 기본값(`AI, IT`)이 그대로 남은 명함의 태그를 비운다 — **관리자 전용,
/// 일회성 정리**(빌드6·7 통합본 E-08, backlog 추가 204).
///
/// **왜 앱 시작 시 자동 마이그레이션으로 하지 않았나**: 그러면 일반 사용자
/// 기기에서도 돌아, **진짜 AI·IT 업계 사람이 그 태그를 그대로 둔 경우까지
/// 지운다.** 둘을 구별할 방법이 없다. 잘못 채워진 값을 지우려다 맞는 값을
/// 지우는 쪽이 더 나쁘다 — 그래서 사람이 눌러서 실행하는 경로로 두었다.
///
/// **대상을 좁게 잡는다**: 태그가 **정확히 `AI`와 `IT` 둘뿐**인 명함만 본다.
/// 하나라도 다른 태그를 직접 넣었다면 사용자가 이 칸을 의식했다는 뜻이라
/// 건드리지 않는다.
Future<void> _confirmSeededTagCleanup(BuildContext context) async {
  final repo = context.read<ContactsRepository>();
  // 어떤 명함을 고르는지가 이 기능의 전부다 — 판정 규칙은 따로 빼서
  // 테스트한다(`seeded_tag_cleanup.dart`).
  final targets = repo.contacts
      .where((c) => isSeededDefaultTagSet(c.tags))
      .toList();

  final messenger = ScaffoldMessenger.of(context);
  if (targets.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('기본값만 남은 명함이 없습니다.')),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${targets.length}건의 태그를 비울까요?'),
      content: Text(
        '태그가 "AI, IT" 둘뿐인 명함 ${targets.length}건입니다.\n'
        '예전 입력칸 기본값이 그대로 저장된 것으로 봅니다.\n\n'
        '되돌릴 수 없습니다. 실제로 AI·IT 태그를 쓰던 명함이 섞여 있다면 '
        '먼저 그 명함에 다른 태그를 추가해 대상에서 빼 주세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '태그 비우기',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  for (final contact in targets) {
    repo.updateContact(contact.copyWith(tags: const []));
  }
  messenger.showSnackBar(
    SnackBar(content: Text('${targets.length}건의 태그를 비웠습니다.')),
  );
}

/// 스캔이 자동으로 넣던 문구가 그대로 남은 메모를 비운다 — **관리자 전용,
/// 일회성 정리**(backlog 추가 223).
///
/// 태그 정리([_confirmSeededTagCleanup])와 같은 구조다. 자동 마이그레이션으로
/// 하지 않은 이유도 같다 — **사용자가 그 문장을 보고 그대로 두기로 했을
/// 가능성**을 앱이 구별할 수 없다. 지우려다 사용자 메모를 지우는 쪽이 더 나쁘다.
///
/// 대상은 메모가 **그 문장 하나뿐**인 명함이다. 뒤에 무언가 덧붙였다면 사용자가
/// 그 칸을 의식했다는 뜻이라 건드리지 않는다.
Future<void> _confirmSeededMemoCleanup(BuildContext context) async {
  final repo = context.read<ContactsRepository>();
  // 판정 규칙은 따로 빼서 테스트한다(`seeded_memo_cleanup.dart`).
  final targets = repo.contacts
      .where((c) => isSeededScanMemo(c.memo))
      .toList();

  final messenger = ScaffoldMessenger.of(context);
  if (targets.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('자동 삽입된 메모만 남은 명함이 없습니다.')),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${targets.length}건의 메모를 비울까요?'),
      content: Text(
        '메모가 "AI OCR 스캔으로 자동 추출된 명함 텍스트 정보입니다." '
        '한 줄뿐인 명함 ${targets.length}건입니다.\n'
        '예전에 스캔이 자동으로 넣던 문구가 그대로 저장된 것으로 봅니다.\n\n'
        '이 문구는 AI 대화 가이드를 만들 때도 함께 전송되어, 아무 의미 없는 '
        '내용이 상대방에 대한 정보처럼 쓰입니다.\n\n'
        '되돌릴 수 없습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            '메모 비우기',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  for (final contact in targets) {
    repo.updateContact(contact.copyWith(memo: ''));
  }
  messenger.showSnackBar(
    SnackBar(content: Text('${targets.length}건의 메모를 비웠습니다.')),
  );
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

/// `BuildContext`가 아니라 미리 잡아 둔 [ScaffoldMessengerState]를 받는다 —
/// 이유는 `_performAccountDeletion` 주석 참고.
void _showAccountDeletionError(ScaffoldMessengerState messenger, Object error) {
  final message = error is AuthException
      ? error.message
      : '계정 삭제 중 오류가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.';
  messenger.showSnackBar(
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
