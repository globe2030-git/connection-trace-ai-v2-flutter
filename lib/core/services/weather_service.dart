import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/geo_utils.dart';

/// Open-Meteo(https://open-meteo.com/) 무료 날씨 API로 오늘 날씨를 조회한다.
/// API 키가 필요 없고 위경도만 넘기면 되어, AI 대화 브리핑 프롬프트에
/// "오늘 상대방 지역 날씨"를 자연스럽게 곁들이는 용도로 쓴다.
///
/// 날씨는 브리핑을 더 자연스럽게 만들어 주는 "있으면 좋은" 부가 정보일
/// 뿐이라, 상대방 주소가 지오코딩되지 않았거나(geo == null) API 호출이
/// 실패해도 예외를 던지지 않고 조용히 null을 반환한다 — 날씨 조회 실패가
/// AI 브리핑 생성 전체를 막아서는 안 된다.
class WeatherService {
  static const _timeout = Duration(seconds: 8);

  static Future<String?> getTodayWeatherSummary(GeoPosition? geo) async {
    if (geo == null) return null;
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${geo.lat}&longitude=${geo.lng}'
        '&current=temperature_2m,weather_code&timezone=Asia/Seoul',
      );
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      final temp = (current['temperature_2m'] as num?)?.round();
      final code = (current['weather_code'] as num?)?.toInt();
      if (temp == null || code == null) return null;

      return '${describeWeatherCode(code)}, $temp°C';
    } catch (_) {
      // 네트워크 오류, 타임아웃, 파싱 오류 등 무엇이든 조용히 스킵.
      return null;
    }
  }

  /// Open-Meteo가 쓰는 WMO Weather interpretation code를 한국어 날씨
  /// 설명으로 변환한다. (https://open-meteo.com/en/docs 코드표 기준)
  static String describeWeatherCode(int code) {
    if (code == 0) return '맑음';
    if (code == 1 || code == 2) return '대체로 맑음';
    if (code == 3) return '흐림';
    if (code == 45 || code == 48) return '안개';
    if (code >= 51 && code <= 57) return '이슬비';
    if (code >= 61 && code <= 67) return '비';
    if (code >= 71 && code <= 77) return '눈';
    if (code >= 80 && code <= 82) return '소나기';
    if (code == 85 || code == 86) return '눈 소나기';
    if (code >= 95 && code <= 99) return '뇌우';
    return '흐림';
  }
}
