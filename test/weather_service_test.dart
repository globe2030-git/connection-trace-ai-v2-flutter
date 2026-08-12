import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/weather_service.dart';

void main() {
  group('WeatherService.summarizeWeatherJson', () {
    test('현재기온 + 최고/최저기온이 모두 있으면 전체 포맷을 반환한다', () {
      final json = {
        'current': {'temperature_2m': 23.6, 'weather_code': 0},
        'daily': {
          'temperature_2m_max': [32.1],
          'temperature_2m_min': [22.9],
        },
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, '맑음, 현재 24°C (오늘 최고 32° · 최저 23°)');
    });

    test('daily가 없으면 현재기온만으로 degrade 된다', () {
      final json = {
        'current': {'temperature_2m': 24.0, 'weather_code': 0},
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, '맑음, 현재 24°C');
    });

    test('daily는 있지만 max/min 리스트가 비어있으면 degrade 된다', () {
      final json = {
        'current': {'temperature_2m': 24.0, 'weather_code': 3},
        'daily': {
          'temperature_2m_max': <num>[],
          'temperature_2m_min': <num>[],
        },
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, '흐림, 현재 24°C');
    });

    test('daily에 min만 없어도 degrade 된다(둘 다 있어야 표기)', () {
      final json = {
        'current': {'temperature_2m': 24.0, 'weather_code': 1},
        'daily': {
          'temperature_2m_max': [32.0],
        },
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, '대체로 맑음, 현재 24°C');
    });

    test('current가 없으면 전체가 null이다', () {
      final json = {
        'daily': {
          'temperature_2m_max': [32.0],
          'temperature_2m_min': [23.0],
        },
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, isNull);
    });

    test('current는 있지만 temperature_2m이 없으면 전체가 null이다', () {
      final json = {
        'current': {'weather_code': 0},
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, isNull);
    });

    test('current는 있지만 weather_code가 없으면 전체가 null이다', () {
      final json = {
        'current': {'temperature_2m': 24.0},
      };

      final summary = WeatherService.summarizeWeatherJson(json);

      expect(summary, isNull);
    });
  });

  group('WeatherService.buildWeatherSummary', () {
    test('최고/최저기온이 모두 있으면 괄호 표기를 포함한다', () {
      final summary = WeatherService.buildWeatherSummary(
        description: '맑음',
        currentTemp: 24,
        maxTemp: 32,
        minTemp: 23,
      );

      expect(summary, '맑음, 현재 24°C (오늘 최고 32° · 최저 23°)');
    });

    test('최고기온만 없으면 현재기온만 표기한다', () {
      final summary = WeatherService.buildWeatherSummary(
        description: '비',
        currentTemp: 18,
        maxTemp: null,
        minTemp: 15,
      );

      expect(summary, '비, 현재 18°C');
    });
  });
}
