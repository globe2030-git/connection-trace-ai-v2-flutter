/// 명함 등록 폼에서 **어떤 칸이 아직 자동 인식 값 그대로인지** 판정한다(F-09).
///
/// ## 왜 파일로 뺐나
///
/// 판정 자체는 한 줄짜리 비교지만, **틀렸을 때 드러나지 않는** 종류의 규칙이다.
/// 표시가 잘못 붙어도 화면은 멀쩡하고 저장도 정상이라 아무도 모른다 — 이
/// 저장소가 반복해서 겪은 "코드는 맞는데 실물이 틀린" 유형이다(CLAUDE.md 4절).
/// 그래서 촬영 품질 판정을 `frame_contrast.dart`로 뺀 것과 같은 이유로,
/// 화면에서 떼어내 테스트로 고정한다.
///
/// ## 규칙
///
/// 자동 인식이 채운 값(`snapshot[key]`)과 **현재 입력값이 같을 때만** "자동
/// 인식됨"으로 본다. 사용자가 한 글자라도 고치면 더 이상 자동 인식 값이 아니다.
///
/// 별도의 "수정됨" 플래그를 두지 않는 이유: 되돌리기(재촬영 취소)·초기화 경로가
/// 여럿이라 플래그를 그때마다 맞춰 줘야 하고, **한 곳이라도 빠지면 표시가
/// 사실과 어긋난다.** 매번 비교하면 상태가 한 벌뿐이라 어긋날 수가 없다.
library;

/// [key] 칸이 아직 자동 인식 값 그대로인가.
///
/// - [key]가 null이면 자동 인식 대상 칸이 아니다(태그·관심사·메모 등) → false
/// - 스냅샷에 그 키가 없으면 이번에 파서가 채우지 못한 칸이다 → false
/// - 스냅샷 값이 비어 있으면 채운 것으로 치지 않는다 → false
/// - 현재 값은 **앞뒤 공백을 떼고** 비교한다. 스냅샷에 넣을 때 이미 `trim()`을
///   거치므로, 여기서 안 떼면 사용자가 공백만 하나 더 쳐도 표시가 사라진다.
bool isStillOcrValue({
  required String? key,
  required Map<String, String> snapshot,
  required String currentText,
}) {
  if (key == null) return false;
  final parsed = snapshot[key];
  if (parsed == null || parsed.isEmpty) return false;
  return parsed == currentText.trim();
}
