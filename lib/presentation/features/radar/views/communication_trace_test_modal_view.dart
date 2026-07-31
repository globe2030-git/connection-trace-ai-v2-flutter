import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../view_models/radar_view_model.dart';

class CommunicationTraceTestModalView extends StatefulWidget {
  const CommunicationTraceTestModalView({super.key});

  @override
  State<CommunicationTraceTestModalView> createState() => _CommunicationTraceTestModalViewState();
}

class _CommunicationTraceTestModalViewState extends State<CommunicationTraceTestModalView> {
  String? _selectedContactId;

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
                      Icon(Icons.sync, color: AppColors.accentSky, size: 22),
                      SizedBox(width: 8),
                      Text(
                        '소통 Trace 연동 실시간 테스트',
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

              // Description banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: const Text(
                  '💡 스마트폰 실제 환경에서는 시스템 권한(Call Log, SMS, KakaoTalk, Email API)을 통해 자동 연동됩니다. 아래 버튼을 터치하면 각 채널별 연동 신호를 실시간으로 가상 발생시켜 테스트할 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
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
                  border: Border.all(color: AppColors.accentSky.withValues(alpha: 0.4)),
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

              const Text(
                '📱 4개 채널 실시간 소통 연동 신호 발생',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),

              // 1. 최근 통화 연동 버튼
              _buildChannelButton(
                icon: Icons.phone_in_talk,
                color: AppColors.accentSky,
                title: '📞 최근 통화 수신 연동 테스트',
                subtitle: '수신 통화 (03분 15초) - 신규 프로젝트 추진 안건',
                onTap: () => _triggerCommLog(
                  contact: selectedContact,
                  type: 'call',
                  summary: '수신 통화 (03분 15초) - 신규 프로젝트 추진 안건 논의',
                ),
              ),
              const SizedBox(height: 10),

              // 2. 카카오톡 연동 버튼
              _buildChannelButton(
                icon: Icons.chat_bubble_outline,
                color: const Color(0xFFFEE500),
                title: '💬 카카오톡 메세지 연동 테스트',
                subtitle: '카카오톡 - "다음 주 화요일 미팅 장소 테헤란로로 확정했습니다!"',
                onTap: () => _triggerCommLog(
                  contact: selectedContact,
                  type: 'kakao',
                  summary: '카카오톡 메세지 - "다음 주 화요일 미팅 장소 테헤란로로 확정했습니다!"',
                ),
              ),
              const SizedBox(height: 10),

              // 3. 이메일 연동 버튼
              _buildChannelButton(
                icon: Icons.email_outlined,
                color: Colors.amber,
                title: '✉️ 이메일 수신 연동 테스트',
                subtitle: '이메일 - [테크노바] 2026 하반기 파트너십 계약서 최종본.pdf',
                onTap: () => _triggerCommLog(
                  contact: selectedContact,
                  type: 'email',
                  summary: '이메일 수신 - [${selectedContact.company}] 2026 하반기 파트너십 계약서 최종본.pdf',
                ),
              ),
              const SizedBox(height: 10),

              // 4. SMS 문자 연동 버튼
              _buildChannelButton(
                icon: Icons.sms_outlined,
                color: AppColors.accentLime,
                title: '📱 SMS 문자 메세지 연동 테스트',
                subtitle: '문자 - "역삼동 사무실 도착했습니다. 로비 1층에서 뵐게요."',
                onTap: () => _triggerCommLog(
                  contact: selectedContact,
                  type: 'sms',
                  summary: '문자 메시지 - "역삼동 사무실 도착했습니다. 로비 1층에서 뵐게요."',
                ),
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
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgDarkSlate,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _triggerCommLog({
    required ContactModel contact,
    required String type,
    required String summary,
  }) {
    final newLog = CommunicationLogModel(
      type: type,
      summary: summary,
      timestamp: DateTime.now(),
    );

    final updatedLogs = [newLog, ...contact.commLogs];
    final updatedContact = contact.copyWith(commLogs: updatedLogs);

    final viewModel = context.read<RadarViewModel>();
    // Update contact in repository
    viewModel.updateContact(updatedContact);

    Navigator.pop(context);

    // Immediately open Briefing Overlay for the updated contact so user sees the new log!
    viewModel.openBriefing(updatedContact);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 ${contact.name} 님의 [${_getTypeName(type)}] 소통 연동 신호가 발생하여 AI 브리핑에 반영되었습니다!'),
        backgroundColor: AppColors.accentSky,
      ),
    );
  }

  String _getTypeName(String type) {
    switch (type) {
      case 'call':
        return '최근통화';
      case 'sms':
        return '문자';
      case 'email':
        return '이메일';
      case 'kakao':
      default:
        return '카카오톡';
    }
  }
}
