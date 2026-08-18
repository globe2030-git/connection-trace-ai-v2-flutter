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
/// 같은 칸에 들어갈 두 값을 비교할 때 **무엇을 같은 값으로 볼지**는 칸마다
/// 다르다. 전화번호는 구분자를, 이름은 음절 사이 공백을, 이메일은 대소문자를
/// 무시해야 한다. 그 규칙을 칸 종류로 고른다.
enum ScanValueKind {
  name,
  phone,
  email,

  /// 회사명·직함·주소처럼 자유 문장인 칸. 앞뒤 공백과 이어진 공백만 정리해
  /// 비교한다 — **한글/영문 표기 차이는 다른 값으로 본다.**
  ///
  /// 다른 명함인지 판정할 때는 회사명을 일부러 안 보지만(위 주석), 칸 단위로
  /// 고를 때는 이야기가 다르다. `크림하우스(주)`와 `CREAMHOUSE`는 **둘 다
  /// 쓸모 있는 값이고 어느 쪽을 남길지는 사용자가 정할 일**이다.
  text,
}

class ScanConflict {
  const ScanConflict._();

  /// 한 칸에 대해, **이미 있는 값과 새로 읽은 값이 사실상 다른지**.
  ///
  /// 한쪽이 비어 있으면 충돌이 아니다 — 빈 칸을 채우는 것은 고를 일이 없다.
  ///
  /// `looksLikeDifferentCard`가 "이 스캔 전체가 다른 사람 것인가"를 묻는다면,
  /// 이쪽은 "이 칸 하나를 어느 값으로 둘 것인가"를 묻는다(F-01). 뒷면을 이어
  /// 찍었을 때 **이미 채워진 칸에 들어온 값이 조용히 버려지던 것**을 사용자
  /// 눈앞에 꺼내기 위한 판정이다.
  static bool valuesConflict({
    required String existing,
    required String scanned,
    required ScanValueKind kind,
  }) {
    final normalize = switch (kind) {
      ScanValueKind.name => _normalizeName,
      ScanValueKind.phone => _normalizePhone,
      ScanValueKind.email => _normalizeEmail,
      ScanValueKind.text => _normalizeText,
    };
    return _conflicts(existing, scanned, normalize);
  }

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

  /// 자유 문장은 줄바꿈·연속 공백만 한 칸으로 정리한다. OCR이 같은 줄을 두
  /// 칸 띄어 읽는 일이 흔한데, 그걸 다른 값이라고 물으면 고를 것이 없는
  /// 물음이 된다.
  static String _normalizeText(String v) =>
      v.trim().replaceAll(RegExp(r'\s+'), ' ');
}
