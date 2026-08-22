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
