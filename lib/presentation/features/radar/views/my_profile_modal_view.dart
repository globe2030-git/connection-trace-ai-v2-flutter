import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';

class MyProfileModalView extends StatelessWidget {
  const MyProfileModalView({super.key});

  @override
  Widget build(BuildContext context) {
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
                  '👤 내 디지털 명함',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note, color: AppColors.accentSky, size: 24),
                  onPressed: () {},
                )
              ],
            ),
            const SizedBox(height: 14),

            // Profile Card
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.accentSky.withValues(alpha: 0.2),
                        child: const Text(
                          '홍',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.accentSky),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('홍길동 대표', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            Text('커넥션 트레이스 AI / C-Level', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.borderDark),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.phone_iphone, size: 16, color: AppColors.textMuted),
                      SizedBox(width: 8),
                      Text('010-1234-5678', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.email_outlined, size: 16, color: AppColors.textMuted),
                      SizedBox(width: 8),
                      Text('gildong.hong@connectiontrace.ai', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 16, color: AppColors.textMuted),
                      SizedBox(width: 8),
                      Text('서울특별시 강남구 테헤란로 123', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Share Card Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.share, color: Colors.white, size: 18),
                label: const Text('디지털 명함 공유하기', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentSky,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
