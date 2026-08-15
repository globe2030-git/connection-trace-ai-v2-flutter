/// 촬영 확인 화면에서 사용자가 돌린 각도를 다루는 계산(F-03 C안).
///
/// ## 왜 위젯 밖으로 뺐나
///
/// 위젯 없이 규칙만 검사하기 위해서다. 이 저장소의 다른 계산들
/// (`ocr_origin.dart`, `address_grouping.dart`)과 같은 이유다.
///
/// ## 왜 각도만 들고 있다가 마지막에 한 번 굽나
///
/// 회전할 때마다 파일을 새로 쓰면 **누를 때마다 JPEG을 다시 압축**하게 된다.
/// 재인코딩은 매번 화질을 깎는다. 네 번 눌러 제자리로 돌아온 경우에는
/// **아예 다시 구울 필요가 없다** — [needsRebake]가 그 판단을 한다.
library;

/// 시계 방향 90도. `0 → 90 → 180 → 270 → 0`.
///
/// 자동 크롭(`_cropToGuideFrame`)이 이미 반시계 90도로 세워 주므로, 여기서
/// 다루는 각도는 **그 결과 위에 사용자가 더 돌린 만큼**이다.
int nextClockwiseTurn(int currentDegrees) => (currentDegrees + 90) % 360;

/// 다시 구울 필요가 있나. `0`이면 원본 그대로 쓰면 된다.
///
/// 네 번 눌러 제자리로 온 것을 굳이 재인코딩하면 **화질만 깎이고 결과는
/// 같다.**
bool needsRebake(int degrees) => normalizeTurn(degrees) != 0;

/// 어떤 값이 들어와도 `0·90·180·270` 중 하나로 만든다.
///
/// 음수도 받는다 — 나중에 반시계 회전을 붙이더라도 이 함수가 그대로 쓰인다.
int normalizeTurn(int degrees) {
  final m = degrees % 360;
  return m < 0 ? m + 360 : m;
}

/// `RotatedBox`의 `quarterTurns`로 쓸 값(0~3).
///
/// 미리보기는 파일을 다시 굽지 않고 이 값으로만 돌린다 — **누르는 즉시
/// 화면이 바뀌어야** 사용자가 결과를 보고 판단할 수 있다.
int quarterTurnsFor(int degrees) => normalizeTurn(degrees) ~/ 90;
