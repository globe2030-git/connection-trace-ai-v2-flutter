import 'package:geolocator/geolocator.dart';
import '../utils/geo_utils.dart';

enum DeviceLocationAccess {
  serviceDisabled,
  denied,
  deniedForever,
  granted,
  error,
}

abstract interface class LocationGateway {
  Future<DeviceLocationAccess> checkAccess();
  Future<DeviceLocationAccess> requestPermission();
  Future<GeoPosition?> getCurrentPosition();
  Future<bool> openAppPermissionSettings();
  Future<bool> openDeviceLocationSettings();
}

/// 실제 기기의 위치 서비스와 OS 권한을 다룬다.
///
/// 권한 확인과 권한 요청을 의도적으로 분리했다. 앱 자체 이용 동의를 받기 전에는
/// [requestPermission]을 호출하지 않으며, 위치를 얻지 못했을 때 가짜 좌표를
/// 반환하지 않는다.
class LocationService implements LocationGateway {
  @override
  Future<DeviceLocationAccess> checkAccess() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return DeviceLocationAccess.serviceDisabled;

      final permission = await Geolocator.checkPermission();
      return _mapPermission(permission);
    } catch (_) {
      return DeviceLocationAccess.error;
    }
  }

  @override
  Future<DeviceLocationAccess> requestPermission() async {
    try {
      final current = await checkAccess();
      if (current != DeviceLocationAccess.denied) return current;

      final permission = await Geolocator.requestPermission();
      return _mapPermission(permission);
    } catch (_) {
      return DeviceLocationAccess.error;
    }
  }

  @override
  Future<GeoPosition?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 회사 주소와의 근접 거리에는 중간 정확도로 충분하다. GPS를 최고
          // 정확도로 고정하지 않아 위치 조회 시간과 배터리 사용을 줄인다.
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
      return GeoPosition(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openAppPermissionSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openDeviceLocationSettings() =>
      Geolocator.openLocationSettings();

  DeviceLocationAccess _mapPermission(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.denied => DeviceLocationAccess.denied,
      LocationPermission.deniedForever => DeviceLocationAccess.deniedForever,
      LocationPermission.whileInUse ||
      LocationPermission.always => DeviceLocationAccess.granted,
      LocationPermission.unableToDetermine => DeviceLocationAccess.error,
    };
  }
}
