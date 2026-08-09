import 'package:flutter/material.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';

class NotificationCenterModalView extends StatelessWidget {
  const NotificationCenterModalView({super.key});

  @override
  Widget build(BuildContext context) {
    // 근접 감지/신규 명함 등록 같은 실제 이벤트를 실시간 알림으로 쌓는
    // 파이프라인이 아직 없어서, 가짜 샘플 알림 대신 빈 상태로 둔다.
    final notifications = <Map<String, Object>>[];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
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
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Row(
              children: [
                AppIcon(AppIconId.notification, color: AppColors.accentText),
                SizedBox(width: 8),
                Text(
                  '알림 센터',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (notifications.isEmpty)
              const GlassCard(
                child: Text(
                  '아직 알림이 없습니다. 주변 인맥이 감지되거나 새 명함이 등록되면 여기에 표시됩니다.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),

            ...notifications.map((n) {
              return GlassCard(
                margin: const EdgeInsets.only(bottom: 10),
                borderColor: (n['isNew'] as bool) ? AppColors.accentText : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: (n['isNew'] as bool)
                          ? AppColors.accentText.withValues(alpha: 0.2)
                          : AppColors.borderSubtle,
                      child: AppIcon(
                        AppIconId.notification,
                        size: 18,
                        color: (n['isNew'] as bool)
                            ? AppColors.accentText
                            : AppColors.textMuted,
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
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                n['time'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n['body'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
