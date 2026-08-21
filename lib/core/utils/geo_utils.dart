import 'dart:math';

class GeoPosition {
  final double lat;
  final double lng;

  const GeoPosition({required this.lat, required this.lng});
}

class GeoUtils {
  static double getDistanceMeters(GeoPosition? a, GeoPosition? b) {
    if (a == null || b == null) return double.infinity;

    const earthRadiusM = 6371000.0;
    double toRad(double deg) => deg * pi / 180.0;

    final dLat = toRad(b.lat - a.lat);
    final dLng = toRad(b.lng - a.lng);
    final lat1 = toRad(a.lat);
    final lat2 = toRad(b.lat);

    final sinDLat = sin(dLat / 2);
    final sinDLng = sin(dLng / 2);
    final h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLng * sinDLng;
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));

    return earthRadiusM * c;
  }

  static String formatDistanceLabel(double? meters) {
    if (meters == null || meters.isInfinite || meters.isNaN) return '';
    if (meters < 1000) {
      return '${meters.round()}m 근접';
    }
    return '${(meters / 1000.0).toStringAsFixed(1)}km 근접';
  }

  /// [a]에서 [b]를 바라보는 초기 방위각(도, 0=정북, 90=정동, 시계 방향).
  ///
  /// 주변 홈 지도 카드(⑥-C)가 "거리·방향 기준"으로 점을 배치할 때 쓴다 —
  /// 실제 지도 타일이 아니므로 위/아래를 북/남으로 못 박고, 그 안에서 각
  /// 인맥이 어느 쪽에 있는지는 이 각도로만 정한다.
  ///
  /// 둘 중 하나라도 없으면(위치를 모르면) 0을 준다 — 호출부가 애초에 좌표가
  /// 있는 인맥만 넘기므로 실제로는 방어용이다.
  static double getBearingDegrees(GeoPosition? a, GeoPosition? b) {
    if (a == null || b == null) return 0;
    double toRad(double deg) => deg * pi / 180.0;
    final lat1 = toRad(a.lat);
    final lat2 = toRad(b.lat);
    final dLng = toRad(b.lng - a.lng);
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final theta = atan2(y, x);
    return (theta * 180.0 / pi + 360.0) % 360.0;
  }
}
