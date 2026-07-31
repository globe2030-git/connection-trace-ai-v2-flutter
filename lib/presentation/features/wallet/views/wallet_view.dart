import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';
import '../view_models/wallet_view_model.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WalletViewModel>();

    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.bgGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '명함 지갑',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppColors.accentSky, size: 28),
                      onPressed: () {},
                    )
                  ],
                ),
                const SizedBox(height: 12),

                // Search Bar Input
                TextField(
                  onChanged: viewModel.setSearchTerm,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '이름, 회사, 직함 검색',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.cardDark,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: AppColors.borderDark),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Tag Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: viewModel.allTags.map((tag) {
                      final isSelected = viewModel.selectedTags.contains(tag);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text('#$tag'),
                          selected: isSelected,
                          onSelected: (_) => viewModel.toggleTag(tag),
                          selectedColor: AppColors.accentSky,
                          backgroundColor: AppColors.cardDark,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 14),

                // Contact List
                Expanded(
                  child: ListView.builder(
                    itemCount: viewModel.filteredContacts.length,
                    itemBuilder: (context, index) {
                      final contact = viewModel.filteredContacts[index];
                      return GlassCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.accentSky.withOpacity(0.2),
                              child: Text(
                                contact.name.substring(0, 1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accentSky,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        contact.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        contact.title,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    contact.company,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.accentSky,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    contact.phone,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                contact.isPriority ? Icons.star : Icons.star_border,
                                color: contact.isPriority ? AppColors.accentLime : AppColors.textMuted,
                              ),
                              onPressed: () => viewModel.togglePriority(contact.id),
                            )
                          ],
                        ),
                      );
                    },
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
