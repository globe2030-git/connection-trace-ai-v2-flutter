import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/contact_export_name.dart';
import '../../../../data/models/contact_model.dart';

/// 명함을 내보내기 전에 **무엇이 나가는지** 보여 주는 확인 창(추가 492).
///
/// ## 왜 한 단계를 더 두나
///
/// 내보내기는 **제3자(명함 주인)의 개인정보를 앱 밖으로 내보내는** 동작이다.
/// 공유 시트가 바로 뜨면 이용자는 *"무엇이 담긴 파일인지"* 모른 채 카카오톡
/// 목록을 보게 된다. 이 앱은 명함을 암호화해 보관하면서 그 내용을 평문
/// 파일로 내보내는 것이므로, **나가는 것이 무엇인지 먼저 보이는 편**이 맞다.
///
/// ## 🚨 담기는 항목은 **실제로 값이 있는 것만** 보여 준다
///
/// 이메일이 없는 명함에 "이메일"을 적으면 **거짓말**이다. 이 저장소는 화면을
/// 채우려고 없는 것을 만들지 않는다(CLAUDE.md 4절).
class ContactExportConfirmDialog extends StatelessWidget {
  const ContactExportConfirmDialog({
    super.key,
    required this.contact,
    this.nameFormat = ContactExportNameFormat.nameOnly,
  });

  final ContactModel contact;

  /// 주소록 이름 칸 형식(추가 494). 이 창이 **실제로 저장될 이름**을 보여
  /// 주므로, 내보낼 때 쓰는 것과 같은 값이어야 한다 — 다르면 이 창이
  /// 거짓말이 된다.
  final ContactExportNameFormat nameFormat;

  /// 계속을 누르면 `true`. 취소하거나 바깥을 누르면 `false`.
  static Future<bool> show(
    BuildContext context,
    ContactModel contact, {
    ContactExportNameFormat nameFormat = ContactExportNameFormat.nameOnly,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ContactExportConfirmDialog(
        contact: contact,
        nameFormat: nameFormat,
      ),
    );
    return ok ?? false;
  }

  /// 이 명함에서 **실제로 나가는** 항목 이름들.
  ///
  /// [VCardUtil.encodeContact]가 내보내는 것과 짝이 맞아야 한다 — 메모는
  /// 나가지 않으므로 여기에도 없다.
  @visibleForTesting
  static List<String> itemsOf(ContactModel c) {
    bool has(String? v) => v != null && v.trim().isNotEmpty;
    return [
      if (has(c.name)) '이름',
      if (has(c.phone) || has(c.directPhone) || has(c.officePhone)) '전화번호',
      if (has(c.company) || has(c.title) || has(c.department)) '회사·직함',
      if (has(c.email)) '이메일',
      if (has(c.address)) '주소',
      if (has(c.website)) '홈페이지',
      if (has(c.fax)) '팩스',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = itemsOf(contact);
    final name = contact.name.trim();
    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        name.isEmpty ? '이 명함을 연락처에 저장할까요?' : '$name님을 연락처에 저장할까요?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '명함 정보가 담긴 파일(vCard)을 만들고, 저장할 곳(연락처 앱·카카오톡·'
            '메시지 등)을 고르는 화면이 열립니다.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          // 🚨 **주소록에 실제로 들어갈 이름.** 형식에 따라 직책·회사가 붙는데
          //    (추가 494), 보여 주지 않으면 저장한 뒤에야 알게 된다.
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 15,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              const Text(
                '주소록에 저장되는 이름',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  buildExportName(contact, nameFormat),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '파일에 담기는 정보',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in items)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgElevated,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          item,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // 📌 빠지는 것도 말해 준다. 메모는 이용자가 적어 둔 사적인
                //    글이라 내보내지 않는데, 말하지 않으면 **나갔다고 오해**할
                //    수 있다.
                const Text(
                  '메모는 담기지 않습니다.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('계속'),
        ),
      ],
    );
  }
}
