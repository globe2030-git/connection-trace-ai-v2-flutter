/// "AI에 보낼 정보" 화면이 **직전에 사용자가 고른 것**을 기억하는 아주 작은
/// 저장소(F-08).
///
/// ## 왜 필요한가
///
/// 한 번 동의하고 나면 그 화면에 다시 들어갈 길이 없었고, 어렵게 다시 열어도
/// **빈 칸에서 시작해 직전에 무엇을 보냈는지 볼 수 없었다.** 그래서 "수정"이
/// 실제로는 "처음부터 다시 쓰기"였다(빌드6·7 테스터 피드백 F-08).
///
/// ## ⚠️ 기기에 저장하지 않는다 — 앱이 켜져 있는 동안만
///
/// 위젯 트리 밖으로 뺀 이유는 테스트 때문이지만, **메모리에만 두는 것은
/// 의도한 설계다.**
///
/// - 소통 기록 선택은 남는 것이 기록 식별자뿐이라 굳이 디스크에 늘릴 이유가
///   없다(2026-08-10 결정).
/// - 메모는 더 조심할 이유가 있다 — **제3자(명함 주인)에 대해 사용자가 직접
///   쓴 문장**이다. 저장하면 저장·백업·다기기 동기화·탈퇴 파기 대상이 하나
///   늘고, 개인정보처리방침에도 반영해야 한다(CLAUDE.md 개인정보 절).
///   방침과 구현이 어긋나는 것 자체가 법적 리스크다.
///
/// 앱을 다시 켜면 아무것도 선택되지 않은 상태(기본 제외, opt-in)로 시작한다.
/// **기기에 남기려면 그건 별도 결정 사항이다.**
class AiDataReviewMemory {
  AiDataReviewMemory._();

  static final Map<String, Set<String>> _selectionByContact = {};
  static final Map<String, String> _noteByContact = {};

  /// 직전에 고른 소통 기록 id. 없으면 빈 집합.
  static Set<String> selectionFor(String contactId) =>
      {...?_selectionByContact[contactId]};

  /// 직전에 적어 둔 메모. 없으면 빈 문자열.
  static String noteFor(String contactId) => _noteByContact[contactId] ?? '';

  /// **동의까지 마친** 선택만 기억한다.
  ///
  /// 화면을 그냥 닫은 경우는 "고른 것"이 아니므로 다음번 기본값이 되어서는
  /// 안 된다 — 안 그러면 눌러 보다 닫은 것이 다음에 전송 대상으로 살아난다.
  static void remember({
    required String contactId,
    required Set<String> selectedLogIds,
    required String note,
  }) {
    _selectionByContact[contactId] = {...selectedLogIds};
    // 비웠으면 **비운 상태를 기억해야 한다.** 지웠는데 다음에 되살아나면
    // 사용자가 지운 문장이 자기도 모르게 다시 전송된다 — 그게 더 나쁘다.
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      _noteByContact.remove(contactId);
    } else {
      _noteByContact[contactId] = trimmed;
    }
  }

  /// 계정 삭제·로그아웃처럼 기기에서 사람을 지울 때 함께 비운다. 메모리에만
  /// 있어 앱을 끄면 사라지지만, 같은 실행 안에서 계정을 갈아타는 경우
  /// **앞 사람의 메모가 뒷사람 화면에 뜨는 것**을 막아야 한다.
  static void clear() {
    _selectionByContact.clear();
    _noteByContact.clear();
  }
}
