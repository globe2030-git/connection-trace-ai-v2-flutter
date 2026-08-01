import 'package:geolocator/geolocator.dart';
import '../utils/geo_utils.dart';

/// 실제 기기 GPS로 현재 위치를 가져온다. 위치 서비스가 꺼져 있거나 권한이
/// 거부된 경우 등 실패 상황에서는 예외를 던지는 대신 null을 반환해서, 호출하는
/// 쪽(RadarViewModel)이 마지막으로 알려진 위치나 강남역 기준 fallback 좌표를
/// 계속 쓸 수 있게 한다 — 위치 권한이 없다고 앱 전체가 못 쓰이게 되면 안 됨.
class LocationService {
  static Future<GeoPosition?> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return GeoPosition(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
