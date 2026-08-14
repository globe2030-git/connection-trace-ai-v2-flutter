/// 방금 스캔한 것이 **같은 명함의 뒷면**인지, **다른 명함**인지 판정한다.
///
/// 명함 한 장은 앞면과 뒷면까지가 최대다. 앞면을 찍고 이어서 뒷면을 찍으면
/// 빈 칸을 채워야 하지만, 전혀 다른 명함을 찍었는데 그대로 이어붙이면 **두
/// 사람의 정보가 한 명함에 섞인다.**
///
/// 예전에는 **이름 하나만** 비교했다. 그래서 앞면에서 이름을 못 읽으면
/// (`이름`이 빈 값) 감지가 아예 안 됐고, 다른 명함이 조용히 섞였다.
/// 2026-08-14에 인식 규칙을 "확신하지 못하면 비운다"로 바꾸면서 이름이 빈
/// 경우가 103장 기준 9장 → 24장으로 늘어, 이 구멍이 더 자주 열리게 됐다
/// (backlog 추가 183·189).
///
/// 그래서 **휴대폰과 이메일까지** 본다. 둘은 앞뒷면이 같거나 한쪽에만 있지,
/// 같은 사람인데 서로 다른 값이 나오는 일은 없다.
///
/// ⚠️ **회사명은 일부러 안 본다.** 같은 명함이라도 앞면은 한글, 뒷면은 영문
/// 표기인 경우가 흔해서(`크림하우스(주)` / `CREAMHOUSE`) 다른 명함으로
/// 잘못 잡는다.
class ScanConflict {
  const ScanConflict._();

  /// 기존 값과 새 스캔 값이 **둘 다 있는데 서로 다르면** 다른 명함으로 본다.
  /// 한쪽이 비어 있으면 판단 근거가 없으므로 충돌로 보지 않는다.
  static bool looksLikeDifferentCard({
    required String existingName,
    required String scannedName,
    required String existingPhone,
    required String scannedPhone,
    required String existingEmail,
    required String scannedEmail,
  }) {
    return _conflicts(existingName, scannedName, _normalizeName) ||
        _conflicts(existingPhone, scannedPhone, _normalizePhone) ||
        _conflicts(existingEmail, scannedEmail, _normalizeEmail);
  }

  static bool _conflicts(
    String existing,
    String scanned,
    String Function(String) normalize,
  ) {
    final a = normalize(existing);
    final b = normalize(scanned);
    if (a.isEmpty || b.isEmpty) return false;
    return a != b;
  }

  /// 이름은 음절 사이 공백만 다른 경우가 흔해 공백을 무시한다
  /// (`최 태 웅` / `최태웅`).
  static String _normalizeName(String v) => v.replaceAll(RegExp(r'\s'), '');

  /// 전화번호는 구분자(하이픈·점·공백·괄호)가 제각각이라 숫자만 남겨 비교한다.
  static String _normalizePhone(String v) => v.replaceAll(RegExp(r'\D'), '');

  /// 이메일은 대소문자만 다른 경우가 있어 소문자로 맞춘다.
  static String _normalizeEmail(String v) => v.trim().toLowerCase();
}
