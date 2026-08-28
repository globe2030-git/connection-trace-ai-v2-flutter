/// 메모에 쌓인 **이전 명함 기록**을 날짜별로 갈라 읽는다.
///
/// ## 왜 메모에서 읽나
///
/// 명함이 바뀐 사람을 다시 등록하면 예전 값이 메모 맨 위에 한 줄로 붙는다
/// (`add_card_modal_view.dart`의 `_applyUpdateToExisting`).
///
/// ```
/// [이전 정보 · 2026-08-19] 회사 / 직함 / 부서 / 휴대폰 / 이메일
/// [이전 정보 · 2026-05-02] 회사 / 직함 / 휴대폰
/// (그 아래는 사용자가 쓴 메모)
/// ```
///
/// 쌓이기는 하는데 **메모 한 덩어리라 눈으로 읽기 나빴다.** 이 파일은 그것을
/// 날짜별로 갈라 화면이 목록으로 그릴 수 있게 한다.
///
/// ## ⚠️ 칸을 되살리지는 **못한다** — 일부러 시도하지 않는다
///
/// 기록할 때 **값이 빈 칸은 통째로 빠진다.** 그래서 조각 개수가 명함마다
/// 다르고, `세 번째 조각`이 부서인지 휴대폰인지 알 방법이 없다. 값 안에
/// `/`가 들어가면(주소에 흔하다) 더 어긋난다.
///
/// 그러므로 [CardHistoryNote.content]는 **적힌 그대로**다. 이 저장소는 화면을
/// 채우려고 없는 것을 지어내지 않는다(CLAUDE.md 4절) — 칸을 추측해 붙이면
/// **틀린 이력이 그럴듯하게** 남는다.
///
/// 칸이 제대로 나뉜 이력이 필요하면 **저장 구조를 바꾸는 것**이 답이지
/// 이 문자열을 파싱하는 것이 아니다.
class CardHistoryNote {
  const CardHistoryNote({required this.date, required this.content});

  /// `2026-08-19` 형식. 기록할 때 쓴 것을 그대로 옮긴다.
  final String date;

  /// 그날 남은 예전 값들. **적힌 그대로**이며 칸으로 나뉘어 있지 않다.
  final String content;

  static final _lineRegExp = RegExp(r'^\[이전 정보 · (\d{4}-\d{2}-\d{2})\]\s*(.*)$');

  /// 메모에서 이력 줄만 골라낸다. 새 기록이 위에 붙으므로 **최신이 앞**이다.
  static List<CardHistoryNote> parse(String? memo) {
    if (memo == null || memo.isEmpty) return const [];
    final out = <CardHistoryNote>[];
    for (final line in memo.split('\n')) {
      final m = _lineRegExp.firstMatch(line.trim());
      if (m == null) continue;
      final content = (m.group(2) ?? '').trim();
      if (content.isEmpty) continue; // 값이 없으면 보여 줄 것도 없다
      out.add(CardHistoryNote(date: m.group(1)!, content: content));
    }
    return out;
  }

  /// 이력 줄만 골라 **원문 그대로** 돌려준다(줄바꿈으로 이은 문자열).
  ///
  /// 저장할 때 이용자가 고친 메모 위에 다시 붙이기 위한 것이다 — [parse]는
  /// 날짜와 내용을 갈라 버리므로 **원문 복원에 쓸 수 없다**(`[이전 정보 · …]`
  /// 머리표가 사라진다).
  ///
  /// ## 🚨 왜 이것이 필요한가 (2026-08-28)
  ///
  /// 편집 화면이 메모 칸에 **이력 줄까지 통째로** 띄우고 저장할 때 그 텍스트를
  /// 그대로 덮어썼다. **이용자가 메모를 정리하며 이력 줄을 지우면 이력이 영영
  /// 사라졌다.** [userMemo]가 그것을 막으려고 있었는데 **부르는 곳이 없었다**
  /// (`grep -rn "userMemo" lib` → 정의 한 줄뿐).
  ///
  /// 📌 CLAUDE.md 4절 표의 *"서비스는 정상, 부르는 쪽이 없음"* 과 같은 자리다.
  static String historyLines(String? memo) {
    if (memo == null || memo.isEmpty) return '';
    return memo
        .split('\n')
        .where((l) => _lineRegExp.hasMatch(l.trim()))
        .map((l) => l.trim())
        .join('\n');
  }

  /// [historyLines]와 [userMemo]를 도로 하나로 잇는다. 저장 직전에 쓴다.
  ///
  /// 이력이 위, 이용자 메모가 아래 — 지금까지 쌓여 온 순서 그대로다.
  /// 둘 다 비면 `null`(메모 없음)이다.
  static String? join({required String history, required String userMemo}) {
    final h = history.trim();
    final u = userMemo.trim();
    if (h.isEmpty && u.isEmpty) return null;
    if (h.isEmpty) return u;
    if (u.isEmpty) return h;
    return '$h\n$u';
  }

  /// 이력 줄을 걷어낸 **사용자가 쓴 메모**만 돌려준다.
  static String userMemo(String? memo) {
    if (memo == null || memo.isEmpty) return '';
    return memo
        .split('\n')
        .where((l) => !_lineRegExp.hasMatch(l.trim()))
        .join('\n')
        .trim();
  }
}
