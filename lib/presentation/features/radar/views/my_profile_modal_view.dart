import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/my_profile_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/glass_card.dart';
import 'my_profile_edit_modal_view.dart';

class MyProfileModalView extends StatelessWidget {
  const MyProfileModalView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<MyProfileRepository>().profile;
    final fullAddress =
        (profile.addressDetail != null &&
            profile.addressDetail!.trim().isNotEmpty)
        ? '${profile.address} ${profile.addressDetail}'
        : profile.address;
    // 우편번호가 있으면 주소 앞에 괄호로 붙인다(우편물 표기 관례).
    final postalCode = profile.postalCode?.trim() ?? '';
    final addressLine = postalCode.isEmpty
        ? fullAddress
        : '($postalCode) $fullAddress';

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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    AppIcon(
                      AppIconId.cardWallet,
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '내 디지털 명함',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const AppIcon(
                    AppIconId.editCard,
                    color: AppColors.accentText,
                    size: 24,
                  ),
                  tooltip: '정보 수정',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const MyProfileEditModalView(),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (!profile.isSetUp)
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.person_off_outlined,
                      size: 40,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '아직 내 프로필을 설정하지 않았습니다',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '이름·연락처 등 내 정보를 입력하면 디지털 명함으로 공유할 수 있어요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const MyProfileEditModalView(),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '내 프로필 설정하기',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
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
                          backgroundColor: AppColors.accent.withValues(
                            alpha: 0.2,
                          ),
                          backgroundImage: profile.avatarPath != null
                              ? FileImage(File(profile.avatarPath!))
                              : null,
                          child: profile.avatarPath == null
                              ? Text(
                                  profile.name.isNotEmpty
                                      ? profile.name.substring(0, 1)
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentText,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                _companyLine(profile),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.borderSubtle),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_iphone,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          profile.phone,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if ((profile.officePhone ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _iconLine(Icons.phone_outlined, profile.officePhone!),
                    ],
                    if ((profile.fax ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _iconLine(Icons.print_outlined, profile.fax!),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          profile.email,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if ((profile.website ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _iconLine(Icons.language, profile.website!),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            addressLine,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
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
                icon: const AppIcon(
                  AppIconId.share,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  '디지털 명함 공유하기',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 회사 / 직함 줄. 부서가 있으면 회사 옆에 붙인다 — 별도 줄을 만들면
  /// 이 카드가 세로로 길어지는데, 부서는 회사에 딸린 값이라 같은 줄이 맞다.
  static String _companyLine(MyProfileModel profile) {
    final dept = profile.department?.trim() ?? '';
    final org = dept.isEmpty
        ? profile.company
        : '${profile.company} · $dept';
    return '$org / ${profile.title}';
  }

  /// 휴대폰·이메일 줄과 같은 모양의 한 줄. 선택 항목(사무실 전화·팩스·
  /// 웹사이트)은 값이 있을 때만 그려지므로 이 함수로 모아 둔다.
  static Widget _iconLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
