import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/contact_export_name.dart';

/// 주소록 **이름 칸 형식**을 고르는 화면(추가 494).
///
/// 두 자리에서 같은 화면을 쓴다.
///
/// | 언제 | [firstTime] |
/// |---|---|
/// | 첫 내보내기 때 한 번 | `true` — 왜 묻는지 설명이 붙는다 |
/// | 설정에서 다시 볼 때 | `false` |
///
/// 한 화면을 두 자리에 쓰는 이유는 **두 벌이 되면 어긋나기** 때문이다. 이
/// 저장소는 광고 수신 동의에서 같은 이유로 화면을 공유하고 있다.
///
/// ## 🚨 미리보기가 있어야 한다
///
/// *"이름 형식을 고르세요"* 만으로는 무엇을 고르는지 모른다. 네 형식이 각각
/// 어떻게 보이는지 **가상값으로** 보여 준다 — 실제 명함을 쓰면 고르는
/// 화면에서 제3자 개인정보가 형식마다 네 번 보이게 된다.
///
/// ## 🚨 "이미 내보낸 것은 바뀌지 않습니다"
///
/// 나중에 형식을 바꿔도 폰에 이미 들어간 이름은 **소급해서 안 고쳐진다.**
/// 적지 않으면 *"바꿨는데 왜 그대로냐"* 가 문의로 온다.
class ContactExportNameFormatSheet extends StatefulWidget {
  const ContactExportNameFormatSheet({
    super.key,
    required this.initial,
    required this.firstTime,
  });

  final ContactExportNameFormat initial;

  /// 첫 내보내기 때인가. 설정에서 열면 `false`.
  final bool firstTime;

  /// 고른 형식을 돌려준다. 뒤로 가면 `null` — **부르는 쪽이 그때 무엇을 할지
  /// 정한다**(첫 물음이면 내보내기를 멈추고, 설정이면 그냥 닫는다).
  static Future<ContactExportNameFormat?> show(
    BuildContext context, {
    required ContactExportNameFormat initial,
    required bool firstTime,
  }) {
    return showModalBottomSheet<ContactExportNameFormat>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContactExportNameFormatSheet(
        initial: initial,
        firstTime: firstTime,
      ),
    );
  }

  @override
  State<ContactExportNameFormatSheet> createState() =>
      _ContactExportNameFormatSheetState();
}

class _ContactExportNameFormatSheetState
    extends State<ContactExportNameFormatSheet> {
  late ContactExportNameFormat _selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '주소록에 어떤 이름으로 저장할까요?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.firstTime
                        ? '직책이나 회사명을 이름에 함께 넣으면 주소록에서 '
                            '동명이인을 가려내기 쉽습니다.'
                        : '앞으로 내보낼 명함에 적용됩니다.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final format in ContactExportNameFormat.values)
                    _FormatRow(
                      format: format,
                      selected: format == _selected,
                      onTap: () => setState(() => _selected = format),
                    ),
                  const SizedBox(height: 12),
                  // 🚨 소급되지 않는다는 것을 화면에 적는다.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 15,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '이미 주소록에 저장한 연락처는 바뀌지 않습니다.'
                          '${widget.firstTime ? '' : ' 설정에서 언제든 다시 바꿀 수 있어요.'}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(widget.firstTime ? '이 형식으로 계속' : '저장'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 형식 한 줄 — **왼쪽에 이름, 오른쪽에 미리보기.**
class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.format,
    required this.selected,
    required this.onTap,
  });

  final ContactExportNameFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.borderSubtle,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // 🚨 미리보기. 가상값이다.
                    Text(
                      previewOf(format),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
