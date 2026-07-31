import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';
import 'communication_trace_test_modal_view.dart';

class NotificationCenterModalView extends StatelessWidget {
  const NotificationCenterModalView({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = [
      {
        'title': '📍 근접 알림: 김민준 이사 (140m)',
        'body': '테크노바 김민준 이사님이 근처에 계십니다. 30초 AI 브리핑을 확인해보세요.',
        'time': '방금 전',
        'isNew': true,
      },
      {
        'title': '💡 추천 대화 포인트 생성 완료',
        'body': '한소율 팀장님과의 만남 전 유용한 바이오 R&D 주제 대화 포인트 3개가 준비되었습니다.',
        'time': '12분 전',
        'isNew': true,
      },
      {
        'title': '🎴 신규 명함 자동 등록 완료',
        'body': '오현우 본부장님의 디지털 명함 정보가 성공적으로 저장되었습니다.',
        'time': '2시간 전',
        'isNew': false,
      },
    ];

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
                const Text(
                  '🔔 알림 센터',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const CommunicationTraceTestModalView(),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accentSky.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accentSky.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.sync, size: 14, color: AppColors.accentSky),
                        SizedBox(width: 4),
                        Text(
                          '소통 연동 테스트',
                          style: TextStyle(fontSize: 11.5, color: AppColors.accentSky, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ...notifications.map((n) {
              return GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                borderColor: (n['isNew'] as bool) ? AppColors.accentSky : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: (n['isNew'] as bool)
                          ? AppColors.accentSky.withValues(alpha: 0.2)
                          : AppColors.borderDark,
                      child: Icon(
                        Icons.notifications_active_outlined,
                        size: 18,
                        color: (n['isNew'] as bool) ? AppColors.accentSky : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                n['title'] as String,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              Text(
                                n['time'] as String,
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n['body'] as String,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              );
            }),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
