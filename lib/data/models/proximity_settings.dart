/// 현재 실제로 동작하는 주변 인맥 필터 설정만 보관한다.
/// 백그라운드 알림이나 주기적 폴링처럼 아직 구현되지 않은 옵션은 포함하지 않는다.
class ProximitySettings {
  final double radiusMeters;

  // 확정된 설정 UI의 기본 감지 반경과 같이 1km로 시작한다.
  // 무제한으로 두면 멀리 있는 인맥도 근처 인맥으로 오인될 수 있다.
  const ProximitySettings({this.radiusMeters = 1000});

  ProximitySettings copyWith({double? radiusMeters}) {
    return ProximitySettings(radiusMeters: radiusMeters ?? this.radiusMeters);
  }
}
