import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/services/ai_usage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/ai_usage_chip.dart';
import '../../../../data/models/contact_model.dart';
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
    // 상단 잔여 칩(AiUsageChip)이 구독하는 최신값을 미리 읽어 둔다.
    AiUsageService.fetch();
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
    final action = await showModalBottomSheet<CommunicationSourceAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunicationSourceSheet(contact: widget.contact),
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
/// - 더보기: OS 공유 시트. 위 셋에 없는 앱(메일·슬랙 등)은 여기로 간다.
class _SendChannelRow extends StatelessWidget {
  final ContactModel contact;
  final String? selectedPoint;

  const _SendChannelRow({required this.contact, required this.selectedPoint});

  /// 문자는 휴대폰 번호로만 보낸다 — 사무실 유선번호로 문자를 보낼 수는 없다.
  bool get _hasMobile => contact.phone.trim().isNotEmpty;

  /// 통화는 둘 중 하나만 있어도 걸 수 있다. 어느 번호로 걸지는 선택 시트가
  /// 정한다(사용자 요청, 2026-08-10).
  bool get _hasAnyPhone =>
      _hasMobile || (contact.officePhone?.trim().isNotEmpty ?? false);

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
            icon: AppIconId.chatSend,
            label: '더보기',
            useMaterialIcon: Icons.ios_share,
            enabled: true,
            onTap: () => _share(context),
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
    if (selectedPoint != null) {
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
    await PhoneCallService.showCallPicker(context, contact);
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
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast(messenger, '문자 앱을 열지 못했어요.');
    }
  }

  Future<void> _kakao(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // 카카오톡에는 "특정 상대에게 미리 채운 메시지"를 여는 공개 경로가 없다.
    // 링크 공유용 스킴은 있지만 이 화면이 보내려는 것은 링크가 아니라 문장이다.
    // 그래서 복사 후 앱만 열어 주고 붙여넣도록 안내한다 — 되는 척하는 것보다
    // 실제 동작을 그대로 알리는 편이 낫다.
    await _copyPoint();
    final uri = Uri.parse('kakaotalk://');

    // ⚠️ `canLaunchUrl`로 먼저 확인하지 않는다. 이 조회는 Android 11+의
    // `<queries>` 선언과 iOS의 `LSApplicationQueriesSchemes`에 의존하는데,
    // 그 선언이 빠져 있으면 **카카오톡이 깔려 있어도 false**를 돌려준다.
    // 실제로 그 상태로 나가서 "설치돼 있지 않아요"라는 잘못된 안내를 했다
    // (사용자 보고, 2026-08-10). 두 선언을 추가했지만, 여는 것 자체는 조회
    // 권한과 무관하게 되므로 **바로 시도하고 실패했을 때만** 안내한다.
    // 조회에 기대지 않는 편이 선언이 또 빠져도 안전하다.
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 앱이 없으면 플랫폼에 따라 예외가 나기도 하고 false가 오기도 한다.
      opened = false;
    }
    if (opened) {
      _toast(messenger, '대화 포인트를 복사했어요. 카카오톡 대화창에 붙여넣어 주세요.');
    } else {
      _toast(messenger, '카카오톡을 열지 못했어요. 대화 포인트는 복사해 뒀으니 붙여넣어 주세요.');
    }
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final point = selectedPoint;
    if (point == null) {
      _toast(messenger, '먼저 전할 대화 포인트를 선택해 주세요.');
      return;
    }
    await SharePlus.instance.share(ShareParams(text: point));
  }
}

class _ChannelButton extends StatelessWidget {
  final AppIconId icon;

  /// 앱 아이콘 세트에 마땅한 것이 없을 때만 쓰는 대체 아이콘(예: 공유).
  final IconData? useMaterialIcon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ChannelButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.useMaterialIcon,
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
                if (useMaterialIcon != null)
                  Icon(useMaterialIcon, size: 20, color: foreground)
                else
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
