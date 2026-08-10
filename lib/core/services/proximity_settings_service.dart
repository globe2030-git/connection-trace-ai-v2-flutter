import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/proximity_settings.dart';

abstract interface class ProximitySettingsStore {
  Future<ProximitySettings> load();
  Future<void> saveRadius(double radiusMeters);
}

/// 감지 반경을 기기에 보관한다.
///
/// 예전에는 `RadarViewModel`이 반경을 메모리에만 들고 있어서, 앱을 다시 켜거나
/// 화면이 재생성되면 조용히 기본값(1km)으로 돌아갔다. 사용자가 "한번 선택하면
/// 계속 그 기준으로 보여야 하는데 자꾸 바뀐다"고 한 것이 이 증상이다(추가 139).
///
/// 반경은 개인정보가 아니라 단순 설정값이라 일반 `shared_preferences`에 둔다.
/// 위치 좌표나 인맥 정보는 여기에 절대 넣지 않는다.
class ProximitySettingsService implements ProximitySettingsStore {
  /// 미터 단위 정수로 저장한다. `double`로 저장하면 "제한 없음"을
  /// `double.infinity`로 넣어야 하는데, 플랫폼별 직렬화에서 값이 깨질 수 있다.
  /// 대신 [_unlimited]라는 약속된 정수를 쓴다.
  static const _radiusKey = 'proximity_radius_meters_v1';
  static const _unlimited = -1;

  @override
  Future<ProximitySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_radiusKey);
    if (stored == null) return const ProximitySettings();
    if (stored == _unlimited) {
      return const ProximitySettings(radiusMeters: double.infinity);
    }
    // 저장된 값이 선택지에 없는 값이어도 그대로 쓴다 — 선택지가 나중에 바뀌어도
    // 사용자가 고른 기준이 조용히 초기화되지 않게 하기 위함이다.
    return ProximitySettings(radiusMeters: stored.toDouble());
  }

  @override
  Future<void> saveRadius(double radiusMeters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _radiusKey,
      radiusMeters.isInfinite ? _unlimited : radiusMeters.round(),
    );
  }
}
