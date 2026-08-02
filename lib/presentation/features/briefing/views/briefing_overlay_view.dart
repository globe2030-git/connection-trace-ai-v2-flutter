import 'package:flutter/material.dart';
import '../../../../core/services/comm_log_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../common/glass_card.dart';

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

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;

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
                    const Text(
                      '💡 추천 맞춤 대화 포인트',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 10),

                    ...contact.talkingPoints.asMap().entries.map((entry) {
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

                    // Recent Communication History Integration Trace
                    const SizedBox(height: 16),
                    const Text(
                      '💬 최근 소통 Trace 연동 (통화 / 문자 / 이메일 / 카카오톡)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    // 아이폰에서 이 목록을 보고 "자동으로 연동되는구나"라고 오해하지
                    // 않도록, 플랫폼별로 실제 가능한 것을 명확히 안내한다 — 통화/문자는
                    // 안드로이드에서만 실제 연동되고, 카카오톡/이메일은 어느 플랫폼에서도
                    // 아직 데모 데이터다.
                    Text(
                      CommLogSyncService.isSupportedOnThisPlatform
                          ? '통화·문자는 실제 기기 데이터와 연동 가능(🔄 배지), 카카오톡·이메일은 아직 데모입니다.'
                          : '이 기기(iOS)에서는 자동 연동이 불가능합니다 — 아래는 전부 데모 데이터입니다.',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),

                    if (contact.commLogs.isEmpty)
                      GlassCard(
                        child: const Text(
                          '최근 소통 기록이 없습니다. 이메일/문자/카카오톡 연동 대기 중...',
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
