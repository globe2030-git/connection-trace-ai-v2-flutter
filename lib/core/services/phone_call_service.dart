import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/contact_model.dart';
import '../icons/app_icons.dart';
import '../theme/app_colors.dart';
import '../../presentation/common/glass_card.dart';

class PhoneCallService {
  static Future<bool> makeCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanNumber');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  /// 번호가 둘이면 어느 쪽으로 걸지 고르게 하고, 하나뿐이면 바로 건다.
  ///
  /// 예전에는 휴대폰 번호가 반드시 있다고 보고 "사무실 번호가 있으면 시트,
  /// 없으면 휴대폰으로 바로 걸기"로만 나눴다. 그래서 **사무실 번호만 있는
  /// 인맥은 전화를 걸 수 없었다** — 빈 번호로 `tel:`을 열어 아무 일도
  /// 일어나지 않았다. 두 번호를 대칭으로 다룬다(2026-08-10).
  ///
  /// **실제로 전화 걸기가 시작됐으면 true**를 반환한다(시트에서 번호를
  /// 고르지 않고 닫으면 false). 호출한 쪽이 "통화를 시도했다"는 사실에
  /// 의존하는 후속 동작(예: 소통 기록 저장 확인)을 걸 수 있게 하기 위함 —
  /// 시트를 열기만 하고 취소한 경우까지 "통화했다"로 치면, iOS에서 공유
  /// 시트만 닫아도 resumed가 발생해 묵은 확인 다이얼로그가 엉뚱한 시점에
  /// 뜬다(2026-08-11 실기기 QA에서 발견).
  static Future<bool> showCallPicker(
    BuildContext context,
    ContactModel contact,
  ) async {
    final mobile = contact.phone.trim();
    final office = contact.officePhone?.trim() ?? '';
    final hasMobile = mobile.isNotEmpty;
    final hasOfficePhone = office.isNotEmpty;

    if (!hasMobile && !hasOfficePhone) return false;
    if (!hasOfficePhone) {
      return makeCall(mobile);
    }
    if (!hasMobile) {
      return makeCall(office);
    }

    // 시트는 "선택된 번호"를 결과로 돌려주고, 실제 걸기는 여기서 한다.
    // 시트 안에서 makeCall까지 하면 밖에서는 취소와 선택을 구분할 수 없다.
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
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
                  children: [
                    const AppIcon(
                      AppIconId.call,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${contact.name} ${contact.title}님께 전화 걸기',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 📱 Mobile Phone Option
                GlassCard(
                  onTap: () => Navigator.pop(ctx, contact.phone),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.accent,
                        child: Icon(
                          Icons.smartphone,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '휴대폰 전화',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              contact.phone,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ☎️ Office Phone Option
                GlassCard(
                  onTap: () => Navigator.pop(ctx, contact.officePhone),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.accent.withValues(
                          alpha: 0.2,
                        ),
                        child: const Icon(
                          Icons.phone_in_talk,
                          color: AppColors.accentText,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '사무실 전화',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              contact.officePhone!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
    // 시트를 그냥 닫았으면(선택 없음) 통화 시도 자체가 없었던 것이다.
    if (selected == null || selected.trim().isEmpty) return false;
    return makeCall(selected);
  }
}
