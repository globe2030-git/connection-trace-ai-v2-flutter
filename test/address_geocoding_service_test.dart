import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:connection_trace_ai_flutter/core/services/address_geocoding_service.dart';
import 'package:connection_trace_ai_flutter/core/services/juso_geocoding_service.dart';

http.Response _jsonResponse(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

/// [AddressGeocodingService.validateAndConvert]의 "행안부 먼저, 안 되면
/// OS 지오코더" 연결부 검증.
///
/// ⚠️ **키가 없을 때는 지금 동작과 완전히 같아야 한다** — 이것이 안전
/// 기본값이다(`KAKAO_JS_KEY`와 같은 패턴). 그래서 기본 상태(주입 없음)로도
/// 예외 없이 기존 경로(OS 지오코더)까지 도달하는지를 첫 번째로 확인한다.
void main() {
  final defaultJusoService = AddressGeocodingService.jusoService;

  tearDown(() {
    // 테스트마다 주입한 가짜 서비스를 되돌려 다른 테스트로 새지 않게 한다.
    AddressGeocodingService.jusoService = defaultJusoService;
  });

  String searchBody({
    required String errorCode,
    List<Map<String, String>> juso = const [],
  }) => jsonEncode({
    'results': {
      'common': {'errorCode': errorCode, 'errorMessage': ''},
      'juso': juso,
    },
  });

  Map<String, String> item(String road) => {
    'roadAddr': road,
    'jibunAddr': '지번 $road',
    'admCd': '1168010100',
    'rnMgtSn': '116804166044',
    'udrtYn': '0',
    'buldMnnm': '1',
    'buldSlno': '0',
  };

  String coordBody(String x, String y, {String errorCode = '0'}) =>
      jsonEncode({
        'results': {
          'common': {'errorCode': errorCode},
          'juso': [
            {'entX': x, 'entY': y},
          ],
        },
      });

  test('⚠️ 키가 없으면 (기본 상태) OS 지오코더 경로까지 예외 없이 넘어간다', () async {
    // 테스트 환경에는 geocoding 플랫폼 구현체가 없어 결과는 실패지만,
    // "행안부를 건너뛰고 기존 경로로 갔는지"가 핵심이다 — 여기서 던지면
    // 안전 기본값이 깨진 것이다.
    final result = await AddressGeocodingService.validateAndConvert(
      '서울특별시 강남구 테헤란로 1',
    );
    expect(result.isValid, isFalse);
  });

  test('행안부 키가 있고 성공하면 그 좌표를 쓰고 OS 지오코더를 부르지 않는다', () async {
    AddressGeocodingService.jusoService = JusoGeocodingService(
      searchKey: 's',
      coordKey: 'c',
      get: (uri) async {
        if (uri.path.contains('addrLinkApi')) {
          return _jsonResponse(
            searchBody(
              errorCode: '0',
              juso: [item('서울특별시 강남구 테헤란로 1')],
            ),
            200,
          );
        }
        return _jsonResponse(coordBody('958869.634', '1953711.348'), 200);
      },
    );

    final result = await AddressGeocodingService.validateAndConvert(
      '서울특별시 강남구 테헤란로 1',
    );

    // OS 지오코더였다면 플랫폼 구현체가 없어 예외로 실패했을 것 — 성공했다는
    // 것 자체가 행안부 경로로 처리됐다는 증거다.
    expect(result.isValid, isTrue);
    expect(result.geoPosition, isNotNull);
    expect(result.geoPosition!.lat, closeTo(37.5, 0.5));
    expect(result.originalAddress, '서울특별시 강남구 테헤란로 1');
  });

  test('행안부 1차 주소 실패 시 fallbackAddress로 재시도한다', () async {
    AddressGeocodingService.jusoService = JusoGeocodingService(
      searchKey: 's',
      coordKey: 'c',
      get: (uri) async {
        final keyword = uri.queryParameters['keyword'];
        if (uri.path.contains('addrLinkApi')) {
          if (keyword == '실패하는 도로명 주소') {
            return _jsonResponse(searchBody(errorCode: '0', juso: []), 200);
          }
          return _jsonResponse(
            searchBody(errorCode: '0', juso: [item('지번 주소 1')]),
            200,
          );
        }
        return _jsonResponse(coordBody('958869.634', '1953711.348'), 200);
      },
    );

    final result = await AddressGeocodingService.validateAndConvert(
      '실패하는 도로명 주소',
      fallbackAddress: '대체 지번 주소',
    );

    expect(result.isValid, isTrue);
    expect(
      result.originalAddress,
      '실패하는 도로명 주소',
      reason: '표시 주소는 1차(사용자가 입력한) 그대로 유지한다',
    );
  });

  test('행안부가 실패하면(키는 있지만 결과 없음) OS 지오코더 경로로 넘어간다', () async {
    AddressGeocodingService.jusoService = JusoGeocodingService(
      searchKey: 's',
      coordKey: 'c',
      get: (uri) async => _jsonResponse(searchBody(errorCode: '0'), 200),
    );

    final result = await AddressGeocodingService.validateAndConvert(
      '존재하지 않는 주소',
    );

    // OS 지오코더도 테스트 환경에서는 실패하지만, 예외 없이 최종 실패
    // 결과가 오는 것으로 "폴백이 실행됐다"를 확인한다.
    expect(result.isValid, isFalse);
  });
}
