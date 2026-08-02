import 'package:flutter/services.dart';

/// 숫자만 입력해도 한국 전화번호 형식(하이픈 포함)에 맞춰 자동으로 정리해 주는
/// 입력 포맷터. 서울 지역번호(02)는 2-3-4 / 2-4-4로, 그 외(휴대폰 010 등, 다른
/// 지역번호)는 3-3-4 / 3-4-4로 자릿수에 따라 나눈다. 사용자가 직접 하이픈을
/// 입력해도 무시하고 숫자만 뽑아서 다시 규칙대로 배치하므로, 붙여넣기로 들어온
/// "01012345678" 같은 값도 그대로 정리된다.
class KoreanPhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final limited = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = limited.startsWith('02')
        ? _formatWithAreaCodeLength(limited, 2)
        : _formatWithAreaCodeLength(limited, 3);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _formatWithAreaCodeLength(String digits, int areaCodeLength) {
    if (digits.length <= areaCodeLength) {
      return digits;
    }
    if (digits.length <= areaCodeLength + 4) {
      return '${digits.substring(0, areaCodeLength)}-${digits.substring(areaCodeLength)}';
    }
    final remaining = digits.length - areaCodeLength;
    final middleLength = remaining - 4 > 4 ? 4 : remaining - 4;
    final middleEnd = areaCodeLength + middleLength;
    return '${digits.substring(0, areaCodeLength)}-${digits.substring(areaCodeLength, middleEnd)}-${digits.substring(middleEnd)}';
  }
}
