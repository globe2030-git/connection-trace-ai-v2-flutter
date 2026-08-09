import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../../wallet/view_models/wallet_view_model.dart';
import '../../radar/view_models/radar_view_model.dart';
import 'ai_data_review_sheet.dart';
import 'communication_source_sheet.dart';
import 'email_import_sheet.dart';
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

class _BriefingOverlayViewState extends State<BriefingOverlayView> {
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

  @override
  void initState() {
    super.initState();
    _points = widget.contact.talkingPoints;
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
        builder: (_) => AiDataReviewSheet(
          contact: widget.contact,
          myProfile: myProfile,
        ),
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
  }

  Future<void> _addCommunicationRecord() async {
    final action = await showModalBottomSheet<CommunicationSourceAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunicationSourceSheet(contact: widget.contact),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case CommunicationSourceAction.gmail:
        final imported =
            await showModalBottomSheet<List<CommunicationLogModel>>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => EmailImportSheet(contact: widget.contact),
            );
        if (imported == null || imported.isEmpty || !mounted) return;
        final byId = <String, CommunicationLogModel>{
          for (final log in widget.contact.commLogs) log.id: log,
          for (final log in imported) log.id: log,
        };
        final merged = byId.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        final updated = widget.contact.copyWith(commLogs: merged);
        final radar = context.read<RadarViewModel>();
        radar.updateContact(updated);
        radar.openBriefing(updated);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('선택한 이메일 ${imported.length}개를 저장했습니다.'),
            backgroundColor: AppColors.accent,
          ),
        );
        return;
      case CommunicationSourceAction.callNote:
        return _openManualRecord('call');
      case CommunicationSourceAction.smsPaste:
        return _openManualRecord('sms');
      case CommunicationSourceAction.kakaoPaste:
        return _openManualRecord('kakao');
    }
  }

  Future<void> _openManualRecord(String type) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ManualCommLogModalView(contact: widget.contact, initialType: type),
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
    final updated = widget.contact.copyWith(
      commLogs: widget.contact.commLogs
          .where((log) => log.id != target.id)
          .toList(),
    );
    final radar = context.read<RadarViewModel>();
    radar.updateContact(updated);
    radar.openBriefing(updated);
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bolt,
                        color: AppColors.accentText,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '30초 AI 대화 브리핑',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
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
                      'Gmail에서 선택해 가져오거나 직접 작성한 기록만 표시합니다.',
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
                          '최근 소통 기록이 없습니다. 위 "추가" 버튼에서 Gmail을 선택하거나 통화·문자·카카오톡 내용을 직접 기록해 보세요.',
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
                                        if (log.source == 'gmail') ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Gmail에서 선택',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textMuted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
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

            // Bottom Sticky Phone Call Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.cardSurface,
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // 2026-08-07: 통화를 누르면 전화 앱으로 넘어가면서 대화
                    // 포인트 화면이 그대로 사라져 "외워서 말해야 하는" 문제가
                    // 있었다(사용자 피드백). 제3자 앱이 전화 화면 위에 계속
                    // 떠 있는 건 OS가 막아서(iOS/Android 공통) 화면 자체를
                    // 유지할 수는 없지만, 선택된 대화 포인트를 클립보드에
                    // 복사해 통화 중에도 메모 앱 등에 붙여넣어 참고할 수
                    // 있게 한다.
                    if (_points.isNotEmpty && _selectedIndex < _points.length) {
                      final selectedPoint = _points[_selectedIndex];
                      await Clipboard.setData(
                        ClipboardData(text: selectedPoint),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '선택한 대화 포인트를 복사했어요. 통화 중 메모 앱 등에 붙여넣어 참고하세요.',
                            ),
                            backgroundColor: AppColors.accent,
                          ),
                        );
                      }
                    }
                    widget.onClose();
                    if (!context.mounted) return;
                    await PhoneCallService.showCallPicker(context, contact);
                  },
                  icon: const AppIcon(AppIconId.callCheck, color: Colors.white),
                  label: const Text(
                    '안부 전화 걸기',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
