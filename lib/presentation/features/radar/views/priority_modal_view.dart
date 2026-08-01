import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../view_models/radar_view_model.dart';

class PriorityModalView extends StatelessWidget {
  const PriorityModalView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RadarViewModel>();
    final allContacts = viewModel.filteredContacts;
    final priorityContacts = allContacts.where((c) => c.isPriority).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
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
                    Icon(Icons.star, color: AppColors.accentText, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '우선 감지 (VIP 알림) 설정',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentText.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.accentText),
                  ),
                  child: Text(
                    'VIP ${priorityContacts.length}명 등록됨',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentText),
                  ),
                )
              ],
            ),

            const SizedBox(height: 14),

            // How it works explanatory banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bgDarkSlate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '💡 우선 감지 기능이란?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.accentText),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '주변에 여러 인맥이 동시에 접근하더라도, 별(★)표 표시된 VIP 인맥을 최우선으로 감지하여 30초 AI 대화 브리핑 알림을 1순위로 띄워주는 기능입니다.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              '⭐ VIP 우선 감지 대상 인맥 목록',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),

            if (priorityContacts.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    '등록된 VIP 우선 감지 인맥이 없습니다.\n명함지갑에서 별(★) 아이콘을 눌러 VIP로 지정해 보세요!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                  ),
                ),
              )
            else
              ...priorityContacts.map((contact) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.bgDarkSlate,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.accentText.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                        backgroundImage: contact.avatarUrl != null ? NetworkImage(contact.avatarUrl!) : null,
                        child: contact.avatarUrl == null
                            ? Text(
                                contact.name.substring(0, 1),
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentText),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${contact.name} ${contact.title}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accentText,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'VIP',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.black),
                                  ),
                                )
                              ],
                            ),
                            Text(
                              contact.company,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.star, color: AppColors.accentText),
                        onPressed: () => viewModel.togglePriority(contact.id),
                      )
                    ],
                  ),
                );
              }),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('확인 완료', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
