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
