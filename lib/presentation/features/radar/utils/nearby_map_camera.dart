/// 지도 보기(`views/nearby_map_view.dart`)가 **처음 무엇을 담을지** 정하는 순수
/// 로직.
///
/// ## 왜 필요했나 (2026-08-22 실측)
///
/// **첫 번째 문제** — 반경을 "전체"로 두면 담을 반경 원이 없어서, 초기 배율을
/// **내 위치만 보고** 줌 12로 고정했다. 그런데 인맥이 28~37km 떨어져 있으면
/// 줌 12가 담는 범위(세로 약 18km)를 벗어나, **"28명을 지도에 표시했습니다"라고
/// 적힌 화면에 핀이 하나도 없었다.** 그래서 인맥 좌표까지 담도록 고쳤다(추가 391).
///
/// **두 번째 문제** — 이번엔 반대로 벌어졌다. 좌표 하나가 다른 인맥들보다 훨씬
/// 멀면(추가 392의 이상값) 그 하나 때문에 화면이 전국 단위로 벌어져, **핀 30개가
/// 전부 화면 위쪽 20%에 몰려** 보였다. 사용자 요구는 "화면 중앙에 보이게"였다.
///
/// 두 문제의 뿌리는 같다 — **화면 범위를 정할 때 분포를 안 봤다.** 처음에는
/// 내 위치만 봤고, 그 다음에는 최댓값까지 다 봤다. 그래서 여기서는 **무리가
/// 있는 곳**을 기준으로 잡고, 거기서 크게 벗어난 것만 첫 화면에서 뺀다.
///
/// 📌 뺀 인맥의 핀도 **지도에는 그대로 있다.** 축소하거나 밀면 보인다 — 첫
/// 화면에 안 들어올 뿐이다. 몇 명이 밖에 있는지는 아래 바에 글자로 밝힌다.
library;

import 'package:latlong2/latlong.dart';

/// 자동 맞춤이 확대할 수 있는 상한. 인맥이 한 명뿐이고 바로 옆에 있으면 맞춤이
/// 건물 단위까지 파고들어, 어디를 보고 있는지 알 수 없는 화면이 된다.
const double kMapFitMaxZoom = 15;

/// 이상값을 가르는 기준 — "무리의 끝"([kMapFitBulkPercentile]번째 백분위수)의
/// 몇 배까지를 무리로 볼 것인가.
///
/// ⚠️ **잰 값이 아니라 고른 값이다.** 실제 인맥 분포를 표본으로 재서 정한 것이
/// 아니라, 아래 두 경우가 각각 맞게 동작하도록 고른 값이다.
///
/// | 분포 | 무리의 끝 | 문턱(×1.5) | 결과 |
/// |---|---|---|---|
/// | 서울권에 28~37.9km로 몰림 | 약 37km | 약 55km | **아무도 안 빠진다** |
/// | 위 + 230km 이상값 하나 | 약 37km | 약 55km | **그 하나만 빠진다** |
///
/// 즉 **뭉쳐 있으면 아무도 안 빼고, 튀는 것만 뺀다.** 실제 분포를 재게 되면
/// 이 값부터 다시 볼 것.
const double kMapFitOutlierSlack = 1.5;

/// "무리의 끝"으로 볼 백분위수. `nearby_map_layout.dart`의 카드 척도와 같은
/// 값을 쓴다 — 카드와 지도가 서로 다른 기준으로 잘라 내면, 같은 데이터를 두고
/// 두 화면이 다른 이야기를 하게 된다.
const int kMapFitBulkPercentile = 90;

/// 지도를 열 때 어떻게 맞출지에 대한 답.
class MapFitPlan {
  const MapFitPlan({required this.coordinates, required this.outsideCount});

  /// 화면에 반드시 들어와야 할 좌표들. `null`이면 **자동 맞춤을 쓰지 말라**는
  /// 뜻이고, 호출부는 기준점 중심 + 반경에 맞춘 배율을 쓴다.
  final List<LatLng>? coordinates;

  /// 첫 화면 밖에 남는 인맥 수. 핀은 지도에 그대로 있고, 축소하면 보인다.
  final int outsideCount;

  bool get usesFit => coordinates != null;
}

/// 지도 보기의 첫 화면 범위를 정한다.
///
/// [contactsNearestFirst]는 **가까운 순으로 정렬돼 있어야 한다** —
/// `RadarViewModel.filteredContacts`가 그렇게 준다.
///
/// - 반경이 유한하면(500m~5km) 맞춤을 쓰지 않는다. 반경 원이 이미 척도이고,
///   **반경 칩과 지도가 같은 숫자를 말해야** 사용자가 "5km로 뒀더니 지도도
///   5km까지 보이는구나"를 스스로 확인할 수 있다. 그 반경 밖 인맥은 애초에
///   목록에서도 걸러져 있으므로 담을 것도 없다.
/// - 반경이 "전체"인데 그릴 인맥이 없으면 맞춤을 쓰지 않는다.
/// - [includeAll]이면 이상값까지 전부 담는다(사용자가 "전체 보기"를 고른 경우).
/// - 그 밖에는 **기준점·내 위치 + 무리에 드는 인맥**을 담는다. 기준점(F-13)과
///   내 위치는 서로 다를 수 있으므로 둘 다 넣는다 — 하나라도 빠지면 사용자가
///   자기 위치나 거리 기준점을 화면 밖에 두고 보게 된다.
MapFitPlan resolveMapFit({
  required double radiusMeters,
  required LatLng center,
  required LatLng myPoint,
  required List<({LatLng point, double distanceMeters})> contactsNearestFirst,
  bool includeAll = false,
}) {
  if (!radiusMeters.isInfinite) {
    return const MapFitPlan(coordinates: null, outsideCount: 0);
  }
  if (contactsNearestFirst.isEmpty) {
    return const MapFitPlan(coordinates: null, outsideCount: 0);
  }

  final points = <LatLng>[center, myPoint];
  if (includeAll) {
    for (final c in contactsNearestFirst) {
      points.add(c.point);
    }
    return MapFitPlan(coordinates: points, outsideCount: 0);
  }

  final threshold = bulkThresholdMeters([
    for (final c in contactsNearestFirst) c.distanceMeters,
  ]);
  var outside = 0;
  for (final c in contactsNearestFirst) {
    if (c.distanceMeters > threshold) {
      outside++;
    } else {
      points.add(c.point);
    }
  }
  return MapFitPlan(coordinates: points, outsideCount: outside);
}

/// "이 위치에서 다시 찾기" 버튼을 보여줄지 정한다(추가 445, 배달·부동산 앱에
/// 흔한 패턴).
///
/// 지도를 아주 살짝만 옮겼는데 버튼이 뜨면 잡음이다 — 확대하려고 두 손가락을
/// 살짝 눌러도, 손이 떨려도 지도 중심은 미세하게 움직인다. 그래서 일정 거리
/// 이상 벗어났을 때만 보여준다.
///
/// ⚠️ **이 문턱은 잰 값이 아니라 고른 값이다.** 실사용 이동 거리 분포를 재서
/// 정한 것이 아니라 "동네를 벗어났다고 느낄 만한 거리"로 어림잡았다. 실사용에서
/// "버튼이 너무 자주(또는 안) 뜬다"는 제보가 오면 재검토 대상.
const double kMapRefindThresholdMeters = 300;

/// [movedMeters]만큼 지도 중심이 원래 기준점에서 벗어났으면 `true`.
bool shouldShowRefindHereButton(double movedMeters) =>
    movedMeters.isFinite && movedMeters > kMapRefindThresholdMeters;

/// 무리로 볼 거리의 상한. 가까운 순으로 정렬된 [distancesNearestFirst]에서
/// [kMapFitBulkPercentile]번째 백분위수(최근접 순위)를 잡고 여유를 곱한다.
///
/// ⚠️ 가장 가까운 인맥 하나는 **항상 무리에 든다.** 표본이 하나뿐이거나 전부
/// 같은 거리여도 빈 화면이 나오지 않게 하기 위함이다.
double bulkThresholdMeters(List<double> distancesNearestFirst) {
  if (distancesNearestFirst.isEmpty) return double.infinity;
  final n = distancesNearestFirst.length;
  var rank = (n * kMapFitBulkPercentile / 100).ceil();
  if (rank < 1) rank = 1;
  if (rank > n) rank = n;
  final bulkEnd = distancesNearestFirst[rank - 1];
  final threshold = bulkEnd * kMapFitOutlierSlack;
  // 무리의 끝이 0이면(전부 같은 자리) 곱해도 0이라 아무도 못 든다.
  final first = distancesNearestFirst.first;
  return threshold > first ? threshold : first;
}
