import 'dart:ui' show Size;

/// 명함 촬영 가이드 상자의 가로세로비(짧은 변 / 긴 변).
///
/// 국내 명함 표준 규격(90×50mm, 가로세로비 약 1.8:1)이지만, 가이드 프레임
/// 자체는 세로로 긴 모양(비율을 뒤집음)으로 그린다 — 폰은 계속 세로로 잡고,
/// 명함을 시계 방향으로 90도 돌려서 그 세로 프레임 안에 맞춰 넣는 방식이다.
/// 배경은 `camera_scan_modal_view.dart`의 [CameraScanModalView] 문서 참고.
const double kCardGuideAspectRatio = 184 / 330;


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

/// 가이드 상자의 **짧은 변이 화면 폭에서 차지하는 비율**.
///
/// ## ⚠️ 2026-08-21 개정 — 비율이 아니라 **절대 크기**가 문제였다
///
/// 그 전에는 일반 화면 41.3%, 폴더블 커버만 65%였다. 그런데 실기기 치수를
/// 늘어놓고 보니 **비율은 같은데 절대 크기가 제각각**이었다.
///
/// ```
/// 폴드 펼침      41.3% = 309dp   → "너무 크네" (8/17, 추가 293)
/// 폴드 커버      65.0% = 267dp   → 좋다 (#384 이후)
/// 아이폰 16 Pro  41.3% = 166dp   → "작다" (2026-08-21)
/// ```
///
/// ⭐ **같은 비율이 어떤 화면에서는 크고 어떤 화면에서는 작았다.** 사용자가
/// 반응한 값은 비율이 아니라 **dp** 였다.
///
/// ⚠️ 그리고 아이폰(2.17)과 갤럭시 S24(2.17)는 **세로세로비가 소수점 둘째
/// 자리까지 같다.** 그래서 "아이폰만 키우고 안드로이드는 그대로"는 세로비로는
/// 불가능했다 — 문턱값 방식(옛 `kNarrowAspectThreshold`)을 버린 이유다.
///
/// ## 지금 규칙
///
/// ```
/// 짧은 변 = min(화면 폭 × 0.65, kGuideMaxShortEdgeDp)
/// ```
///
/// 커버 화면에만 걸던 65%를 **전 기기로 넓히고**, 절대 상한을 달았다.
/// 폴드 커버는 267dp 그대로이고, 폴드 펼침은 309 → 267로 **줄어든다**
/// (8/17 "너무 크다" 제보와 방향이 맞는다).
const double kGuideShortEdgeRatio = 0.65;

/// 가이드 상자 짧은 변의 **절대 상한(dp)**.
///
/// ## 왜 267인가 — 이미 확인된 값이다
///
/// 폴더블 커버 화면이 #384 이후 이 크기(267dp)로 돌고 있고, 그 뒤로 크기
/// 제보가 없었다. **240 같은 값은 아무도 써 본 적이 없다.**
///
/// ⚠️ **위로 올릴 때는 초점을 반드시 실기기에서 확인할 것.** 가이드를 키우면
/// 사용자가 명함을 **더 가까이** 대게 되고, 렌즈 최소 초점 거리보다 가까워지면
/// **초점이 영영 안 맞는다** — 2026-08-06에 실제로 겪은 회귀다.
///
/// 📌 반대로 아래로 내리면 **거의 모든 기기가 상한값 하나로 평평해진다**
/// (실측: 240으로 낮추면 12종 중 9종이 240). 화면이 커도 가이드가 안 커져
/// 큰 화면에서 작아 보인다.
const double kGuideMaxShortEdgeDp = 267;

/// 화면 크기에 맞는 명함 촬영 가이드 상자 크기를 계산한다.
///
/// ```
/// 짧은 변 = min(화면 폭 × kGuideShortEdgeRatio, kGuideMaxShortEdgeDp)
/// 긴 변   = 짧은 변 ÷ 카드 비율,  단 화면 높이 × kGuideMaxHeightRatio 이내
/// ```
///
/// ⚠️ 높이 상한은 그대로 지킨다. 위아래 안내 문구와 촬영 버튼이 함께
/// 들어가야 하고, 폴더블 펼친 가로 화면에서 **아래가 넘친 전례**가 있다.
///
/// 📌 실측 12종에서 높이 상한에 닿는 기기는 없었다 — 아이폰 SE(667dp)처럼
/// 낮은 화면에서도 여유가 있다.
Size guideFrameSizeFor(Size screenSize) {
  if (screenSize.width <= 0 || screenSize.height <= 0) return Size.zero;

  var shortEdge = screenSize.width * kGuideShortEdgeRatio;
  if (shortEdge > kGuideMaxShortEdgeDp) shortEdge = kGuideMaxShortEdgeDp;

  var longEdge = shortEdge / kCardGuideAspectRatio;
  final maxLongEdge = screenSize.height * kGuideMaxHeightRatio;
  if (longEdge > maxLongEdge) {
    longEdge = maxLongEdge;
    shortEdge = longEdge * kCardGuideAspectRatio;
  }
  return Size(shortEdge, longEdge);
}
