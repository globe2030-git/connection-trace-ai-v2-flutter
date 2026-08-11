/// 한글/영문 이름·회사명을 그룹(ㄱ,ㄴ,ㄷ…,A,B,C…,#)으로 묶어 명함지갑의
/// 인덱스 점프에 쓰기 위한 유틸.
///
/// - 한글 음절의 초성 19자 중 된소리(ㄲㄸㅃㅆㅉ)는 기본 자음(ㄱㄷㅂㅅㅈ)으로
///   접어 14자로 단순화한다("깜박" → ㄱ 그룹).
/// - 영문으로 시작하면 대문자 A~Z 그룹으로 묶는다("John" → J).
/// - 그 밖(숫자·기호 등)은 '#' 그룹으로 모은다.
/// - 정렬·인덱스 순서는 한글(가나다) → 영문(A~Z) → 기타(#).
class KoreanInitial {
  /// 유니코드 한글 음절의 초성 순서(19자).
  static const List<String> _choseong = [
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];

  /// 된소리를 기본 자음으로 접는 표.
  static const Map<String, String> _fold = {
    'ㄲ': 'ㄱ', 'ㄸ': 'ㄷ', 'ㅃ': 'ㅂ', 'ㅆ': 'ㅅ', 'ㅉ': 'ㅈ',
  };

  /// 인덱스 바에 쓰는 기본 자음 14자(된소리 접은 뒤의 대표값 순서).
  static const List<String> baseConsonants = [
    'ㄱ', 'ㄴ', 'ㄷ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅅ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
  ];

  /// 한글 아닌 것(영문 등)을 모으는 그룹 라벨.
  static const String other = '#';

  /// [text]의 첫 글자에 해당하는 그룹 라벨을 돌려준다(초성 / 대문자 A~Z / '#').
  static String of(String text) {
    final t = text.trim();
    if (t.isEmpty) return other;
    final ch = t[0];
    final code = ch.codeUnitAt(0);
    // 가(0xAC00) ~ 힣(0xD7A3): 완성형 한글 음절.
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final choseong = _choseong[(code - 0xAC00) ~/ 588];
      return _fold[choseong] ?? choseong;
    }
    final upper = ch.toUpperCase();
    if (upper.codeUnitAt(0) >= 0x41 && upper.codeUnitAt(0) <= 0x5A) {
      return upper; // A~Z
    }
    return other;
  }

  /// 정렬 시 그룹 순서를 매기는 순위: 한글 초성(0~13) → 영문 A~Z(14~39) →
  /// 기타 '#'(40). 이름/회사명 정렬에서 한글을 가나다순으로 앞에, 영문을
  /// 그다음, 숫자·기호를 맨 뒤로 보낸다.
  static int rank(String text) {
    final group = of(text);
    final k = baseConsonants.indexOf(group);
    if (k != -1) return k;
    if (group.length == 1 &&
        group.codeUnitAt(0) >= 0x41 &&
        group.codeUnitAt(0) <= 0x5A) {
      return baseConsonants.length + (group.codeUnitAt(0) - 0x41);
    }
    return baseConsonants.length + 26; // '#'
  }
}
