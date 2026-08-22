/// [ManualCropView]의 안내 배너 상태 — 정지 이미지 검출(결함 399)이
/// 정직하게 말하도록 판정만 뽑아낸 순수 함수.
///
/// ## 왜 위젯 밖으로 뺐나
///
/// 이 저장소가 반복해서 겪은 유형은 "코드는 맞는데 실물이 틀린" 것과
/// "로직은 맞는데 화면이 틀린" 것 둘 다다(CLAUDE.md 4절). 배너 문구는 딱
/// 후자가 나기 쉬운 자리 — 위젯 State 안에서만 분기하면 `flutter test`
/// 없이 사람이 화면을 눌러 봐야만 "찾지 못했는데 찾았다고 말하는" 경로가
/// 있는지 알 수 있다. 그 분기를 여기로 빼서 **화면 없이도 검사**한다.
///
/// ⚠️ 이 함수는 "무엇을 보여줄지"만 정한다. **왜 그렇게 정했는지는
/// [ManualCropView]의 문서를 함께 읽어야 한다** — 특히 "왜
/// [autoDetectEnabled]가 꺼진 촬영 경로는 이 함수를 거쳐도 결과가 예전과
/// 같은가"(마지막 갈래가 그 답이다).
library;

import 'crop_mode_corners.dart';

/// 배너에 보여줄 상태의 종류.
enum GalleryCropBannerKind {
  /// 검출이 지금 도는 중 — 짧은 진행 표시를 곁들인다.
  detecting,

  /// 검출을 끝냈지만 못 찾았다. **[autoFound]와 절대 같은 아이콘·문구를
  /// 쓰면 안 된다** — "찾지 못했는데 찾았다고 말하는" 경로가 된다.
  notFound,

  /// 실제로 찾았다(검출 성공, 또는 [autoDetectEnabled]가 꺼진 촬영 경로에서
  /// [CropAdjustMode.auto]를 골랐을 때 — 그 경로는 이 화면에 오기 전에 이미
  /// 실시간 검출·크롭을 거쳤으므로 "찾았다"는 참이다).
  autoFound,

  /// 사용자가 스스로 [직접 조정]을 골랐다(검출과 무관).
  manualHint,
}

/// 지금 상태로 어떤 배너를 보여줄지 정한다.
///
/// [autoDetectEnabled]가 거짓이면(촬영 경로) [detecting]·[notFound]로는
/// 절대 가지 않는다 — [mode]만 보고 [autoFound]/[manualHint] 둘 중 하나로
/// 정하므로, 그 경로는 이 함수를 거쳐도 예전과 글자 하나 다르지 않다.
GalleryCropBannerKind galleryCropBannerKind({
  required bool autoDetectEnabled,
  required bool detecting,
  required bool hasDetectedCorners,
  required CropAdjustMode mode,
}) {
  if (autoDetectEnabled) {
    if (detecting) return GalleryCropBannerKind.detecting;
    // ⚠️ [mode]가 [CropAdjustMode.auto]라는 것만으로는 "찾았다"고 말할 수
    // 없다 — 사용자가 검출 실패 뒤에도 [자동 인식] 탭을 다시 누를 수 있다.
    // 실제로 찾았는지는 오직 [hasDetectedCorners]로만 판단한다.
    if (!hasDetectedCorners) return GalleryCropBannerKind.notFound;
  }
  return mode == CropAdjustMode.auto
      ? GalleryCropBannerKind.autoFound
      : GalleryCropBannerKind.manualHint;
}

/// 배너에 실제로 띄울 문구.
String galleryCropBannerText(GalleryCropBannerKind kind) => switch (kind) {
  GalleryCropBannerKind.detecting => '테두리를 찾는 중이에요…',
  GalleryCropBannerKind.notFound =>
    '테두리를 찾지 못했어요 — 모서리 점을 직접 맞춰 주세요',
  GalleryCropBannerKind.autoFound =>
    '테두리를 자동으로 찾았어요 — 모서리 점을 끌어 바로 고칠 수 있어요',
  GalleryCropBannerKind.manualHint => '네 귀퉁이를 명함 모서리에 맞춰 주세요',
};
