import 'dart:ui' show Size;

/// 명함 촬영 가이드 상자의 가로세로비(짧은 변 / 긴 변).
///
/// 국내 명함 표준 규격(90×50mm, 가로세로비 약 1.8:1)이지만, 가이드 프레임
/// 자체는 세로로 긴 모양(비율을 뒤집음)으로 그린다 — 폰은 계속 세로로 잡고,
/// 명함을 시계 방향으로 90도 돌려서 그 세로 프레임 안에 맞춰 넣는 방식이다.
/// 배경은 `camera_scan_modal_view.dart`의 [CameraScanModalView] 문서 참고.
const double kCardGuideAspectRatio = 184 / 330;

/// 가이드 상자의 **긴 변이 화면 폭에서 차지하는 비율**(일반 화면).
///
/// ## ⚠️ 줄일 때는 반드시 실기기에서 **초점**을 확인할 것
///
/// 이 값을 줄이면 사용자가 명함을 **더 가까이** 대게 된다. 예전에 가이드를
/// 화면 **높이** 기준으로 잡았다가, 렌즈 최소 초점 거리보다 가까워져
/// **초점이 영영 안 맞는** 문제가 있었다(2026-08-06 실기기,
/// *"가이드에 맞추려 가까이 가면서 초점을 못맞춤"*).
///
/// ## 왜 줄였나 (2026-08-17, 추가 293)
///
/// 실기기에서 *"흰색 가이드가 너무 크네"* — 가이드가 화면을 거의 채워서
/// 명함이 가운데 작게 놓이고, **찍힌 사진에 배경이 많이 들어갔다**
/// (`가이드 크롭 1636x2934`).
///
/// 0.86 → 0.74로 **한 단계만** 줄였다. 이 저장소는 이런 값을 크게 바꿨다가
/// 두 번 되돌린 적이 있다(자르기 여유 1.5 → 1.0 → 1.2).
const double kGuideLongEdgeRatio = 0.74;

/// 가이드 상자 크기를 정할 때 **화면 높이의 최대 몇 %까지** 쓸지.
///
/// 화면이 낮으면(가로 방향, 폴더블 펼침) 가이드가 세로로 넘친다. 위아래
/// 안내 문구와 촬영 버튼이 함께 들어가야 하므로 **높이의 0.72까지만** 쓴다.
///
/// ⚠️ 예전 상한은 0.8이었는데, 그것만으로는 모자라 가로에서
/// `BOTTOM OVERFLOWED BY 52 PIXELS`가 떴다(사용자 제보 "핸드폰을 90도
/// 돌리니까 아래에 노란색이 보여"). 세로 고정(`setPreferredOrientations`)도
/// 함께 걸었지만 **Android는 큰 화면에서 앱의 방향 제한을 무시한다** —
/// 폴더블 펼친 화면에서는 여전히 가로가 되므로 크기 자체를 맞춰야 한다.
const double kGuideMaxHeightRatio = 0.72;

/// 폴더블 **커버 화면**처럼 화면 폭 자체가 좁은 기기에서 가이드를 다시
/// 키우는 문턱값(dp). 화면 폭이 이보다 **좁을 때만**
/// [kNarrowScreenWidthRatio] 보정이 걸린다.
///
/// ⚠️ 갤럭시 폴드(SM-F966N)를 접은 커버 화면에서 촬영 가이드가 작다는
/// 실사용 제보로 추가했다(2026-08-21, fix/fold-cover-capture-guide).
///
/// ## 원인 — [kGuideLongEdgeRatio]는 항상 **화면 폭**만 본다
///
/// [guideFrameSizeFor]는 가이드의 긴 변(세로 방향)을 `화면 폭 × 0.74`로
/// 정한다. 이건 의도된 설계다([kGuideLongEdgeRatio] 문서 참고 — 초점
/// 문제로 "화면 높이" 기준을 이미 한 번 시도했다가 되돌렸다). 문제는
/// **비율이 아니라 절대 폭이다.** 이 비율은 화면 모양과 무관하게 항상
/// "화면 폭의 약 41%"(0.74 × 카드비율)로 고정되는데, 일반 폰이든 커버
/// 화면이든 **같은 비율**이 적용되므로, 커버 화면처럼 폭 자체가 물리적으로
/// 좁은 기기에서는 절대 크기(dp)가 작게 나온다 — 세로 공간은 남아도는데도
/// 그렇다(높이 상한 [kGuideMaxHeightRatio]는 폭 기반 값이 **높이**를 넘칠
/// 때만 걸리므로, 세로로 긴 화면에서는 애초에 걸리지 않는다).
///
/// ## ⚠️ 계산이다, 실측이 아니다
///
/// SM-F966N 실기기가 이 작업에는 배정돼 있지 않아 커버 화면의 정확한 논리
/// 폭(dp)을 재지 못했다. 아래 문턱값 340dp는 **Android가 일반 폰의 최소
/// 폭으로 흔히 쓰는 360dp보다 확실히 좁게** 잡은 값이고, 삼성이 폴더블
/// 커버 화면 반응형 레이아웃 기준으로 안내해 온 폭(대략 300~320dp대)보다는
/// 넉넉하게 잡은 값이다 — **일반 폰을 잘못 건드리지 않는 쪽으로** 여유를
/// 뒀다. 실기기가 배정되면 실제 커버 화면 폭을 재서 이 값과 비율을 다시
/// 맞춰야 한다.
const double kNarrowScreenWidthThreshold = 340.0;

/// 좁은 화면(위 문턱값 아래)에서 가이드가 **화면 폭에서 차지해야 하는
/// 최소 비율**(가이드 상자의 짧은 변 기준).
///
/// 기존 비율(0.74 × 카드비율 ≈ 0.41)보다 뚜렷이 크게 잡아, 폭이 좁아도
/// 절대 크기가 작아 보이지 않게 한다. 세로 공간은 커버 화면일수록 더
/// 넉넉해서(높이 상한 [kGuideMaxHeightRatio]는 그대로 유지) 이만큼 키워도
/// 위아래 여백이 부족해지지 않는다.
const double kNarrowScreenWidthRatio = 0.62;

/// 화면 크기에 맞는 명함 촬영 가이드 상자 크기를 계산한다.
///
/// 일반 폰·펼친 폴드·태블릿(화면 폭이 [kNarrowScreenWidthThreshold] 이상)은
/// 기존 계산 그대로다 — `화면 폭 × 0.74`를 긴 변으로 삼고, 화면 높이의
/// [kGuideMaxHeightRatio]를 넘지 않게 자른 뒤, 짧은 변은 카드 비율로 낸다.
///
/// 화면 폭이 그보다 좁은 화면(폴더블 커버 디스플레이)에서만, 짧은 변이
/// 화면 폭의 [kNarrowScreenWidthRatio] 이상이 되도록 다시 계산한다 — 그래도
/// 긴 변이 [kGuideMaxHeightRatio] 상한을 넘으면 그 상한으로 다시 자른다.
Size guideFrameSizeFor(Size screenSize) {
  var longEdge = screenSize.width * kGuideLongEdgeRatio;
  final maxLongEdge = screenSize.height * kGuideMaxHeightRatio;
  if (longEdge > maxLongEdge) longEdge = maxLongEdge;
  var shortEdge = longEdge * kCardGuideAspectRatio;

  // ⚠️ **폭이 좁은 화면(커버 디스플레이)에서만** 다시 키운다. 일반
  // 폰·펼친 폴드·태블릿은 폭이 이 문턱값보다 항상 넓어 아래 분기를 타지
  // 않고 기존 계산 그대로 나간다 — 그래서 그 기기들의 가이드 크기는 이
  // 보정 전과 **한 픽셀도 다르지 않다.**
  if (screenSize.width < kNarrowScreenWidthThreshold) {
    final boostedShortEdge = screenSize.width * kNarrowScreenWidthRatio;
    if (boostedShortEdge > shortEdge) {
      var boostedLongEdge = boostedShortEdge / kCardGuideAspectRatio;
      if (boostedLongEdge > maxLongEdge) boostedLongEdge = maxLongEdge;
      longEdge = boostedLongEdge;
      shortEdge = longEdge * kCardGuideAspectRatio;
    }
  }

  return Size(shortEdge, longEdge);
}
