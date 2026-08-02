import 'package:geocoding/geocoding.dart';
import '../utils/geo_utils.dart';

class AddressValidationResult {
  final bool isValid;
  final String originalAddress;
  final String? roadNameAddress;
  final GeoPosition? geoPosition;
  final String? message;

  const AddressValidationResult({
    required this.isValid,
    required this.originalAddress,
    this.roadNameAddress,
    this.geoPosition,
    this.message,
  });
}

class AddressGeocodingService {
  // geocoding 5.x부터 top-level 함수(geocoding.locationFromAddress(...))가 아니라
  // Geocoding 인스턴스 메서드로 API가 바뀜(4.x대 breaking change).
  static final Geocoding _geocoder = Geocoding();

  /// 입력한 주소를 실제 지오코딩(iOS: CLGeocoder / Android: 네이티브 Geocoder)으로
  /// 검증하고 위경도 좌표를 얻는다. 좌표를 다시 역지오코딩해서 얻은 행정구역/도로명
  /// 구성요소로 정돈된 주소 문자열도 함께 만들어 "도로명 주소 변환 제안"에 쓴다.
  /// 웹처럼 geocoding 플랫폼 구현체가 없거나, 주소를 못 찾거나, 기기에 네트워크가
  /// 없는 등 실패 상황에서는 예외를 그대로 던지지 않고 실패 결과를 반환해서 호출
  /// 쪽이 "위치를 찾을 수 없는 주소" 안내를 보여줄 수 있게 한다.
  static Future<AddressValidationResult> validateAndConvert(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return const AddressValidationResult(
        isValid: false,
        originalAddress: '',
        message: '주소가 입력되지 않았습니다.',
      );
    }

    try {
      final locations = await _geocoder.locationFromAddress(trimmed);
      if (locations.isEmpty) {
        return AddressValidationResult(
          isValid: false,
          originalAddress: trimmed,
          message: '위치를 찾을 수 없는 주소입니다. 건물명이나 도로명 주소를 확인해 주세요.',
        );
      }

      final location = locations.first;
      final geoPosition = GeoPosition(lat: location.latitude, lng: location.longitude);
      final roadNameAddress = await _reverseGeocodeToRoadName(location);

      return AddressValidationResult(
        isValid: true,
        originalAddress: trimmed,
        roadNameAddress: roadNameAddress,
        geoPosition: geoPosition,
        message: '주소 위치를 확인했습니다.',
      );
    } catch (_) {
      return AddressValidationResult(
        isValid: false,
        originalAddress: trimmed,
        message: '위치를 찾을 수 없는 주소입니다. 건물명이나 도로명 주소를 확인해 주세요.',
      );
    }
  }

  static Future<String?> _reverseGeocodeToRoadName(Location location) async {
    try {
      final placemarks = await _geocoder.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;
      final parts = [
        p.administrativeArea,
        p.subAdministrativeArea,
        p.thoroughfare,
        p.subThoroughfare,
      ].where((s) => s != null && s.trim().isNotEmpty).toList();

      if (parts.isEmpty) return null;
      return parts.join(' ');
    } catch (_) {
      // 역지오코딩 실패는 치명적이지 않음 — 정방향 지오코딩으로 얻은 좌표는
      // 이미 유효하므로 원본 주소를 그대로 쓰면 된다.
      return null;
    }
  }
}
