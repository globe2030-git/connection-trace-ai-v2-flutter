import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/comm_log_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../briefing/views/manual_comm_log_modal_view.dart';
import '../view_models/radar_view_model.dart';

class CommunicationTraceTestModalView extends StatefulWidget {
  const CommunicationTraceTestModalView({super.key});

  @override
  State<CommunicationTraceTestModalView> createState() => _CommunicationTraceTestModalViewState();
}

class _CommunicationTraceTestModalViewState extends State<CommunicationTraceTestModalView> {
  String? _selectedContactId;
  bool _isSyncingCall = false;
  bool _isSyncingSms = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RadarViewModel>();
    final contacts = viewModel.filteredContacts;

    if (_selectedContactId == null && contacts.isNotEmpty) {
      _selectedContactId = contacts.first.id;
    }

    final selectedContact = contacts.firstWhere(
      (c) => c.id == _selectedContactId,
      orElse: () => contacts.first,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync, color: AppColors.accentText, size: 22),
                      SizedBox(width: 8),
                      Text(
                        '소통 이력 연동',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),

              const SizedBox(height: 14),

              // Description banner — 플랫폼에 따라 실제로 가능한 것과 불가능한 것이
              // 다르므로(안드로이드: 통화/문자 자동 연동 가능, iOS: OS 정책상 불가),
              // 문구를 명확히 나눠서 "iOS에서도 자동 연동되는 것처럼" 오해하지 않게 함.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CommLogSyncService.isSupportedOnThisPlatform
                      ? AppColors.bgDarkSlate
                      : AppColors.destructive.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CommLogSyncService.isSupportedOnThisPlatform
                        ? AppColors.borderDark
                        : AppColors.destructive.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  CommLogSyncService.isSupportedOnThisPlatform
                      ? '🔄 이 기기(Android)에서는 통화·문자 기록을 실제로 읽어와 자동 연동할 수 있습니다. 카카오톡·이메일은 API 자체가 없어 직접 입력으로 기록합니다.'
                      : '📱 iOS는 OS 정책상 앱이 통화기록·문자·카카오톡에 접근하는 것 자체가 불가능해 자동 연동을 지원하지 않습니다. 아래에서 직접 입력으로 기록해 주세요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: CommLogSyncService.isSupportedOnThisPlatform
                        ? AppColors.textSecondary
                        : AppColors.destructive,
                    height: 1.4,
                    fontWeight: CommLogSyncService.isSupportedOnThisPlatform ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Select Contact Dropdown
              const Text(
                '👤 테스트할 인맥 선택',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accentText.withValues(alpha: 0.4)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedContact.id,
                    isExpanded: true,
                    dropdownColor: AppColors.cardDark,
                    items: contacts.map((c) {
                      return DropdownMenuItem<String>(
                        value: c.id,
                        child: Text(
                          '${c.name} ${c.title} (${c.company})',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedContactId = val;
                        });
                      }
                    },
                  ),
                ),
              ),

              const SizedBox(height: 18),

              Text(
                CommLogSyncService.isSupportedOnThisPlatform ? '🔄 자동 연동 (실제 기기 데이터)' : '🔒 자동 연동 (이 플랫폼에서는 불가)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),

              // 1. 최근 통화 연동 버튼 — 안드로이드에서는 실제 통화기록 API 연동
              _buildChannelButton(
                icon: Icons.phone_in_talk,
                color: AppColors.channelCall,
                title: '📞 최근 통화 기록 연동',
                subtitle: CommLogSyncService.isSupportedOnThisPlatform
                    ? '${selectedContact.name} 님과의 통화 기록을 실제로 불러옵니다'
                    : 'iOS에서는 지원되지 않는 기능입니다',
                isLoading: _isSyncingCall,
                enabled: CommLogSyncService.isSupportedOnThisPlatform,
                onTap: () => _syncCallLogs(selectedContact),
              ),
              const SizedBox(height: 10),

              // 2. SMS 문자 연동 버튼 — 안드로이드에서는 실제 문자함 API 연동
              _buildChannelButton(
                icon: Icons.sms_outlined,
                color: AppColors.channelSms,
                title: '📱 문자 메시지 연동',
                subtitle: CommLogSyncService.isSupportedOnThisPlatform
                    ? '${selectedContact.name} 님과 주고받은 문자를 실제로 불러옵니다'
                    : 'iOS에서는 지원되지 않는 기능입니다',
                isLoading: _isSyncingSms,
                enabled: CommLogSyncService.isSupportedOnThisPlatform,
                onTap: () => _syncSmsMessages(selectedContact),
              ),

              const SizedBox(height: 18),

              const Text(
                '📝 수동 입력 (카카오톡·이메일은 이 방식으로 기록)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),

              // 3. 카카오톡 — 어떤 플랫폼도 개인 대화 읽기 API가 없어 항상 수동 입력만 가능
              _buildChannelButton(
                icon: Icons.chat_bubble_outline,
                color: AppColors.channelKakao,
                title: '💬 카카오톡 메시지 직접 입력',
                subtitle: '카카오톡으로 나눈 대화 내용을 직접 기록합니다',
                onTap: () => _openManualEntry(selectedContact, 'kakao'),
              ),
              const SizedBox(height: 10),

              // 4. 이메일 — 실제 연동은 OAuth 등 별도 작업 필요, 그때까진 수동 입력
              _buildChannelButton(
                icon: Icons.email_outlined,
                color: AppColors.channelEmail,
                title: '✉️ 이메일 직접 입력',
                subtitle: '주고받은 이메일 내용을 직접 기록합니다',
                onTap: () => _openManualEntry(selectedContact, 'email'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelButton({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
    bool isLoading = false,
  }) {
    final effectiveColor = enabled ? color : AppColors.textMuted;
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgDarkSlate,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: effectiveColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: effectiveColor),
                    )
                  : Icon(enabled ? icon : Icons.lock_outline, color: effectiveColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: effectiveColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (enabled) const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _syncCallLogs(ContactModel contact) async {
    if (!CommLogSyncService.isSupportedOnThisPlatform) return;
    setState(() => _isSyncingCall = true);
    try {
      final logs = await CommLogSyncService.syncCallLogs(contact.phone);
      if (!mounted) return;
      if (logs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일치하는 통화 기록을 찾지 못했습니다.'), backgroundColor: AppColors.textMuted),
        );
        return;
      }
      _mergeSyncedLogsAndShowBriefing(contact, logs, channelLabel: '통화');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ 통화 기록 연동 실패: $e'), backgroundColor: AppColors.destructive),
      );
    } finally {
      if (mounted) setState(() => _isSyncingCall = false);
    }
  }

  Future<void> _syncSmsMessages(ContactModel contact) async {
    if (!CommLogSyncService.isSupportedOnThisPlatform) return;
    setState(() => _isSyncingSms = true);
    try {
      final logs = await CommLogSyncService.syncSmsMessages(contact.phone);
      if (!mounted) return;
      if (logs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일치하는 문자 메시지를 찾지 못했습니다.'), backgroundColor: AppColors.textMuted),
        );
        return;
      }
      _mergeSyncedLogsAndShowBriefing(contact, logs, channelLabel: '문자');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ 문자 메시지 연동 실패: $e'), backgroundColor: AppColors.destructive),
      );
    } finally {
      if (mounted) setState(() => _isSyncingSms = false);
    }
  }

  void _mergeSyncedLogsAndShowBriefing(
    ContactModel contact,
    List<CommunicationLogModel> newLogs, {
    required String channelLabel,
  }) {
    // 같은 타임스탬프를 가진 항목은 이미 연동된 것으로 보고 중복 추가하지 않음.
    final existingTimestamps = contact.commLogs.map((l) => l.timestamp).toSet();
    final toAdd = newLogs.where((l) => !existingTimestamps.contains(l.timestamp)).toList();
    final updatedLogs = [...toAdd, ...contact.commLogs]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final updatedContact = contact.copyWith(commLogs: updatedLogs);

    final viewModel = context.read<RadarViewModel>();
    viewModel.updateContact(updatedContact);

    Navigator.pop(context);
    viewModel.openBriefing(updatedContact);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 ${contact.name} 님의 실제 $channelLabel 기록 ${toAdd.length}건을 연동했습니다!'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _openManualEntry(ContactModel contact, String initialType) {
    Navigator.pop(context); // 이 테스트 모달을 닫고
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualCommLogModalView(contact: contact, initialType: initialType),
    );
  }
}
