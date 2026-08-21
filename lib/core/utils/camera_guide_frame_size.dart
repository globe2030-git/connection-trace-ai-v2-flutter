import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
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

/// 가이드 상자의 **짧은 변이 화면 폭에서 차지하는 비율** — 플랫폼별로 다르다.
///
/// ## ⚠️ 왜 플랫폼으로 가르나 — 카메라가 다르기 때문이다
///
/// 가이드를 키우면 이용자가 명함을 **더 가까이** 대게 된다. 그 거리가 렌즈
/// 최소 초점 거리보다 가까우면 **초점이 안 맞는다.** 그 한계가 **기기마다
/// 다르다.**
///
/// 2026-08-21 실기기 실측(아이폰 16 Pro · 갤럭시 폴드):
///
/// | 비율 | 아이폰 초점 | 폴드 커버 초점 |
/// |---|---|---|
/// | 41.3% (개정 전) | ◎ | ◎ (가이드가 작다는 제보) |
/// | 50% | ○ 잡힘 | — |
/// | 55% | △ 아쉽다 | — |
/// | 65% | ✕ **흐림** | ◎ (#384 이후 이 값) |
///
/// ⭐ **같은 65%가 폴드에서는 되고 아이폰에서는 안 됐다.** 화면 크기나
/// 세로세로비 문제가 아니다 — 아이폰과 갤럭시 S24 는 세로세로비가 소수점
/// 둘째 자리까지 같아서, **세로비로는 아예 가를 수 없었다.**
///
/// 📌 플랫폼으로 가르는 것이 편법이 아닌 이유: 원인이 **카메라 하드웨어**에
/// 붙어 있고, 화면 모양이 아니라 그 축으로 갈라야 맞기 때문이다.
///
/// ## ⚠️ 안드로이드는 폴드에서만 확인했다
///
/// 65% 에서 초점이 확인된 안드로이드는 **폴더블 커버 화면 하나**다. 일반
/// 안드로이드(갤럭시 S24 등)에서도 괜찮은지는 **모른다.** 지금 테스터 기기가
/// 폴드라 당장 문제는 없지만, **다른 안드로이드에서 같은 제보가 오면 이
/// 값부터 의심할 것.**
///
/// ## ⚠️ 크기와 초점은 맞바꿈 관계다 — 값으로는 못 푼다
///
/// 아이폰에서 50% 는 초점이 잡히지만 *"맞추기 불편하다"* 는 평가였다.
/// 키우면 초점이 깨지고 줄이면 맞추기 어렵다. **가이드를 크게 두되 꽉 채우지
/// 않아도 되게** 하고 자르기 기준을 검출된 테두리로 옮기는 것이 방향인데,
/// 그건 값이 아니라 화면 설계 변경이라 별건으로 뺐다.
double guideShortEdgeRatioFor(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
        ? kGuideShortEdgeRatioIos
        : kGuideShortEdgeRatioDefault;

/// 아이폰. 초점이 잡히는 것으로 확인된 최대에 가까운 값이다.
const double kGuideShortEdgeRatioIos = 0.50;

/// 아이폰 외. 폴더블 커버에서 초점이 확인된 값이다(#384 부터 쓰던 값).
const double kGuideShortEdgeRatioDefault = 0.65;

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
/// 짧은 변 = min(화면 폭 × 플랫폼별 비율, kGuideMaxShortEdgeDp)
/// 긴 변   = 짧은 변 ÷ 카드 비율,  단 화면 높이 × kGuideMaxHeightRatio 이내
/// ```
///
/// ⚠️ 높이 상한은 그대로 지킨다. 위아래 안내 문구와 촬영 버튼이 함께
/// 들어가야 하고, 폴더블 펼친 가로 화면에서 **아래가 넘친 전례**가 있다.
///
/// 📌 실측 12종에서 높이 상한에 닿는 기기는 없었다 — 아이폰 SE(667dp)처럼
/// 낮은 화면에서도 여유가 있다.
Size guideFrameSizeFor(Size screenSize, {TargetPlatform? platform}) {
  if (screenSize.width <= 0 || screenSize.height <= 0) return Size.zero;

  final ratio = guideShortEdgeRatioFor(platform ?? defaultTargetPlatform);
  var shortEdge = screenSize.width * ratio;
  if (shortEdge > kGuideMaxShortEdgeDp) shortEdge = kGuideMaxShortEdgeDp;

  var longEdge = shortEdge / kCardGuideAspectRatio;
  final maxLongEdge = screenSize.height * kGuideMaxHeightRatio;
  if (longEdge > maxLongEdge) {
    longEdge = maxLongEdge;
    shortEdge = longEdge * kCardGuideAspectRatio;
  }
  return Size(shortEdge, longEdge);
}
