/// 주변 홈 지도 카드(⑥-C, 2026-08-21 확정)의 점 배치를 계산하는 순수 로직.
///
/// ## 왜 위젯에서 분리했나
///
/// "거리·방위 → 화면 좌표"는 숫자 계산이지 그리기가 아니다. `CustomPainter`
/// 안에 묻어 두면 배치가 맞는지 확인하려고 매번 화면을 그려야 한다 — 여기서는
/// 좌표만 계산해 돌려주고, 실제로 원을 그리는 일은
/// `views/nearby_map_card.dart`가 한다.
///
/// ## 좌표계
///
/// 카드 중심을 원점으로 한 정규화 좌표 `dx`/`dy` (각각 -1.0~1.0)를 쓴다.
/// **화면 관례를 따른다** — `dx`는 오른쪽(동쪽)이 양수, `dy`는 **아래쪽
/// (남쪽)이 양수**다. `1.0`은 카드에 그린 반경 링의 가장 바깥(=[displayRadiusMeters])에
/// 닿는 거리라는 뜻이다. 위젯은 이 값에 그릴 반지름(px)을 곱하기만 하면 된다.
library;

import 'dart:math';

import '../../../../core/utils/address_grouping.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';

/// 지도 카드 위 점 하나 — 인맥 한 명이거나, 같은 주소 묶음이거나, 표시
/// 상한을 넘겨 더 묶은 "+N" 뭉치다.
class MapDotPlacement {
  const MapDotPlacement({
    required this.dx,
    required this.dy,
    required this.distanceMeters,
    required this.label,
    required this.count,
    required this.isBadge,
    required this.representative,
  });

  /// 카드 중심 기준 정규화 가로 위치. 오른쪽(동)이 양수.
  final double dx;

  /// 카드 중심 기준 정규화 세로 위치. 아래(남)가 양수.
  final double dy;

  final double distanceMeters;

  /// 원 안에 그릴 글자 — 낱개 인맥이면 이름 첫 글자, 묶음이면 인원수.
  final String label;

  /// 이 점이 대표하는 인맥 수. 낱개면 1.
  final int count;

  /// 숫자 배지 스타일(같은 주소 묶음·표시 상한 초과 뭉치)인지, 이니셜 원인지.
  final bool isBadge;

  /// 묶음의 대표 인맥 — 낱개면 본인, 묶음이면 그 안의 첫 번째 사람(거리·주소
  /// 기준이 되는 인맥). 지금은 접근성 라벨에만 쓴다.
  final ContactModel representative;
}

/// [contactsSortedByDistance]([RadarViewModel.filteredContacts]가 이미
/// 가까운 순으로 정렬해 준다)를 받아 지도 카드에 그릴 점 목록을 계산한다.
///
/// - 같은 주소는 [groupContactsByAddress]로 먼저 묶는다(F-15와 같은 규칙 —
///   한 건물에 여러 명 있으면 목록에서도, 지도에서도 "3명"으로 보여야 지도
///   쪽만 낱개로 흩어지는 모순이 없다).
/// - 묶음 수가 [maxDots]를 넘으면, 가장 가까운 `maxDots - 1`개만 낱개로
///   그리고 나머지는 "+N" 뭉치 하나로 합친다(브리프: "표시 수 상한을 두고
///   넘치면 묶음/생략").
///
/// [displayRadiusMeters]는 카드에 그리는 가장 바깥 링이 나타내는 거리다.
/// 0 이하이거나 무한대면 계산할 척도가 없으므로 빈 목록을 돌려준다 — 호출부가
/// [resolveDisplayRadiusMeters]로 항상 유효한 값을 만들어 넘겨야 한다.
List<MapDotPlacement> computeNearbyMapDots({
  required GeoPosition origin,
  required List<ContactModel> contactsSortedByDistance,
  required double displayRadiusMeters,
  int maxDots = 6,
}) {
  if (displayRadiusMeters <= 0 ||
      displayRadiusMeters.isInfinite ||
      displayRadiusMeters.isNaN) {
    return const [];
  }
  assert(maxDots >= 1, 'maxDots는 최소 1이어야 한다');

  // 같은 주소끼리 먼저 묶는다. 입력이 이미 거리순이므로 groupContactsByAddress가
  // 만드는 묶음 순서도 거리순을 유지한다(각 묶음의 대표 거리 = 그 안 첫 인맥의
  // 거리 — 같은 주소는 좌표도 같아 거리도 같다).
  final groups = groupContactsByAddress(contactsSortedByDistance);

  MapDotPlacement placementFor(AddressGroup group, {int? overrideCount}) {
    final rep = group.contacts.first;
    final distance = GeoUtils.getDistanceMeters(origin, rep.geo);
    final bearingDeg = GeoUtils.getBearingDegrees(origin, rep.geo);
    final bearingRad = bearingDeg * pi / 180.0;
    // 반경 밖(예: "전체" 반경이라 척도를 데이터 최대값으로 잡았는데 그 뒤
    // 갱신 타이밍상 더 먼 사람이 섞여 들어온 경우)으로 나가면 링 가장자리에
    // 붙여 둔다 — 카드 밖으로 점이 튀어나가는 것보다 낫다.
    final fraction = (distance / displayRadiusMeters).clamp(0.0, 1.0);
    final dx = fraction * sin(bearingRad);
    final dy = -fraction * cos(bearingRad);
    final count = overrideCount ?? group.contacts.length;
    final isBadge = count > 1;
    return MapDotPlacement(
      dx: dx,
      dy: dy,
      distanceMeters: distance,
      label: isBadge ? '$count' : _initialOf(rep.name),
      count: count,
      isBadge: isBadge,
      representative: rep,
    );
  }

  if (groups.length <= maxDots) {
    return groups.map(placementFor).toList();
  }

  // 상한 초과 — 가까운 (maxDots - 1)개는 그대로, 나머지는 하나로 뭉친다.
  // maxDots가 1이면 "낱개로 보여줄 자리"가 없으므로 전부 하나의 뭉치가 된다.
  final keepCount = maxDots - 1;
  final kept = groups.take(keepCount).map(placementFor).toList();
  final overflowGroups = groups.skip(keepCount).toList();
  final overflowCount = overflowGroups.fold<int>(
    0,
    (sum, g) => sum + g.contacts.length,
  );
  // 뭉침 점의 위치는 뭉친 것 중 가장 가까운 묶음 자리를 쓴다 — 실제로는
  // 여러 방향에 흩어져 있지만, 대표할 한 점을 정해야 하므로 "그나마 가장
  // 가까운 곳"을 고른다(가장 먼 것보다 존재를 알아채기 쉽다).
  final overflowAnchor = overflowGroups.first;
  final overflowPlacement = placementFor(
    overflowAnchor,
    overrideCount: overflowCount,
  );
  return [...kept, overflowPlacement];
}

/// 이름의 첫 "글자"(코드유닛이 아니라 유니코드 스칼라 하나) — 한글 이름은
/// 대부분 BMP 안이라 `runes.first`만으로 충분하다.
String _initialOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  return String.fromCharCode(trimmed.runes.first);
}

/// 카드에 그릴 가장 바깥 반경(척도)을 정한다.
///
/// - 반경 선택이 유한하면(500m~5km) 그 값을 그대로 척도로 쓴다 — 반경 칩과
///   지도가 같은 숫자를 말해야 "5km로 뒀더니 지도도 5km까지 보이는구나"를
///   사용자가 스스로 확인할 수 있다.
/// - "전체"(무제한)를 골랐으면 척도로 쓸 숫자가 없다. 실제로 있는 사람 중
///   가장 먼 사람의 거리를 척도로 쓴다(전부 카드 안에 들어오게). 그마저
///   없으면(주변에 아무도 없음) 기본값 1km로 둔다 — 텅 빈 카드에 링만
///   그리는 최소한의 크기다.
double resolveDisplayRadiusMeters({
  required double selectedRadiusMeters,
  required List<double> distancesMeters,
  double fallbackMeters = 1000,
}) {
  if (selectedRadiusMeters.isFinite && selectedRadiusMeters > 0) {
    return selectedRadiusMeters;
  }
  if (distancesMeters.isEmpty) return fallbackMeters;
  final maxDistance = distancesMeters.reduce(max);
  if (maxDistance <= 0 || !maxDistance.isFinite) return fallbackMeters;
  return maxDistance;
}
