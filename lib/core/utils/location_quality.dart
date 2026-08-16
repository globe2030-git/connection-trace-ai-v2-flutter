/// 내 위치가 **얼마나 믿을 만한지** 판단한다(E-12, 2026-08-16).
///
/// ## 왜 필요한가
///
/// 테스터가 *"현재 위치 정확도"*를 문제로 올렸는데(통합본 E-12), 오래
/// **재현 조건을 못 좁혀** 남아 있었다. 코드를 열어 보니 재현할 것이 아니라
/// **설계의 결과**였다.
///
/// | 코드 | 무슨 뜻 |
/// |---|---|
/// | `LocationAccuracy.medium` | **중간 정확도** — 수백 미터 오차가 정상 범위다 |
/// | `maxLastKnownAge = 10분` | 새 측위에 실패하면 **최대 10분 전 위치**를 쓴다 |
/// | (없음) | ⚠️ **그 사실을 사용자에게 알려 주지 않았다** |
///
/// 그래서 사용자에게는 *"왜 여기 있는 사람이 안 뜨지"*로만 보인다. **어긋난
/// 것을 알 방법이 없다.**
///
/// ## 무엇을 고쳤나 — 정확도를 올리는 것이 아니라 **알려 주는 것**
///
/// 정확도를 최고로 올리면 측위가 느려지고 배터리를 더 쓴다. 그래서 **정확도는
/// 그대로 두고, 지금 위치가 얼마나 믿을 만한지 화면에 말해 준다.**
///
/// 이 저장소가 명함 정보에서 내린 결론과 같은 결이다 — **못 고쳐도 모른다는
/// 것은 알려줄 수 있다.**
///
/// ## ⚠️ 기준을 절대값으로 두지 않는다
///
/// *"오차 300m면 나쁘다"*는 말이 성립하지 않는다. **감지 반경이 얼마인지에
/// 달렸다** — 반경 10km에서 300m는 무시할 만하고, 반경 500m에서 300m는
/// 목록 자체를 못 믿게 만든다.
///
/// 그래서 **오차를 반경과 견준다.**
library;

/// 오차가 반경의 이 비율을 넘으면 알린다.
///
/// 절반이면 *"근처"*라는 말이 흔들리기 시작한다 — 반경 1km에 오차 500m면
/// 실제로는 500m~1.5km 안 어딘가라는 뜻이다.
const double kCoarseAccuracyRatio = 0.5;

/// 이보다 오래된 위치를 쓰고 있으면 알린다.
///
/// `LocationService.maxLastKnownAge`(10분)보다 짧게 둔다 — **쓸 수 있는 것**과
/// **말없이 써도 되는 것**은 다르다. 3분이면 걸어서 200m쯤 움직인다.
const Duration kStaleFixAge = Duration(minutes: 3);

/// 한 번의 측위 결과와 그 품질.
///
/// [accuracyMeters]가 null이면 **오차를 모른다**는 뜻이지 정확하다는 뜻이
/// 아니다. [age]가 null이면 방금 잰 것이다.
class LocationFixQuality {
  final double? accuracyMeters;
  final Duration? age;

  const LocationFixQuality({this.accuracyMeters, this.age});

  /// 아무것도 모르는 상태. 옛 코드 경로에서 쓴다.
  static const unknown = LocationFixQuality();
}

/// 오차가 반경에 견줘 큰가.
///
/// 반경이 무제한이면 견줄 기준이 없으므로 **알리지 않는다** — 전체를 보는
/// 중이라 오차가 목록을 흔들지 않는다.
bool isCoarseForRadius(double? accuracyMeters, double radiusMeters) {
  if (accuracyMeters == null || accuracyMeters <= 0) return false;
  if (!radiusMeters.isFinite || radiusMeters <= 0) return false;
  return accuracyMeters > radiusMeters * kCoarseAccuracyRatio;
}

/// 지금 쓰는 위치가 오래됐나.
bool isStaleFix(Duration? age) {
  if (age == null) return false;
  if (age.isNegative) return false; // 기기 시계가 흔들린 경우
  return age > kStaleFixAge;
}

/// 화면에 띄울 한 줄. 알릴 것이 없으면 null.
///
/// ⚠️ **둘 다 해당하면 오래된 것을 먼저 말한다.** 오차는 "덜 정확하다"이지만
/// 오래된 위치는 **아예 다른 곳**일 수 있어 더 무겁다.
///
/// 문구에 숫자를 넣는 이유: *"위치가 부정확합니다"*만으로는 사용자가 무엇을
/// 할지 모른다. **얼마나 어긋나는지 알면 판단할 수 있다.**
String? locationQualityNotice({
  double? accuracyMeters,
  Duration? age,
  required double radiusMeters,
}) {
  if (isStaleFix(age)) {
    final minutes = age!.inMinutes;
    return '$minutes분 전 위치를 쓰고 있어요. 실제 위치와 다를 수 있어요.';
  }
  if (isCoarseForRadius(accuracyMeters, radiusMeters)) {
    final m = accuracyMeters!.round();
    return '현재 위치가 약 ${m}m까지 어긋날 수 있어요. 실내에서는 더 큽니다.';
  }
  return null;
}
