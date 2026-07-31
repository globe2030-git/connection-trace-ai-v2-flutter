import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
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
      color: Colors.black.withOpacity(0.85),
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
                        const Icon(Icons.bolt, color: AppColors.accentLime, size: 22),
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
                            backgroundColor: AppColors.accentSky.withOpacity(0.2),
                            child: Text(
                              contact.name.substring(0, 1),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.accentSky),
                            ),
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
                                        color: AppColors.accentSky.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: const TextStyle(fontSize: 11, color: AppColors.accentSky, fontWeight: FontWeight.w600),
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
                        borderColor: isSelected ? AppColors.accentSky : null,
                        backgroundColor: isSelected ? AppColors.accentSky.withOpacity(0.15) : null,
                        onTap: () => setState(() => _selectedIndex = idx),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected ? AppColors.accentSky : AppColors.textMuted,
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

                    if (contact.memo != null) ...[
                      const SizedBox(height: 14),
                      const Text(
                        '📝 메모 서머리',
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
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.phone, color: Colors.white),
                  label: const Text(
                    '안부 전화 걸기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentSky,
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
