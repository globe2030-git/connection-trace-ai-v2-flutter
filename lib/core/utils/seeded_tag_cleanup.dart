/// 예전 입력칸 기본값(`AI, IT`)이 **그대로 남은** 태그인지 판정한다.
///
/// 2026-08-14까지 명함 등록 화면의 태그 입력칸에 `'AI, IT'`가 미리 채워져 있어,
/// 직업·업종과 무관하게 그 값이 저장됐다(빌드6·7 통합본 E-08, backlog 추가 204).
/// 기본값 자체는 없앴지만 **이미 저장된 명함에는 남아 있다.**
///
/// ⚠️ 이 판정이 틀리면 **사용자가 직접 넣은 맞는 태그를 지운다.** 그래서 대상을
/// 최대한 좁게 잡는다 — 태그가 **정확히 `AI`와 `IT` 둘뿐**일 때만 참이다.
/// 하나라도 다른 태그가 함께 있으면 사용자가 이 칸을 의식하고 손댔다는 뜻이므로
/// 건드리지 않는다. 진짜 AI·IT 업계 사람이 기본값을 그대로 둔 경우와는 구별할
/// 방법이 없으니, 실행 전에 사람에게 확인받는 경로에서만 쓴다.
library;

const _seeded = {'ai', 'it'};

/// [tags]가 손대지 않은 기본값 그대로인가.
///
/// 대소문자와 앞뒤 공백은 무시한다(`' ai '`, `'It'`). 빈 항목도 무시한다 —
/// `'AI, IT,'`처럼 쉼표가 남은 입력이 실제로 들어온다.
bool isSeededDefaultTagSet(List<String> tags) {
  final normalized = tags
      .map((t) => t.trim().toLowerCase())
      .where((t) => t.isNotEmpty)
      .toSet();
  return normalized.length == _seeded.length && normalized.containsAll(_seeded);
}
