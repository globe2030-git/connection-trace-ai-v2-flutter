import 'package:geolocator/geolocator.dart';
import '../utils/geo_utils.dart';
import '../utils/location_quality.dart';

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

  /// 직전 [getCurrentPosition]이 얻은 위치의 **품질**(E-12).
  ///
  /// 반환값을 바꾸지 않고 따로 둔 이유: `GeoPosition`은 좌표 계산 전반에 쓰여
  /// 거기에 품질을 얹으면 관계없는 코드가 다 바뀐다. **품질은 "직전 측위"의
  /// 성질이지 좌표의 성질이 아니다.**
  LocationFixQuality get lastFixQuality;
  Future<bool> openAppPermissionSettings();
  Future<bool> openDeviceLocationSettings();
}

/// 실제 기기의 위치 서비스와 OS 권한을 다룬다.
///
/// 권한 확인과 권한 요청을 의도적으로 분리했다. 앱 자체 이용 동의를 받기 전에는
/// [requestPermission]을 호출하지 않으며, 위치를 얻지 못했을 때 가짜 좌표를
/// 반환하지 않는다.
class LocationService implements LocationGateway {
  LocationFixQuality _lastFixQuality = LocationFixQuality.unknown;

  @override
  LocationFixQuality get lastFixQuality => _lastFixQuality;

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

  /// 새 위치를 기다리는 한도. 예전에는 6초였는데 **대부분 실패**했다
  /// (테스터 E-10, Galaxy S24+: "현재 위치를 확인하지 못했어요"가 거의 매번,
  /// 간헐적으로만 성공). `getCurrentPosition`은 캐시가 아니라 **새 측위**를
  /// 강제하므로 실내·콜드 스타트에서는 6초 안에 못 끝나는 일이 흔하다.
  static const Duration fixTimeout = Duration(seconds: 15);

  /// 새 측위에 실패했을 때 대신 쓸 수 있는 "마지막으로 알려진 위치"의 최대 나이.
  /// 무제한으로 받아들이면 한참 전 동네를 현재 위치로 삼아 거리 계산이 틀리므로
  /// (E-06 정확도 문제와 직결) 상한을 둔다. 이보다 오래되면 위치 없음으로 본다.
  static const Duration maxLastKnownAge = Duration(minutes: 10);

  /// 마지막으로 알려진 위치를 쓸 수 있는 나이인지. 순수 함수라 테스트로 고정한다.
  static bool isLastKnownUsable(DateTime timestamp, DateTime now) {
    final age = now.difference(timestamp);
    // 기기 시계가 흔들려 미래 시각이 찍히는 경우가 있어 음수도 막는다.
    if (age.isNegative) return false;
    return age <= maxLastKnownAge;
  }

  @override
  Future<GeoPosition?> getCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 회사 주소와의 근접 거리에는 중간 정확도로 충분하다. GPS를 최고
          // 정확도로 고정하지 않아 위치 조회 시간과 배터리 사용을 줄인다.
          accuracy: LocationAccuracy.medium,
          timeLimit: fixTimeout,
        ),
      );
      // 방금 잰 것이므로 나이는 없다. 오차는 OS가 준 값을 그대로 쓴다 —
      // 우리가 추정하지 않는다(E-12).
      _lastFixQuality = LocationFixQuality(accuracyMeters: position.accuracy);
      return GeoPosition(lat: position.latitude, lng: position.longitude);
    } catch (_) {
      // 새 측위가 실패(대개 시간 초과)해도 곧바로 포기하지 않는다 — OS가 들고
      // 있는 최근 위치가 있으면 그걸로 충분한 경우가 많다. 없거나 너무 오래된
      // 것뿐이면 그때 위치 없음(null)으로 돌려준다. 가짜 좌표는 만들지 않는다.
      return _recentLastKnownPosition();
    }
  }

  Future<GeoPosition?> _recentLastKnownPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        _lastFixQuality = LocationFixQuality.unknown;
        return null;
      }
      if (!isLastKnownUsable(last.timestamp, DateTime.now())) {
        _lastFixQuality = LocationFixQuality.unknown;
        return null;
      }
      // ⚠️ 여기가 E-12의 핵심이다 — **오래된 위치를 쓰고 있다는 사실**을
      // 여태 아무도 몰랐다. 나이를 남겨 화면이 말할 수 있게 한다.
      _lastFixQuality = LocationFixQuality(
        accuracyMeters: last.accuracy,
        age: DateTime.now().difference(last.timestamp),
      );
      return GeoPosition(lat: last.latitude, lng: last.longitude);
    } catch (_) {
      _lastFixQuality = LocationFixQuality.unknown;
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
