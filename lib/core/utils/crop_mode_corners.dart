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
