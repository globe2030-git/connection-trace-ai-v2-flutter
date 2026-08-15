import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/models/pending_comm_log_intent.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/services/ai_usage_service.dart';
import '../../../../core/services/pilot_events_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/ai_usage_chip.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../../wallet/view_models/wallet_view_model.dart';
import '../../radar/view_models/radar_view_model.dart';
import 'ai_data_review_sheet.dart';
import 'communication_source_sheet.dart';
import 'manual_comm_log_modal_view.dart';

// 이 오버레이의 페이지 배경 위에 "직접" 놓이는(=GlassCard 안이 아닌) 에러 텍스트/아이콘
// 전용 색상. AppColors.destructive(#EF4444)는 AppColors.bgBase 위에서
// 대비비 3.54:1로 본문 텍스트 WCAG AA 기준(4.5:1)에 못 미쳐 여기서는 쓰지 않는다.
// (GlassCard 흰 배경 안에서 쓰이는 AppColors.destructive는 이번 수정 범위 밖이라 그대로 둔다.)
const Color _onPageErrorText = Color(0xFFB91C1C);

class BriefingOverlayView extends StatefulWidget {
  final ContactModel contact;
  final VoidCallback onClose;

  const BriefingOverlayView({
    super.key,
    required this.contact,
    required this.onClose,
  });

  @override
  State<BriefingOverlayView> createState() => _BriefingOverlayViewState();
}

class _BriefingOverlayViewState extends State<BriefingOverlayView>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late List<String> _points;
  bool _isGenerating = false;
  String? _errorMessage;

  // 이 화면(같은 상대방의 AI 브리핑을 보는 동안)을 여는 중에는 재동의 없이
  // "다시 시도"/새로고침이 되도록 최초 동의 결과를 들고 있는다. 화면을 닫았다
  // 다시 열면(= 새 State 인스턴스) 다시 물어본다 — 완전한 세션(앱 재시작 전까지)
  // 단위로 넓히면 다른 상대방 전송 항목까지 안 보고 넘어갈 수 있어 과하다고
  // 판단했다. AiDataReviewSheet의 동의 문구도 이 범위에 맞춰 함께 고쳤다.
  AiBriefingSelection? _consentedSelection;

  // "전한 대화 포인트를 소통 기록에 저장" 기능(2026-08-11)의 대기 의도.
  // 통화/문자/카톡/더보기(이메일)로 실제로 앱을 벗어난 순간 여기 채워 두고,
  // 앱이 다시 활성화(resumed)되면 한 번 확인 다이얼로그를 띄운다. url_launcher/
  // share는 "보냄" 콜백이 없어 라이프사이클로 복귀를 감지하는 수밖에 없다.
  // 매핑·중복 방지 로직은 위젯 트리 밖(core/models/pending_comm_log_intent.dart)
  // 으로 뽑아 두어 위젯 없이도 단위 테스트할 수 있게 했다.
  final _pendingSaveTracker = PendingCommLogTracker();

  // 파일럿(베타) 계측 — 대화 포인트 복사/전송 이벤트와 브리핑 반응(피드백)을
  // 남긴다. 개인정보(대화 포인트 원문·상대방 식별 정보)는 전혀 넘기지
  // 않는다(PilotEventsService 자체가 채널/반응 값만 받는다).
  final _pilotEvents = PilotEventsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _points = widget.contact.talkingPoints;
    // 상단 잔여 칩(AiUsageChip)이 구독하는 최신값을 미리 읽어 둔다.
    AiUsageService.fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeConfirmPendingSave();
    }
  }

  @override
  void didUpdateWidget(covariant BriefingOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contact.talkingPoints != widget.contact.talkingPoints) {
      _points = widget.contact.talkingPoints;
      _selectedIndex = 0;
    }
    if (oldWidget.contact.id != widget.contact.id) {
      _consentedSelection = null;
    }
  }

  Future<void> _generate() async {
    final myProfile = context.read<MyProfileRepository>().profile;
    var selection = _consentedSelection;
    if (selection == null) {
      selection = await showModalBottomSheet<AiBriefingSelection>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            AiDataReviewSheet(contact: widget.contact, myProfile: myProfile),
      );
      if (selection == null || !mounted) return;
      _consentedSelection = selection;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final points = await AiBriefingService.generateTalkingPoints(
        contact: widget.contact,
        myProfile: myProfile,
        communicationLogs: selection.communicationLogs,
        weatherSummary: selection.weatherSummary,
        extraNote: selection.extraNote,
        // F-07: "새로 생성"을 누른 시점 화면에 있던 포인트를 넘겨, 서버가 그
        // 문장들을 피해 다른 각도로 만들게 한다. 최초 생성이면 _points가 비어
        // 있어(또는 캐시된 이전 결과) 그대로 넘긴다 — 서버가 알아서 처리한다.
        previousPoints: _points,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _selectedIndex = 0;
        _isGenerating = false;
      });
      // 다음에 열 때 API를 다시 호출하지 않도록 결과를 인맥 데이터에 캐시.
      context.read<WalletViewModel>().updateContact(
        widget.contact.copyWith(talkingPoints: points),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e is AiBriefingException
            ? e.message
            : '대화 포인트를 생성하지 못했습니다: $e';
      });
    }
    // 성공·실패와 무관하게 잔여 횟수를 다시 읽는다(서버가 호출을 셌을 수 있음).
    // latest에 방송돼 상단 칩과 홈·설정 칩이 함께 갱신된다.
    await AiUsageService.fetch();
  }

  Future<void> _addCommunicationRecord() async {
    final contact = _resolveContact(context.read<ContactsRepository>());
    final action = await showModalBottomSheet<CommunicationSourceAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunicationSourceSheet(contact: contact),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case CommunicationSourceAction.callNote:
        return _openManualRecord('call');
      case CommunicationSourceAction.smsPaste:
        return _openManualRecord('sms');
      case CommunicationSourceAction.kakaoPaste:
        return _openManualRecord('kakao');
    }
  }

  Future<void> _openManualRecord(String type, {String? initialSummary}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualCommLogModalView(
        contact: _resolveContact(context.read<ContactsRepository>()),
        initialType: type,
        initialSummary: initialSummary,
      ),
    );
  }

  /// 통화/문자/카톡/더보기(이메일) 경로를 실제로 실행한 순간
  /// `_SendChannelRow`가 호출한다. 대기 의도는 1건만 유지한다 — 연속으로
  /// 다른 경로를 누르면 새 것으로 교체돼 중복 저장을 막는다.
  void _rememberPendingSave(String contactId, String channel, String point) {
    _pendingSaveTracker.remember(
      PendingCommLogIntent(
        contactId: contactId,
        channel: channel,
        point: point,
      ),
    );
    // 계측(파일럿 관측 항목 3) — 채널만 남기고 대화 포인트 원문·상대방
    // 식별 정보는 넘기지 않는다. 실패해도 조용히 무시(계측이 전송 기능을
    // 막지 않는다).
    unawaited(_pilotEvents.recordCopySend(channel));
  }

  /// 앱이 다시 활성화됐을 때(라이프사이클 resumed) 대기 의도가 있으면 한 번
  /// 확인한다. `consume()`이 처리 시작과 동시에 대기 의도를 비워 다이얼로그가
  /// 뜨는 도중 다시 백그라운드/포그라운드를 반복해도 두 번 뜨지 않게 한다.
  Future<void> _maybeConfirmPendingSave() async {
    final intent = _pendingSaveTracker.consume();
    if (intent == null || !mounted) return;

    final contact = _resolveContact(context.read<ContactsRepository>());
    // 대기 의도를 남긴 인맥과 지금 열려 있는 브리핑의 인맥이 다르면(이론상
    // 화면 전환 중 드문 경우) 확인을 건너뛴다 — 엉뚱한 인맥 기록에 붙는 걸
    // 막는다.
    if (contact.id != intent.contactId) return;

    final action = await showDialog<PendingCommLogAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '방금 ${communicationChannelLabel(intent.channel)}로 전한 내용을 소통 기록에 저장할까요?',
        ),
        content: Text(
          '"${communicationLogPreview(intent.point)}"',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, PendingCommLogAction.discard),
            child: const Text('아니오'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, PendingCommLogAction.edit),
            child: const Text('수정 후 저장'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, PendingCommLogAction.save),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('저장', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == PendingCommLogAction.discard) {
      return;
    }
    if (action == PendingCommLogAction.save) {
      _saveCommLog(intent);
    } else {
      await _openManualRecord(intent.channel, initialSummary: intent.point);
    }
  }

  void _saveCommLog(PendingCommLogIntent intent) {
    final current = _resolveContact(context.read<ContactsRepository>());
    final newLog = CommunicationLogModel(
      type: intent.channel,
      summary: intent.point,
      timestamp: DateTime.now(),
      isAutoSynced: false,
      source: 'manual',
    );
    final updated = current.copyWith(commLogs: [newLog, ...current.commLogs]);
    context.read<RadarViewModel>().updateContact(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('소통 기록에 저장했어요'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  Future<void> _deleteCommunicationRecord(CommunicationLogModel target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('소통 기록을 삭제할까요?'),
        content: const Text('이 기기에 저장된 기록에서 삭제되며 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final current = _resolveContact(context.read<ContactsRepository>());
    final updated = current.copyWith(
      commLogs: current.commLogs.where((log) => log.id != target.id).toList(),
    );
    final radar = context.read<RadarViewModel>();
    radar.updateContact(updated);
    radar.openBriefing(updated);
  }

  /// 화면에 그릴 **최신** 인맥 정보.
  ///
  /// 생성자로 받은 `widget.contact`는 화면을 연 순간의 스냅숏이다. 소통 기록을
  /// 추가해도 그 스냅숏은 바뀌지 않아, 명함 지갑에서 열었을 때는 방금 남긴
  /// 기록이 보이지 않았다 — 다른 메뉴에 갔다 와야 나타났다(사용자 보고,
  /// 2026-08-10). 주변 화면에서 열었을 때만 우연히 동작했는데,
  /// `RadarViewModel.openBriefing`이 새 스냅숏을 다시 밀어 넣었기 때문이다.
  ///
  /// 저장소에서 id로 매번 다시 찾아 그 문제를 없앤다. 삭제된 직후처럼 저장소에
  /// 없으면 마지막 스냅숏으로 되돌아간다(화면이 갑자기 비지 않도록).
  ContactModel _resolveContact(ContactsRepository repo) {
    for (final c in repo.contacts) {
      if (c.id == widget.contact.id) return c;
    }
    return widget.contact;
  }

  @override
  Widget build(BuildContext context) {
    final contact = _resolveContact(context.watch<ContactsRepository>());
    const serviceDeployed = AiBriefingService.kAiServiceDeployed;

    return Container(
      // 기존 검정 85% 스크림은 위에 직접 놓인 textPrimary(#171A21) 등 어두운 텍스트와
      // 대비비 ~1.2:1로 거의 보이지 않는 버그였다. 앱 전역이 이미 라이트 테마
      // (scaffoldBackgroundColor = AppColors.bgBase)이므로 이 오버레이도 같은
      // 배경 토큰으로 통일해 기존 textPrimary/textSecondary/accentText 위젯 트리를
      // 그대로 두고 대비 문제를 해결한다.
      color: AppColors.bgBase,
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar with Close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              color: AppColors.accentText,
                              size: 22,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '30초 AI 대화 브리핑',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textPrimary,
                          size: 24,
                        ),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  // 잔여 횟수 칩(탭하면 상세) — 닫기 버튼을 밀지 않도록 제목 줄
                  // 아래에 따로 놓는다. 서비스 미배포/미조회 시 스스로 숨김.
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: AiUsageChip(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header Card
                    GlassCard(
                      child: Row(
                        children: [
                          ContactAvatar(
                            photoPath: contact.avatarUrl,
                            name: contact.name,
                            radius: 30,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${contact.name} ${contact.title}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  contact.company,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  // 태그가 많아 여러 줄로 감기면 runSpacing이
                                  // 없어 줄끼리 붙어 보였다(P1-11).
                                  runSpacing: 4,
                                  children: contact.tags.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentText.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.accentText,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Tailored Talking Points
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Row(
                            children: [
                              AppIcon(
                                AppIconId.talkPoints,
                                size: 18,
                                color: AppColors.accentText,
                              ),
                              SizedBox(width: 7),
                              Text(
                                '추천 맞춤 대화 포인트',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (serviceDeployed)
                          IconButton(
                            icon: _isGenerating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accentText,
                                    ),
                                  )
                                : const Icon(
                                    Icons.refresh,
                                    size: 20,
                                    color: AppColors.accentText,
                                  ),
                            onPressed: _isGenerating ? null : _generate,
                            tooltip: '새로 생성',
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '커넥션센스 AI가 생성',
                      style: TextStyle(
                        fontSize: 11,
                        // 페이지 배경에 직접 놓이는 캡션 — textMuted(대비 3.59:1)는
                        // AA 미달이라 textSecondary(대비 5.44:1)를 사용한다.
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (!serviceDeployed)
                      GlassCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.hourglass_empty,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '서비스 준비 중 — 곧 제공될 예정이에요.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_isGenerating && _points.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accentText,
                          ),
                        ),
                      )
                    else if (_errorMessage != null && _points.isEmpty)
                      GlassCard(
                        borderColor: AppColors.destructive.withValues(
                          alpha: 0.4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 18,
                                  color: AppColors.destructive,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.destructive,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _generate,
                              child: const Text(
                                '다시 시도',
                                style: TextStyle(
                                  color: AppColors.accentText,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_points.isEmpty)
                      GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '아직 생성된 AI 가이드가 없습니다. 전송할 정보를 먼저 확인한 뒤 직접 생성할 수 있습니다.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _generate,
                                icon: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'AI 가이드 만들기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                // 페이지 배경에 직접 놓임 — AppColors.destructive는
                                // 여기서 AA 미달(3.54:1)이라 _onPageErrorText 사용.
                                color: _onPageErrorText,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '새로 생성하지 못해 이전 결과를 보여드려요: $_errorMessage',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: _onPageErrorText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ..._points.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final point = entry.value;
                        final isSelected = _selectedIndex == idx;

                        return GlassCard(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          borderColor: isSelected ? AppColors.accentText : null,
                          backgroundColor: isSelected
                              ? AppColors.accentText.withValues(alpha: 0.15)
                              : null,
                          onTap: () => setState(() => _selectedIndex = idx),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isSelected
                                    ? AppColors.accentText
                                    : AppColors.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '"$point"',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      // 고른 대화 포인트를 어떤 경로로 전할지 바로 여기서
                      // 정한다(사용자 요청, 2026-08-10). 예전에는 화면 맨 아래
                      // "안부 전화 걸기" 버튼 하나뿐이라 통화 말고는 길이
                      // 없었고, 고른 문장과 버튼이 화면 양 끝으로 떨어져 있어
                      // 무엇이 전달되는지도 잘 보이지 않았다.
                      const SizedBox(height: 4),
                      _SendChannelRow(
                        contact: contact,
                        selectedPoint:
                            _points.isNotEmpty &&
                                _selectedIndex < _points.length
                            ? _points[_selectedIndex]
                            : null,
                        onSent: (channel, point) =>
                            _rememberPendingSave(contact.id, channel, point),
                      ),

                      // 파일럿(베타) 계측 — 대화 포인트가 뜬 직후 가벼운
                      // 반응 수집(관측 항목 4). 응답하지 않아도 무방한
                      // 선택형이라 강요하지 않는다. 새로 생성할 때마다
                      // (`_points`가 바뀔 때) 이전 선택이 남아 보이지 않도록
                      // key로 새 State를 만든다.
                      _FeedbackRow(
                        key: ValueKey(_points),
                        pilotEvents: _pilotEvents,
                      ),
                    ],

                    // Recent Communication History Integration Trace
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            '최근 소통 기록',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addCommunicationRecord,
                          icon: const Icon(
                            Icons.add_circle_outline,
                            size: 16,
                            color: AppColors.accentText,
                          ),
                          label: const Text(
                            '추가',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.accentText,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '직접 작성하거나 붙여넣은 기록만 표시합니다.',
                      style: TextStyle(
                        fontSize: 11,
                        // 페이지 배경에 직접 놓이는 캡션 — textMuted(대비 3.59:1)는
                        // AA 미달이라 textSecondary(대비 5.44:1)를 사용한다.
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (contact.commLogs.isEmpty)
                      GlassCard(
                        child: const Text(
                          '최근 소통 기록이 없습니다. 위 "추가" 버튼에서 통화·문자·카카오톡 내용을 직접 기록해 보세요.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    else
                      ...contact.commLogs.map((log) {
                        AppIconId icon;
                        Color color;
                        String badge;

                        switch (log.type) {
                          case 'call':
                            icon = AppIconId.call;
                            color = AppColors.channelCall;
                            badge = '최근통화';
                            break;
                          case 'sms':
                            icon = AppIconId.message;
                            color = AppColors.channelSms;
                            badge = '문자';
                            break;
                          case 'email':
                            icon = AppIconId.mailSend;
                            color = AppColors.channelEmail;
                            badge = '이메일';
                            break;
                          case 'kakao':
                          default:
                            icon = AppIconId.chatSend;
                            color = AppColors.channelKakao;
                            badge = '카카오톡';
                            break;
                        }

                        return GlassCard(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: AppIcon(icon, size: 16, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            badge,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${log.timestamp.month}월 ${log.timestamp.day}일 ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      log.summary,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '기록 삭제',
                                onPressed: () =>
                                    _deleteCommunicationRecord(log),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 19,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    if (contact.memo != null) ...[
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          AppIcon(
                            AppIconId.memo,
                            size: 18,
                            color: AppColors.accentText,
                          ),
                          SizedBox(width: 7),
                          Text(
                            '메모',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GlassCard(
                        child: Text(
                          contact.memo!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 고른 대화 포인트를 어떤 경로로 전할지 고르는 줄 — 통화 / 문자 / 카톡 / 더보기.
///
/// 예전에는 화면 맨 아래 "안부 전화 걸기" 버튼 하나뿐이었다. 통화 말고는 길이
/// 없었고, 고른 문장과 버튼이 화면 양 끝으로 떨어져 있어 무엇이 전달되는지도
/// 잘 보이지 않았다(사용자 요청, 2026-08-10).
///
/// **네 경로의 성격이 서로 다르다.**
/// - 통화: 문장을 보낼 수 없으므로 클립보드에 복사해 두고 전화를 건다.
/// - 문자: `sms:` URL에 본문을 실어 문자 앱이 미리 채운 채로 열린다.
/// - 카톡: 카카오톡에는 "특정 상대에게 미리 채운 메시지"를 여는 공개 경로가
///   없다. 그래서 복사 후 앱만 열어 주고, 사용자가 붙여넣게 안내한다.
///   있는 척하지 않고 실제 동작을 그대로 알린다.
/// - 이메일: `mailto:`로 명함의 주소를 수신인까지 채워 연다.
///
/// 예전의 "더보기"(OS 공유 시트로 슬랙 등 임의 앱 공유)는 뺐다 — 공유
/// 시트는 어느 앱으로 보냈는지 알 수 없어 소통 기록으로 저장할 수 없고,
/// "소통 기록을 저장할 수 있는 채널만 둔다"는 결정(사용자, 2026-08-11)에
/// 따라 이메일을 직접 버튼으로 승격했다. 임의 공유가 필요하면 문장을
/// 복사해 원하는 앱에 붙여넣으면 된다(통화·카톡 경로가 이미 복사해 준다).
class _SendChannelRow extends StatelessWidget {
  final ContactModel contact;
  final String? selectedPoint;

  /// 통화/문자/카톡/더보기(이메일)로 실제로 앱을 벗어났을 때 호출된다
  /// (channel, point). 대기 의도를 기억해 두었다가 앱이 다시 활성화되면
  /// 소통 기록 저장 여부를 한 번 확인한다(2026-08-11 스펙).
  final void Function(String channel, String point)? onSent;

  const _SendChannelRow({
    required this.contact,
    required this.selectedPoint,
    this.onSent,
  });

  /// 문자는 휴대폰 번호로만 보낸다 — 사무실 유선번호로 문자를 보낼 수는 없다.
  bool get _hasMobile => contact.phone.trim().isNotEmpty;

  /// 통화는 둘 중 하나만 있어도 걸 수 있다. 어느 번호로 걸지는 선택 시트가
  /// 정한다(사용자 요청, 2026-08-10).
  bool get _hasAnyPhone =>
      _hasMobile || (contact.officePhone?.trim().isNotEmpty ?? false);

  /// 이메일 버튼은 명함에 주소가 있어야 살아난다 — 수신인 없이 메일 앱만
  /// 여는 것은 "보내기" 경로로서 의미가 없다.
  bool get _hasEmail => contact.email.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ChannelButton(
            icon: AppIconId.call,
            label: '통화',
            enabled: _hasAnyPhone,
            onTap: () => _call(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ChannelButton(
            icon: AppIconId.message,
            label: '문자',
            enabled: _hasMobile,
            onTap: () => _sms(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ChannelButton(
            icon: AppIconId.chatSend,
            label: '카톡',
            enabled: true,
            onTap: () => _kakao(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ChannelButton(
            icon: AppIconId.mailSend,
            label: '이메일',
            enabled: _hasEmail,
            onTap: () => _emailTap(context),
          ),
        ),
      ],
    );
  }

  Future<void> _copyPoint() async {
    final point = selectedPoint;
    if (point == null) return;
    await Clipboard.setData(ClipboardData(text: point));
  }

  // await 뒤에 BuildContext를 다시 쓰면 위젯이 이미 사라졌을 수 있다. 그래서
  // 각 동작 시작 시점에 messenger를 미리 잡아 두고 그것만 넘긴다.
  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.accent),
    );
  }

  Future<void> _call(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // 2026-08-07: 통화를 누르면 전화 앱으로 넘어가면서 대화 포인트 화면이
    // 그대로 사라져 "외워서 말해야 하는" 문제가 있었다(사용자 피드백). 제3자
    // 앱이 전화 화면 위에 계속 떠 있는 건 OS가 막아서(iOS/Android 공통) 통화
    // 중에는 화면을 볼 수 없지만, 복사해 두면 메모 앱에 붙여넣어 볼 수 있다.
    await _copyPoint();
    final point = selectedPoint;
    if (point != null) {
      _toast(messenger, '선택한 대화 포인트를 복사했어요. 통화 중 메모 앱 등에 붙여넣어 참고하세요.');
    }
    if (!context.mounted) return;
    // ⚠️ 브리핑 화면을 먼저 닫으면 안 된다. 예전 코드는 닫은 뒤 번호 선택
    // 시트를 열었는데, 그 시점에는 이 위젯이 이미 사라져 `context.mounted`가
    // false가 되고 **시트가 조용히 안 뜬다** — 사무실 번호까지 있는 인맥은
    // 통화를 눌러도 아무 일이 없었다. 시트를 먼저 띄운다.
    //
    // 통화가 끝나고 돌아오면 브리핑이 그대로 있어, 고른 대화 포인트를 다시
    // 볼 수 있다는 이점도 있다.
    final launched = await PhoneCallService.showCallPicker(context, contact);
    // 소통 기록 저장 의도는 **전화 걸기가 실제로 시작된 뒤에만** 남긴다.
    // 시트를 열자마자 남기면, 번호를 고르지 않고 닫은 경우에도 의도가 남아
    // — iOS에선 공유 시트를 닫기만 해도 resumed가 오므로 — 엉뚱한 시점에
    // "저장할까요?" 다이얼로그가 떴다(2026-08-11 실기기 QA에서 발견).
    if (launched && point != null) {
      onSent?.call('call', point);
    }
  }

  Future<void> _sms(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final number = contact.phone.replaceAll(RegExp(r'[^\d+]'), '');
    final point = selectedPoint;

    // 본문을 쿼리로 실어 보내면 문자 앱이 내용을 미리 채운 채로 열린다.
    // 사용자가 보내기 전에 고칠 수 있으므로 앱이 대신 발송하는 것은 아니다.
    //
    // ⚠️ `Uri(queryParameters: ...)`를 쓰면 안 된다. 그 생성자는 웹 폼 규칙
    // (application/x-www-form-urlencoded)으로 인코딩해서 **공백을 `+`로**
    // 바꾸는데, 문자 앱은 그것을 되돌리지 않고 글자 그대로 보여 준다 —
    // 사용자가 "문자에 + 기호가 들어간다"고 보고한 증상이다(2026-08-10).
    // `Uri.encodeComponent`는 공백을 `%20`으로 넣어 이 문제가 없다.
    //
    // 구분자도 플랫폼마다 다르다. Android는 `?body=`, iOS는 `&body=`를
    // 인식한다 — 반대로 쓰면 본문이 통째로 무시되고 빈 문자 화면만 열린다.
    final separator = Platform.isIOS ? '&' : '?';
    final uri = Uri.parse(
      point == null
          ? 'sms:$number'
          : 'sms:$number${separator}body=${Uri.encodeComponent(point)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _toast(messenger, '문자 앱을 열지 못했어요.');
    } else if (point != null) {
      onSent?.call('sms', point);
    }
  }

  Future<void> _kakao(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // 카카오톡에는 "특정 상대에게 미리 채운 메시지"를 여는 공개 경로가 없다.
    // 링크 공유용 스킴은 있지만 이 화면이 보내려는 것은 링크가 아니라 문장이다.
    // 그래서 복사 후 앱만 열어 주고 붙여넣도록 안내한다 — 되는 척하는 것보다
    // 실제 동작을 그대로 알리는 편이 낫다.
    await _copyPoint();

    // ⚠️ `canLaunchUrl`로 먼저 확인하지 않는다. 이 조회는 Android 11+의
    // `<queries>` 선언과 iOS의 `LSApplicationQueriesSchemes`에 의존하는데,
    // 그 선언이 빠져 있으면 **카카오톡이 깔려 있어도 false**를 돌려준다.
    // 실제로 그 상태로 나가서 "설치돼 있지 않아요"라는 잘못된 안내를 했다
    // (사용자 보고, 2026-08-10). 두 선언을 추가했지만, 여는 것 자체는 조회
    // 권한과 무관하게 되므로 **바로 시도하고 실패했을 때만** 안내한다.
    // 조회에 기대지 않는 편이 선언이 또 빠져도 안전하다.
    //
    // ⚠️ **주소를 여러 개 시도한다.** 예전에는 `kakaotalk://` 하나만 썼는데,
    // Android에서 그 형태는 **해석되지 않는다**(카카오톡이 설치돼 있어도
    // `unable to resolve Intent`). 그래서 늘 실패 안내만 떴다 —
    // 테스터 제보 "카카오톡을 열지 못했습니다"의 원인이다(빌드6·7 통합본 E-09).
    // 기기에서 후보를 하나씩 넣어 보고 `kakaotalk://launch`가 카카오톡
    // 메인 화면을 여는 것을 확인했다(갤럭시 폴드, 2026-08-14).
    //
    // `kakaotalk://`를 지우지 않고 뒤에 남겨 둔다 — iOS에서 오래 쓰인 형태이고,
    // 카카오톡 업데이트로 어느 한쪽이 막혀도 다른 쪽이 받아 준다.
    const candidates = ['kakaotalk://launch', 'kakaotalk://'];
    var opened = false;
    for (final candidate in candidates) {
      try {
        opened = await launchUrl(
          Uri.parse(candidate),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        // 앱이 없거나 그 주소를 못 열면 플랫폼에 따라 예외가 나기도 하고
        // false가 오기도 한다. 다음 후보로 넘어간다.
        opened = false;
      }
      if (opened) break;
    }
    if (opened) {
      _toast(messenger, '대화 포인트를 복사했어요. 카카오톡 대화창에 붙여넣어 주세요.');
      final point = selectedPoint;
      if (point != null) onSent?.call('kakao', point);
    } else {
      _toast(messenger, '카카오톡을 열지 못했어요. 대화 포인트는 복사해 뒀으니 붙여넣어 주세요.');
    }
  }

  /// 이메일 버튼. `mailto:`로 명함의 주소를 수신인까지 채워 연다 — 공유
  /// 시트로 메일 앱을 고르면 본문만 넘어가고 받는 사람이 비기 때문
  /// (사용자 보고, 2026-08-10). 예전엔 "더보기" 시트 안에 있었지만,
  /// 일반 공유를 없애면서 직접 버튼으로 승격했다(2026-08-11).
  Future<void> _emailTap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final point = selectedPoint;
    if (point == null) {
      _toast(messenger, '먼저 전할 대화 포인트를 선택해 주세요.');
      return;
    }
    await _email(messenger, point, contact.email.trim());
  }

  /// 메일 앱을 **수신인까지 채운 채로** 연다. 수신인은 명함에 적힌 이메일이다.
  Future<void> _email(
    ScaffoldMessengerState messenger,
    String point,
    String email,
  ) async {
    // 문자와 같은 이유로 `Uri(queryParameters:)`를 쓰지 않는다 — 공백이 `+`로
    // 바뀌어 본문에 그대로 찍힌다.
    final subject = Uri.encodeComponent('${contact.name}님, 안녕하세요');
    final body = Uri.encodeComponent(point);
    final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      _toast(messenger, '메일 앱을 열지 못했어요.');
    } else {
      onSent?.call('email', point);
    }
  }
}

/// 브리핑 직후(대화 포인트가 뜬 바로 아래) 가벼운 반응 수집 — 👍/👎와
/// 선택적 1~5 척도. **응답하지 않아도 무방한 선택형**이라 아무 것도 안
/// 눌러도 화면 사용에 지장이 없다(작업 지시서 명시 — 강제 응답 금지).
///
/// 👍/👎와 척도는 서로 배타적이지 않다 — 둘 다 누르면 둘 다 기록된다(서버
/// 규칙도 이를 허용). 이미 누른 항목은 다시 눌러도 값을 덮어쓸 뿐 중복
/// 이벤트가 쌓이는 것을 막지는 않는다 — "마음이 바뀐 재평가"도 유효한
/// 신호로 보고, 굳이 1회로 제한할 필요가 없다고 판단했다(파일럿 규모에서
/// 중복 몇 건이 집계를 왜곡할 정도로 크지 않다).
class _FeedbackRow extends StatefulWidget {
  final PilotEventsService pilotEvents;

  const _FeedbackRow({super.key, required this.pilotEvents});

  @override
  State<_FeedbackRow> createState() => _FeedbackRowState();
}

class _FeedbackRowState extends State<_FeedbackRow> {
  bool? _thumbsUp;
  int? _rating;

  void _tapThumbs(bool up) {
    setState(() => _thumbsUp = up);
    unawaited(widget.pilotEvents.recordFeedback(thumbsUp: up));
  }

  void _tapRating(int value) {
    setState(() => _rating = value);
    unawaited(widget.pilotEvents.recordFeedback(rating: value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '이 대화 포인트, 도움이 됐나요?',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ),
          ..._ratingStars(),
          const SizedBox(width: 6),
          _thumbButton(
            icon: Icons.thumb_up_alt_rounded,
            selected: _thumbsUp == true,
            semanticLabel: '도움이 됐어요',
            onTap: () => _tapThumbs(true),
          ),
          const SizedBox(width: 2),
          _thumbButton(
            icon: Icons.thumb_down_alt_rounded,
            selected: _thumbsUp == false,
            semanticLabel: '도움이 안 됐어요',
            onTap: () => _tapThumbs(false),
          ),
        ],
      ),
    );
  }

  List<Widget> _ratingStars() {
    return List.generate(5, (i) {
      final value = i + 1;
      final filled = _rating != null && value <= _rating!;
      return Semantics(
        button: true,
        label: '$value점으로 평가',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _tapRating(value),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 16,
              color: filled ? AppColors.accent : AppColors.textMuted,
            ),
          ),
        ),
      );
    });
  }

  Widget _thumbButton({
    required IconData icon,
    required bool selected,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 17,
            color: selected ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ChannelButton extends StatelessWidget {
  final AppIconId icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ChannelButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? AppColors.accentText : AppColors.textMuted;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label(으)로 전달',
      child: Material(
        color: enabled ? AppColors.accentSoft : AppColors.bgBase,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // 전화번호가 없으면 통화·문자는 열 수 없다. 눌리기는 하는데 아무
          // 일도 안 일어나는 것보다 비활성으로 보이는 편이 낫다.
          onTap: enabled ? onTap : null,
          child: Container(
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: enabled
                    ? AppColors.accentSoftStrong
                    : AppColors.borderFunctional,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, size: 20, color: foreground),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
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
