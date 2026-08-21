/// 지도 보기(`views/nearby_map_view.dart`)가 **처음 무엇을 담을지** 정하는 순수
/// 로직.
///
/// ## 왜 필요했나 (2026-08-22 실기기 실측)
///
/// 반경을 "전체"로 두면 담을 반경 원이 없어서, 초기 배율을 **내 위치만 보고**
/// 줌 12로 고정하고 있었다. 그런데 사용자의 인맥은 내 위치에서 28~37km 떨어진
/// 곳에 몰려 있었다 — 줌 12가 담는 범위는 세로 약 18km라, **"28명을 지도에
/// 표시했습니다"라고 적힌 화면에 핀이 하나도 없었다.** 직접 축소해야 그제서야
/// 나타났다.
///
/// 즉 계산이 틀린 게 아니라 **인맥이 어디 있는지를 안 보고** 범위를 정한 것이
/// 문제였다. 그래서 담을 좌표를 여기서 먼저 정하고, 실제로 배율을 맞추는 일은
/// `flutter_map`의 `CameraFit.coordinates`에 넘긴다.
library;

import 'package:latlong2/latlong.dart';

/// 자동 맞춤이 확대할 수 있는 상한. 인맥이 한 명뿐이고 바로 옆에 있으면 맞춤이
/// 건물 단위까지 파고들어, 어디를 보고 있는지 알 수 없는 화면이 된다.
const double kMapFitMaxZoom = 15;

/// 지도를 열 때 화면에 반드시 들어와야 할 좌표들.
///
/// `null`을 돌려주면 **자동 맞춤을 쓰지 말라**는 뜻이다. 호출부는 그때 기존대로
/// 기준점 중심 + 반경에 맞춘 배율을 쓴다.
///
/// - 반경이 유한하면(500m~5km) `null`. 반경 원이 이미 척도이고, **반경 칩과
///   지도가 같은 숫자를 말해야** 사용자가 "5km로 뒀더니 지도도 5km까지
///   보이는구나"를 스스로 확인할 수 있다. 그 반경 밖 인맥은 애초에 목록에서도
///   걸러져 있으므로 담을 것도 없다.
/// - 반경이 "전체"인데 그릴 인맥이 없으면 `null`. 담을 것이 내 위치뿐이라
///   맞춤이 할 일이 없다.
/// - 그 밖에는 **기준점·내 위치·인맥 좌표 전부**를 돌려준다. 기준점(F-13)과
///   내 위치는 서로 다를 수 있으므로 둘 다 넣는다 — 하나라도 빠지면 사용자가
///   자기 위치나 거리 기준점을 화면 밖에 두고 보게 된다.
List<LatLng>? mapFitCoordinates({
  required double radiusMeters,
  required LatLng center,
  required LatLng myPoint,
  required List<LatLng> contactPoints,
}) {
  if (!radiusMeters.isInfinite) return null;
  if (contactPoints.isEmpty) return null;
  return [center, myPoint, ...contactPoints];
}
