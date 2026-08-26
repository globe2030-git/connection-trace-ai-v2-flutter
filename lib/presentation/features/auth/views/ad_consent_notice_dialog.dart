import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 광고 수신 동의·철회의 **처리결과 통지**(추가 472).
///
/// ## 🚨 이것은 안내가 아니라 법정 의무다
///
/// 정보통신망법 §50⑦·시행령 §62의2는 수신 동의·철회를 받은 사실을 **14일 이내에
/// 알리도록** 한다. 안내서는 **앱 팝업으로 갈음할 수 있다**고 본다.
///
/// 담아야 하는 것 넷(법률 조사 추가 457):
///
/// | 무엇 | 이 화면에서 |
/// |---|---|
/// | 전송자의 명칭 | *"커넥션센스"* |
/// | 수신 동의·철회의 사실 | *"동의가 / 철회가"* |
/// | **날짜** | 🚨 [processedAt]을 **연·월·일로** 찍는다 |
/// | 처리 결과 | *"정상적으로 처리되었습니다"* |
///
/// ## ⚠️ 두 가지를 하지 마라
///
/// **① *"오늘"·"금일"로 쓰지 마라.** 안내서 p.23이 날짜를 적도록 한다. 이용자가
/// 나중에 이 화면을 기억할 때 *"오늘"*은 아무 정보가 아니고, 증적으로도 쓸 수 없다.
///
/// **② 여기에 광고를 섞지 마라.** 안내서 p.23. *"이참에 이런 것도 있어요"*를
/// 붙이는 순간 **통지가 광고성 정보가 된다.** 그러면 통지 자체가 동의 없는
/// 전송이 될 수 있다.
///
/// ## 철회할 때도 뜬다
///
/// 설정에서 껐을 때도 같은 형식으로 알린다. [consented]가 그 둘을 가른다.
class AdConsentNoticeDialog extends StatelessWidget {
  const AdConsentNoticeDialog({
    super.key,
    required this.processedAt,
    required this.media,
    required this.consented,
  });

  /// 처리한 날짜. **연·월·일로 찍는다.**
  final DateTime processedAt;

  /// 동의한 매체 이름들. 철회일 때는 비어 있다.
  final List<String> media;

  /// `true`면 동의, `false`면 철회.
  final bool consented;

  /// [processedAt]을 *"2026년 9월 15일"* 형태로.
  ///
  /// ⚠️ `intl` 없이 직접 만든다 — 이 앱은 한국어 하나뿐이고, 이 문구는 법정
  /// 통지라 **형식이 흔들리면 안 된다.**
  String get _dateText =>
      '${processedAt.year}년 ${processedAt.month}월 ${processedAt.day}일';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(22, 26, 22, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 26, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          // 전송자 명칭 · 사실 · 날짜 · 결과를 한 문장에 담는다.
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              children: [
                const TextSpan(text: '커넥션센스의\n광고성 정보 수신 '),
                TextSpan(text: consented ? '동의가\n' : '철회가\n'),
                TextSpan(
                  text: _dateText,
                  style: const TextStyle(color: AppColors.accentText),
                ),
                const TextSpan(text: ' 정상적으로\n처리되었습니다.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (media.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '동의하신 매체',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    media.join(', '),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // ⚠️ 여기에 다른 안내를 덧붙이지 마라. 광고가 섞이면 통지 전체가
          //    광고성 정보가 된다(안내서 p.23).
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '확인',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 처리결과 통지를 띄운다.
///
/// 동의·철회를 **저장한 뒤** 부른다. 저장에 실패했으면 부르지 마라 — 처리되지
/// 않았는데 처리되었다고 알리는 셈이 된다.
Future<void> showAdConsentNotice(
  BuildContext context, {
  required bool email,
  required bool push,
  required bool consented,
}) {
  final media = <String>[
    if (email) '이메일',
    if (push) '앱 알림',
  ];
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdConsentNoticeDialog(
      // 기기 시각이다. 증적은 서버의 adConsentNotifiedAt 이 든다 —
      // 화면은 이용자에게 보이는 용도다.
      processedAt: DateTime.now(),
      media: media,
      consented: consented,
    ),
  );
}
