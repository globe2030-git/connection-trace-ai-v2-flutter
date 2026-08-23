/// 크롭 UX 공존안(P2-③)의 **[자동 인식]/[직접 조정] 시작 귀퉁이** 계산.
///
/// ## 왜 위젯 밖으로 뺐나
///
/// 세그먼트를 바꾸거나 [회전]을 누를 때마다 "귀퉁이를 어디서 다시
/// 시작할지"를 정하는 규칙이다 — 화면 없이도 검증할 수 있는 순수 값이라
/// `card_quad_geometry.dart`와 같은 이유로 뺐다.
///
/// ⚠️ **왜 세그먼트를 바꾸면 귀퉁이를 리셋하나**: 두 모드가 좌표를
/// 공유하면 "자동에서 살짝 다듬던 것"과 "직접 조정에서 새로 잡던 것"이
/// 섞인다. 이 저장소는 회전과 자르기 좌표를 섞어 실기기에서 두 번 헤맨
/// 적이 있다(추가 273) — 모드 사이에서도 같은 실수를 하지 않기 위해
/// 리셋을 규칙으로 고정한다.
library;

import 'dart:ui';

enum CropAdjustMode { auto, manual }

/// "자동 인식" 시작 귀퉁이 — 부르는 쪽이 이미 자른 사진 위에서 살짝 다듬는
/// 자리라 안쪽으로 거의 붙여 시작한다.
const kAutoModeStartCorners = [
  Offset(0.02, 0.02),
  Offset(0.98, 0.02),
  Offset(0.98, 0.98),
  Offset(0.02, 0.98),
];

/// "직접 조정" 시작 귀퉁이 — 처음부터 새로 잡을 여지를 준다.
const kManualModeStartCorners = [
  Offset(0.08, 0.08),
  Offset(0.92, 0.08),
  Offset(0.92, 0.92),
  Offset(0.08, 0.92),
];

/// 모드에 맞는 시작 귀퉁이를 돌려준다. 세그먼트 전환·[회전]·[다시 찾기]가
/// 모두 이 함수 하나로 리셋한다 — 세 자리가 각자 다른 상수를 참조하기
/// 시작하면 그중 하나만 바뀌었을 때 조용히 어긋난다.
List<Offset> cropStartCornersFor(CropAdjustMode mode) => switch (mode) {
  CropAdjustMode.auto => kAutoModeStartCorners,
  CropAdjustMode.manual => kManualModeStartCorners,
};

/// [cropStartCornersFor]에 **정지 이미지 검출 결과**(결함 399,
/// `gallery_auto_detect.dart`)를 얹은 버전.
///
/// 왜 따로 두나: [ManualCropView]가 갤러리 경로에서 [자동 인식]을 고를 때,
/// "이미 잘린 사진을 살짝 다듬는 자리"([kAutoModeStartCorners], 2~98%)는
/// 전제 자체가 성립하지 않는다 — 갤러리 원본은 잘린 적이 없다. 그래서
/// [autoDetectEnabled]가 켜져 있을 때는 세 갈래로 나눈다.
///
/// | 상황 | 시작 귀퉁이 |
/// |---|---|
/// | 자동 인식 + 실제로 찾음([detectedCorners] 있음) | **찾은 자리 그대로** |
/// | 자동 인식 + 아직 못 찾음(검출 중이거나 실패) | [kManualModeStartCorners] — "찾았다"는 상자를 보여주지 않는다 |
/// | 직접 조정, 또는 [autoDetectEnabled]가 꺼짐(촬영 경로) | [cropStartCornersFor]와 완전히 같다 |
///
/// ⚠️ 마지막 줄이 중요하다 — **촬영 경로는 이 함수를 써도 결과가 예전과
/// 한 치도 다르지 않다.** [autoDetectEnabled]가 꺼져 있으면 첫 번째·두
/// 번째 갈래에 들어가지 않기 때문이다.
List<Offset> cropStartCornersForDetection({
  required CropAdjustMode mode,
  required bool autoDetectEnabled,
  List<Offset>? detectedCorners,
}) {
  // ⚠️ [autoDetectEnabled]를 먼저 본다 — [detectedCorners]가 우연히
  // 채워져 있어도, 이 플래그가 꺼져 있으면(촬영 경로) 검출 결과를 아예
  // 쳐다보지 않는다. 그래야 "촬영 경로는 예전과 완전히 같다"는 계약이
  // 호출하는 쪽의 실수(예: 잘못 채운 detectedCorners)로부터도 지켜진다.
  if (!autoDetectEnabled) return cropStartCornersFor(mode);
  if (mode == CropAdjustMode.auto) {
    return detectedCorners ?? kManualModeStartCorners;
  }
  return cropStartCornersFor(mode);
}

/// [corners]를 이미지가 **시계 방향 90도** 돌아갔을 때의 좌표로 옮긴다.
///
/// ## 왜 재검출 대신 이 함수인가([회전] 지연 개선)
///
/// [회전]을 누르면 사진은 이미 `bakeImageRotation`이 실제로 돌려 새로
/// 굽는다 — 그런데 예전에는 `_detectedCorners`·사용자가 손으로 맞춘
/// `_corners`를 **버리고** 돌아간 사진에 검출을 처음부터 다시 돌렸다.
/// 검출은 싸지 않고(디코드+리사이즈+OpenCV), 무엇보다 **사용자가 이미
/// 맞춰 둔 조정이 회전 한 번에 날아갔다.** 이 함수는 재검출 대신 정확한
/// 좌표 변환으로 그 자리를 대신한다.
///
/// ## 공식
///
/// [corners]는 **이미지 정규 좌표(0~1)**다. 픽셀로 풀면 원본 크기 (W,H)의
/// 점 (x,y)가 시계 방향 90도 회전 뒤 (H−y, x)로 옮겨간다. 정규 좌표로
/// 되돌리면 W·H가 서로 지워져 `(1−y, x)` 하나만 남는다 — 그래도
/// [oldImageSize]를 인자로 받는 것은 이 사실이 우연이 아니라 **의도**임을
/// 코드에 남기기 위해서다. 호출부가 실수로 이미 픽셀 좌표를 넘기면(0~1
/// 범위를 벗어나면) `assert`가 즉시 드러낸다 — 디버그 빌드에서만이지만,
/// "좌표계가 섞였는데 조용히 통과한다"보다는 낫다.
///
/// ⚠️ **호출하는 쪽이 알아야 할 것**: 이 함수는 좌표만 옮길 뿐, 화면이
/// 들고 있는 이미지 크기(회전 뒤 가로세로가 (H,W)로 바뀐다)는 대신
/// 계산해주지 않는다 — `ManualCropView`는 회전 뒤 실제 파일을 다시 읽어
/// (`_loadImageSize`) 채운다.
///
/// 90도를 네 번 적용하면 원래 좌표로 돌아온다(항등) — 테스트로 고정.
List<Offset> rotateCornersCw90(List<Offset> corners, Size oldImageSize) {
  assert(
    oldImageSize.width > 0 && oldImageSize.height > 0,
    'rotateCornersCw90: 회전 전 이미지 크기가 있어야 한다',
  );
  return [for (final c in corners) Offset(1 - c.dy, c.dx)];
}

/// [rotateCornersCw90]의 **역함수** — 반시계 90도(P2-③ 2차, "반시계 회전이
/// 안 된다" 실기기 피드백).
///
/// [rotateCornersCw90]이 (x,y)→(1−y,x)이므로, 그 역은 (x,y)→(y,1−x)다.
/// `ccw(cw(p)) == p`, `cw(ccw(p)) == p`가 항상 성립한다(테스트로 고정) —
/// 두 함수가 서로 다른 공식으로 각자 구현돼 있으면 언젠가 하나만 고쳐져
/// 어긋난다는 걱정을 덜기 위해 이 관계 자체를 테스트로 못박아 둔다.
///
/// 매개변수·계약은 [rotateCornersCw90]과 동일 — [oldImageSize]는 계산에
/// 쓰이지 않고 assert로 잘못된 호출만 드러낸다.
List<Offset> rotateCornersCcw90(List<Offset> corners, Size oldImageSize) {
  assert(
    oldImageSize.width > 0 && oldImageSize.height > 0,
    'rotateCornersCcw90: 회전 전 이미지 크기가 있어야 한다',
  );
  return [for (final c in corners) Offset(c.dy, 1 - c.dx)];
}
