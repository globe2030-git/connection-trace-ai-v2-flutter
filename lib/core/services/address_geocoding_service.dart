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

/// 주소 끝에 붙은 참고항목 괄호를 떼어낸다.
///
/// 예: "경기 성남시 분당구 판교역로 235 (삼평동, 에이치스퀘어)"
///  →  "경기 성남시 분당구 판교역로 235"
///
/// 표시·저장에는 괄호를 포함한 원본을 쓰고, 좌표 조회에만 이 결과를 쓴다.
String stripReferenceText(String address) {
  final stripped = address.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
  return stripped.isEmpty ? address.trim() : stripped;
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
  static Future<AddressValidationResult> validateAndConvert(
    String address,
  ) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return const AddressValidationResult(
        isValid: false,
        originalAddress: '',
        message: '주소가 입력되지 않았습니다.',
      );
    }

    try {
      // Android 네이티브 Geocoder는 백엔드 서비스가 응답을 안 주면 예외를
      // 던지지도 않고 Future가 영원히 안 끝나는 경우가 있다("주소 확인 중..."
      // 상태로 멈추는 문제로 실기기에서 확인됨) — 타임아웃을 걸어서 일정
      // 시간 안에 안 끝나면 실패로 처리한다.
      // 주소 끝의 참고항목 괄호는 떼고 조회한다. 우편번호 서비스에서 고른
      // 주소에는 "… 판교역로 235 (삼평동, 에이치스퀘어)"처럼 법정동·건물명이
      // 붙어 있는데(backlog 추가 83), OS 지오코더는 이 괄호가 붙으면 주소를
      // 못 찾는 경우가 있다. 저장되는 문자열은 괄호를 포함한 원본 그대로다 —
      // 여기서 떼는 것은 좌표 조회용 질의뿐이다.
      final query = stripReferenceText(trimmed);
      final locations = await _geocoder
          .locationFromAddress(query)
          .timeout(const Duration(seconds: 10));
      if (locations.isEmpty) {
        return AddressValidationResult(
          isValid: false,
          originalAddress: trimmed,
          message: '위치를 찾을 수 없는 주소입니다. 건물명이나 도로명 주소를 확인해 주세요.',
        );
      }

      final location = locations.first;
      final geoPosition = GeoPosition(
        lat: location.latitude,
        lng: location.longitude,
      );
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
      final placemarks = await _geocoder
          .placemarkFromCoordinates(location.latitude, location.longitude)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;

      // Android 네이티브 역지오코딩이 이 좌표에 대해 시/도(administrativeArea)
      // 만 돌려주고 도로명(thoroughfare)은 비워서 주는 경우가 실기기에서
      // 확인됐다(예: "경기도 성남시 분당구 대왕판교로644번길 49" 주소가
      // "경기도"로만 돌아옴 — 판교 한컴타워 주소, 2026-08-07). 도로명이
      // 없으면 "도로명 주소"라고 부를 수 없는데, 예전엔 이걸 그대로 받아들여
      // 멀쩡하던 원본 주소를 시/도 한 단어로 덮어써 버리는 심각한 데이터
      // 손실이 있었다. 도로명 자체가 없으면 변환 결과를 아예 버리고
      // null(변환 실패)로 처리해 원본 주소를 그대로 쓰게 한다.
      if (p.thoroughfare == null || p.thoroughfare!.trim().isEmpty) {
        return null;
      }

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
