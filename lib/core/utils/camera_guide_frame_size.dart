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

/// 폴더블 **커버 화면**처럼 세로로 유난히 긴 화면에서 가이드를 다시 키우는
/// 문턱값 — 화면 **세로세로비**(높이/폭)가 이 값 **이상일 때만**
/// [kNarrowAspectMaxShortEdgeRatio] 보정이 걸린다.
///
/// ⚠️ 갤럭시 폴드(SM-F966N)를 접은 커버 화면에서 촬영 가이드가 작다는
/// 실사용 제보로 추가했다(2026-08-21, fix/fold-cover-capture-guide).
///
/// ## 1차 수정(폭 문턱값)이 실기기에서 틀렸다 — 경위
///
/// 처음에는 "화면 **폭**이 340dp보다 좁을 때"로 게이트를 걸었다(계산이었고,
/// 실기기가 배정되지 않아 실측하지 못한 채 냈다). **실측 결과 틀렸다**
/// (2026-08-21, `adb dumpsys display`로 SM-F966N을 직접 잰 값):
///
/// | | 물리 해상도 | density | 논리 폭 | 논리 높이 |
/// |---|---|---|---|---|
/// | 커버(접힘) | 1080×2520px | 420 | **411.4dp** | 960dp |
/// | 펼침 | 1968×2184px | 420 | 749.7dp | 831.4dp |
///
/// **커버 화면 논리 폭이 411.4dp로, 340dp 문턱값보다 훨씬 넓었다.** 심지어
/// 일반 폰 폭(360~412dp)보다도 넓다 — **폭이 원인이 아니었다.** 사용자
/// 실물 캡처·영상 실측으로도 확인됐다: 가이드 상자가 화면 폭의 약 41%,
/// 높이의 약 31%를 차지해 **기존 계산식과 정확히 일치**했다(= 1차 수정의
/// 보정 분기가 실기기에서 **한 번도 발동하지 않았다**). 이 저장소가 반복해
/// 겪은 "계산했다 ≠ 확인했다"의 또 다른 사례다.
///
/// ## 진짜 원인 — 폭이 아니라 **세로세로비**
///
/// 커버 화면(411.4×960dp)의 세로세로비는 **2.33**이다. 일반 폰
/// (360~412dp 폭, 800~915dp 안팎 높이)의 세로세로비는 대략 **2.0~2.22**에
/// 머문다 — 실측 커버 화면과 폭은 비슷하거나 더 좁은데도 **비율이 확연히
/// 다르다.** [kGuideLongEdgeRatio]가 항상 "화면 폭 × 0.74"로만 긴 변을
/// 정하기 때문에, 폭이 비슷해도 세로 공간이 훨씬 남는 화면(=세로세로비가
/// 큰 화면)에서는 그 남는 공간을 전혀 못 쓰고 가이드가 작게 떠 보인다 —
/// 검출된 명함 테두리는 화면을 거의 채우는데 가이드만 그 안에 조그맣게
/// 있는 상태(실물 캡처로 확인).
///
/// ## 문턱값 2.25를 고른 근거
///
/// 일반 폰 상한(약 2.22, 실측 커버와 **같은 논리 폭 411dp**에서도 비율만
/// 다르면 안 걸려야 함)과 실측 커버 비율(2.33) **사이**에 여유를 두고
/// 잡았다. 코드에 아래 `kNarrowAspectThreshold`로 남아 있다.
const double kNarrowAspectThreshold = 2.25;

/// 세로세로비가 [kNarrowAspectThreshold] 이상인 화면에서, 가이드 상자의
/// **짧은 변이 화면 폭에서 차지할 수 있는 최대 비율**(안전 상한).
///
/// ## ⚠️ 무한정 키우지 않는다 — 초점 거리 회귀 재발 방지
///
/// [kGuideLongEdgeRatio] 문서에 남아 있는 대로, 가이드를 과하게 키우면
/// 사용자가 명함을 렌즈 최소 초점 거리보다 가깝게 대야 해서 **초점이 영영
/// 안 맞는** 회귀가 이미 한 번 있었다(2026-08-06). 그래서 세로세로비가
/// 아무리 커도 짧은 변은 **화면 폭의 65%를 넘지 않게** 상한을 둔다 —
/// 일반 화면의 기존 비율(약 41%)보다는 뚜렷이 크지만, 화면을 거의 채우는
/// 수준(예전에 되돌렸던 0.86 시절의 문제 — "배경이 많이 들어갔다")까지는
/// 가지 않는 값이다.
///
/// 세로 공간은 커버 화면일수록 더 넉넉해서(높이 상한
/// [kGuideMaxHeightRatio]는 그대로 유지) 이만큼 키워도 위아래 여백이
/// 부족해지지 않는다 — 실측 커버(411.4×960dp)에서 계산해도 긴 변이 높이의
/// 약 50%로, 상한(72%)에 전혀 닿지 않는다.
const double kNarrowAspectMaxShortEdgeRatio = 0.65;

/// 화면 크기에 맞는 명함 촬영 가이드 상자 크기를 계산한다.
///
/// 세로세로비(높이/폭)가 [kNarrowAspectThreshold] 미만인 화면(일반
/// 폰·펼친 폴드·태블릿)은 기존 계산 그대로다 — `화면 폭 × 0.74`를 긴
/// 변으로 삼고, 화면 높이의 [kGuideMaxHeightRatio]를 넘지 않게 자른 뒤,
/// 짧은 변은 카드 비율로 낸다.
///
/// 세로세로비가 그 이상인 화면(폴더블 커버 디스플레이)에서만, 짧은 변이
/// 화면 폭의 [kNarrowAspectMaxShortEdgeRatio]가 되도록 다시 계산한다 —
/// 그래도 긴 변이 [kGuideMaxHeightRatio] 상한을 넘으면 그 상한으로 다시
/// 자른다.
Size guideFrameSizeFor(Size screenSize) {
  var longEdge = screenSize.width * kGuideLongEdgeRatio;
  final maxLongEdge = screenSize.height * kGuideMaxHeightRatio;
  if (longEdge > maxLongEdge) longEdge = maxLongEdge;
  var shortEdge = longEdge * kCardGuideAspectRatio;

  // ⚠️ **세로세로비가 큰 화면(커버 디스플레이)에서만** 다시 키운다. 일반
  // 폰·펼친 폴드·태블릿은 비율이 이 문턱값보다 항상 작아 아래 분기를
  // 타지 않고 기존 계산 그대로 나간다 — 그래서 그 기기들의 가이드
  // 크기는 이 보정 전과 **한 픽셀도 다르지 않다.** (1차 수정의 폭
  // 문턱값과 달리, 이번엔 **비율**로 갈라야 실측 커버 화면에서 실제로
  // 걸린다 — 위 [kNarrowAspectThreshold] 문서의 경위 참고.)
  if (screenSize.width > 0) {
    final aspect = screenSize.height / screenSize.width;
    if (aspect >= kNarrowAspectThreshold) {
      final cappedShortEdge =
          screenSize.width * kNarrowAspectMaxShortEdgeRatio;
      if (cappedShortEdge > shortEdge) {
        var boostedLongEdge = cappedShortEdge / kCardGuideAspectRatio;
        if (boostedLongEdge > maxLongEdge) boostedLongEdge = maxLongEdge;
        longEdge = boostedLongEdge;
        shortEdge = longEdge * kCardGuideAspectRatio;
      }
    }
  }

  return Size(shortEdge, longEdge);
}
