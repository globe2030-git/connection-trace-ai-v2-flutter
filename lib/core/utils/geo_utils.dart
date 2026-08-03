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
}
