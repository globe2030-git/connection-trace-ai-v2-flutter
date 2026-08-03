import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/ai_briefing_service.dart';
import '../../../../core/services/comm_log_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/ai_credentials_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../common/glass_card.dart';
import '../../settings/views/ai_connection_modal_view.dart';
import '../../wallet/view_models/wallet_view_model.dart';
import 'manual_comm_log_modal_view.dart';

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

  @override
  void initState() {
    super.initState();
    _points = widget.contact.talkingPoints;
    // 이미 캐시된 대화 포인트가 없고 AI가 연동돼 있으면, 처음 열었을 때
    // 빈 화면 대신 바로 생성해서 보여준다.
    if (_points.isEmpty && context.read<AiCredentialsRepository>().activeProvider != null) {
      _generate();
    }
  }

  Future<void> _generate() async {
    final credentials = context.read<AiCredentialsRepository>();
    final provider = credentials.activeProvider;
    if (provider == null) return;
    final apiKey = credentials.apiKeyFor(provider);
    if (apiKey == null) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final myProfile = context.read<MyProfileRepository>().profile;
      final points = await AiBriefingService.generateTalkingPoints(
        provider: provider,
        apiKey: apiKey,
        model: credentials.modelFor(provider),
        contact: widget.contact,
        myProfile: myProfile,
      );
      if (!mounted) return;
      setState(() {
        _points = points;
        _selectedIndex = 0;
        _isGenerating = false;
      });
      // 다음에 열 때 API를 다시 호출하지 않도록 결과를 인맥 데이터에 캐시.
      context.read<WalletViewModel>().updateContact(widget.contact.copyWith(talkingPoints: points));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e is AiBriefingException ? e.message : '대화 포인트를 생성하지 못했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    final activeProvider = context.watch<AiCredentialsRepository>().activeProvider;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
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
                        const Icon(Icons.bolt, color: AppColors.accentText, size: 22),
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
                      icon: const Icon(Icons.close, color: AppColors.textPrimary, size: 24),
                      onPressed: widget.onClose,
                    )
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
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                            backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
                            child: contact.avatarUrl == null
                                ? Text(
                                    contact.name.substring(0, 1),
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.accentText),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${contact.name} ${contact.title}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Text(
                                  contact.company,
                                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  children: contact.tags.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentText.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: const TextStyle(fontSize: 11, color: AppColors.accentText, fontWeight: FontWeight.w600),
                                      ),
                                    );
                                  }).toList(),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Tailored Talking Points
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '💡 추천 맞춤 대화 포인트',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        if (activeProvider != null)
                          IconButton(
                            icon: _isGenerating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentText),
                                  )
                                : const Icon(Icons.refresh, size: 20, color: AppColors.accentText),
                            onPressed: _isGenerating ? null : _generate,
                            tooltip: '새로 생성',
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activeProvider != null ? '${activeProvider.displayName}가 생성' : 'AI 미연동 상태',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 10),

                    if (activeProvider == null)
                      GlassCard(
                        borderColor: AppColors.accentText.withValues(alpha: 0.4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '🔌 AI 연동이 필요합니다',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '실제 AI가 생성한 맞춤 대화 포인트를 받으려면, 갖고 계신 AI 서비스(Claude/ChatGPT/Gemini)를 먼저 연동해야 지원받을 수 있어요.',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const AiConnectionModalView(),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: const Text('AI 연동하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_isGenerating && _points.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: AppColors.accentText)),
                      )
                    else if (_errorMessage != null && _points.isEmpty)
                      GlassCard(
                        borderColor: AppColors.destructive.withValues(alpha: 0.4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚠️ $_errorMessage',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.destructive),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _generate,
                              child: const Text('다시 시도', style: TextStyle(color: AppColors.accentText, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      )
                    else if (_points.isEmpty)
                      const GlassCard(
                        child: Text(
                          '아직 생성된 대화 포인트가 없습니다. 오른쪽 위 새로고침 버튼으로 생성해 보세요.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                        ),
                      )
                    else ...[
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '⚠️ 새로 생성하지 못해 이전 결과를 보여드려요: $_errorMessage',
                            style: const TextStyle(fontSize: 11, color: AppColors.destructive),
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
                          backgroundColor: isSelected ? AppColors.accentText.withValues(alpha: 0.15) : null,
                          onTap: () => setState(() => _selectedIndex = idx),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: isSelected ? AppColors.accentText : AppColors.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '"$point"',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              )
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
                            '💬 최근 소통 Trace 연동 (통화 / 문자 / 이메일 / 카카오톡)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => ManualCommLogModalView(contact: contact),
                            );
                          },
                          icon: const Icon(Icons.add_circle_outline, size: 16, color: AppColors.accentText),
                          label: const Text('직접 추가', style: TextStyle(fontSize: 12, color: AppColors.accentText, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 아이폰에서 이 목록을 보고 "자동으로 연동되는구나"라고 오해하지
                    // 않도록, 플랫폼별로 실제 가능한 것을 명확히 안내한다 — 통화/문자는
                    // 안드로이드에서만, 이메일은 Google 로그인하면 모든 플랫폼에서 실제
                    // 연동 가능하고, 카카오톡은 API가 없어 "직접 추가"만 가능.
                    Text(
                      CommLogSyncService.isSupportedOnThisPlatform
                          ? '통화·문자·이메일은 실제 데이터와 연동 가능(🔄 배지, "소통 연동" 화면에서), 카카오톡은 "직접 추가"로 기록하세요.'
                          : '이 기기(iOS)에서는 통화·문자 자동 연동이 불가능하지만, 이메일은 Google 로그인으로 연동할 수 있습니다("소통 연동" 화면 참고).',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),

                    if (contact.commLogs.isEmpty)
                      GlassCard(
                        child: const Text(
                          '최근 소통 기록이 없습니다. 위 "직접 추가" 버튼으로 통화·문자·이메일·카카오톡 내용을 기록해 보세요.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                        ),
                      )
                    else
                      ...contact.commLogs.map((log) {
                        IconData icon;
                        Color color;
                        String badge;

                        switch (log.type) {
                          case 'call':
                            icon = Icons.phone_in_talk;
                            color = AppColors.channelCall;
                            badge = '최근통화';
                            break;
                          case 'sms':
                            icon = Icons.sms_outlined;
                            color = AppColors.channelSms;
                            badge = '문자';
                            break;
                          case 'email':
                            icon = Icons.email_outlined;
                            color = AppColors.channelEmail;
                            badge = '이메일';
                            break;
                          case 'kakao':
                          default:
                            icon = Icons.chat_bubble_outline;
                            color = AppColors.channelKakao;
                            badge = '카카오톡';
                            break;
                        }

                        return GlassCard(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, size: 16, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            badge,
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${log.timestamp.month}월 ${log.timestamp.day}일 ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                        ),
                                        if (log.isAutoSynced) ...[
                                          const SizedBox(width: 6),
                                          const Text('🔄 자동 연동', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      log.summary,
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                    if (contact.memo != null) ...[
                      const SizedBox(height: 14),
                      const Text(
                        '📝 Memo Summary',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      GlassCard(
                        child: Text(
                          contact.memo!,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      )
                    ]
                  ],
                ),
              ),
            ),

            // Bottom Sticky Phone Call Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.cardDark,
                border: Border(top: BorderSide(color: AppColors.borderDark)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    widget.onClose();
                    await PhoneCallService.showCallPicker(context, contact);
                  },
                  icon: const Icon(Icons.phone, color: Colors.white),
                  label: const Text(
                    '안부 전화 걸기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
