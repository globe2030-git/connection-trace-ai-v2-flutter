import 'dart:math';

import 'geo_utils.dart';

/// UTM-K(EPSG:5179) 좌표를 위경도(WGS84, EPSG:4326)로 바꾼다.
///
/// ## 왜 필요한가
///
/// 행정안전부 좌표제공 API(`addrCoordApi.do`)는 `entX`·`entY`를 **UTM-K**로
/// 준다. 앱은 위경도만 쓰므로(`GeoPosition`, `flutter_map`) 여기서 맞춘다.
///
/// ⚠️ **변환하지 않고 그냥 넣으면 지구 반대편이 아니라 아예 좌표가 아니다.**
/// UTM-K 값은 백만 단위(예: 953752 / 1952032)라 위경도로 읽으면 범위를 한참
/// 벗어난다 — 다행히 `parseGeoFromWebView`의 범위 검사가 걸러 낸다. 그래서
/// 실수하면 "좌표가 안 붙는" 것으로 나타나지, 엉뚱한 자리에 찍히지는 않는다.
///
/// ## 왜 패키지를 안 쓰나
///
/// `proj4dart`를 넣으면 되지만, 우리가 필요한 것은 **투영 하나의 역변환**
/// 뿐이다. 좌표계 정의를 문자열로 싣고 파서를 도는 범용 패키지를 의존성에
/// 추가하는 것보다, 공식(Snyder, USGS Professional Paper 1395)을 그대로 옮기는
/// 편이 검증하기 쉽다 — 아래 테스트가 투영 원점을 못으로 박는다.
///
/// ## EPSG:5179 정의
///
/// ```
/// +proj=tmerc +lat_0=38 +lon_0=127.5 +k=0.9996
/// +x_0=1000000 +y_0=2000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0
/// ```
///
/// 📌 `towgs84`가 전부 0이라 **datum 변환이 없다.** GRS80과 WGS84는 장반경이
/// 같고 편평률이 소수점 아래 아홉째 자리에서 갈리므로, 역투영 결과를 그대로
/// WGS84로 써도 오차가 밀리미터 수준이다. 그래서 여기서는 역투영만 한다.
class UtmK {
  UtmK._();

  // GRS80 타원체.
  static const double _a = 6378137.0;
  static const double _f = 1.0 / 298.257222101;

  // EPSG:5179 투영 상수.
  static const double _lat0 = 38.0 * pi / 180.0;
  static const double _lon0 = 127.5 * pi / 180.0;
  static const double _k0 = 0.9996;
  static const double _x0 = 1000000.0;
  static const double _y0 = 2000000.0;

  static const double _e2 = _f * (2.0 - _f);

  /// 자오선 호장(赤道에서 [lat]까지). 역변환의 기준선을 잡는 데 쓴다.
  static double _meridionalArc(double lat) {
    const e4 = _e2 * _e2;
    const e6 = e4 * _e2;
    return _a *
        ((1 - _e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * lat -
            (3 * _e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * lat) +
            (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * lat) -
            (35 * e6 / 3072) * sin(6 * lat));
  }

  /// UTM-K [x](easting)·[y](northing) → 위경도.
  ///
  /// 입력이 유한하지 않으면 `null`. **범위 검사는 하지 않는다** — 부르는 쪽이
  /// 이미 `parseGeoFromWebView`로 대한민국 범위를 확인하므로, 검사를 두 군데
  /// 두면 기준이 갈라진다.
  static GeoPosition? toWgs84(double x, double y) {
    if (!x.isFinite || !y.isFinite) return null;

    final xp = x - _x0;
    final yp = y - _y0;

    final m = _meridionalArc(_lat0) + yp / _k0;

    const e4 = _e2 * _e2;
    const e6 = e4 * _e2;
    final mu = m / (_a * (1 - _e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256));

    final e1 = (1 - sqrt(1 - _e2)) / (1 + sqrt(1 - _e2));
    final e1p2 = e1 * e1;
    final e1p3 = e1p2 * e1;
    final e1p4 = e1p3 * e1;

    // 밑위도(footpoint latitude).
    final phi1 =
        mu +
        (3 * e1 / 2 - 27 * e1p3 / 32) * sin(2 * mu) +
        (21 * e1p2 / 16 - 55 * e1p4 / 32) * sin(4 * mu) +
        (151 * e1p3 / 96) * sin(6 * mu) +
        (1097 * e1p4 / 512) * sin(8 * mu);

    final ep2 = _e2 / (1 - _e2);
    final cosPhi1 = cos(phi1);
    final sinPhi1 = sin(phi1);
    final tanPhi1 = tan(phi1);

    final c1 = ep2 * cosPhi1 * cosPhi1;
    final t1 = tanPhi1 * tanPhi1;
    final denom = 1 - _e2 * sinPhi1 * sinPhi1;
    final n1 = _a / sqrt(denom);
    final r1 = _a * (1 - _e2) / (denom * sqrt(denom));
    final d = xp / (n1 * _k0);

    final d2 = d * d;
    final d3 = d2 * d;
    final d4 = d3 * d;
    final d5 = d4 * d;
    final d6 = d5 * d;

    final lat =
        phi1 -
        (n1 * tanPhi1 / r1) *
            (d2 / 2 -
                (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) * d4 / 24 +
                (61 +
                        90 * t1 +
                        298 * c1 +
                        45 * t1 * t1 -
                        252 * ep2 -
                        3 * c1 * c1) *
                    d6 /
                    720);

    final lon =
        _lon0 +
        (d -
                (1 + 2 * t1 + c1) * d3 / 6 +
                (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) *
                    d5 /
                    120) /
            cosPhi1;

    final latDeg = lat * 180.0 / pi;
    final lngDeg = lon * 180.0 / pi;
    if (!latDeg.isFinite || !lngDeg.isFinite) return null;
    return GeoPosition(lat: latDeg, lng: lngDeg);
  }

  /// 문자열로 오는 응답(`entX`·`entY`는 String 타입이다)을 그대로 받는다.
  ///
  /// 행안부 응답의 좌표 필드는 숫자가 아니라 **문자열**이다(가이드 출력표).
  /// 부르는 쪽마다 `double.tryParse`를 흩뿌리지 않도록 여기서 받는다.
  static GeoPosition? parse(Object? entX, Object? entY) {
    final x = entX is num ? entX.toDouble() : double.tryParse('${entX ?? ''}');
    final y = entY is num ? entY.toDouble() : double.tryParse('${entY ?? ''}');
    if (x == null || y == null) return null;
    return toWgs84(x, y);
  }
}
