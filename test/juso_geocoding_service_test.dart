import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:connection_trace_ai_flutter/core/services/juso_geocoding_service.dart';

/// [JusoGeocodingService]의 통신 층 검증. 실제 네트워크는 타지 않고 응답을
/// 주입해 검증한다 — HTTP 층을 함수 주입으로 열어 둔 이유가 이것이다.
///
/// 판정 규칙(어느 후보를 쓸지·UTM-K 변환) 자체는 이미
/// `test/juso_geocoding_test.dart`가 잠가 뒀으므로, 여기서는 "그 규칙에 응답을
/// 제대로 넘기는지"·"키·상태에 따라 조용히 비켜서는지"만 본다.
/// `http.Response(body, code)`는 content-type 헤더가 없으면 **latin1로
/// 인코딩**한다(package:http 기본값) — 한글이 섞인 본문을 그대로 넘기면
/// `ArgumentError`가 난다. 실제 서버 응답은 `application/json;charset=UTF-8`
/// 헤더를 주므로, 테스트 더미도 그 헤더를 맞춰 줘야 실제 통신과 같은 조건이 된다.
http.Response _jsonResponse(String body, int statusCode) => http.Response(
  body,
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
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

  group('isConfigured', () {
    test('검색 키·좌표 키가 둘 다 있어야 true', () {
      expect(
        JusoGeocodingService(
          searchKey: 's',
          coordKey: 'c',
        ).isConfigured,
        isTrue,
      );
      expect(
        JusoGeocodingService(searchKey: '', coordKey: 'c').isConfigured,
        isFalse,
      );
      expect(
        JusoGeocodingService(searchKey: 's', coordKey: '').isConfigured,
        isFalse,
      );
      expect(
        JusoGeocodingService(searchKey: '', coordKey: '').isConfigured,
        isFalse,
      );
    });
  });

  group('geocode', () {
    test('⚠️ 키가 없으면 통신 자체를 시도하지 않는다', () async {
      var called = false;
      final service = JusoGeocodingService(
        searchKey: '',
        coordKey: '',
        get: (uri) async {
          called = true;
          return http.Response('', 200);
        },
      );
      final result = await service.geocode('서울특별시 강남구 테헤란로 1');
      expect(result, isNull);
      expect(called, isFalse, reason: '키 없을 때는 조용히 비켜서야 한다');
    });

    test('정상 경로 — 검색 → 좌표 순으로 두 번 부르고 위경도를 만든다', () async {
      final calledUris = <Uri>[];
      final service = JusoGeocodingService(
        searchKey: 'search-key',
        coordKey: 'coord-key',
        get: (uri) async {
          calledUris.add(uri);
          if (uri.path.contains('addrLinkApi')) {
            return _jsonResponse(
              searchBody(
                errorCode: '0',
                juso: [item('서울특별시 강남구 테헤란로 1')],
              ),
              200,
            );
          }
          if (uri.path.contains('addrCoordApi')) {
            return _jsonResponse(
              coordBody('958869.634', '1953711.348'),
              200,
            );
          }
          throw StateError('예상하지 못한 요청: $uri');
        },
      );

      final geo = await service.geocode('서울특별시 강남구 테헤란로 1');

      expect(geo, isNotNull);
      expect(geo!.lat, closeTo(37.5, 0.5));
      expect(geo.lng, closeTo(127.0, 0.5));
      expect(calledUris, hasLength(2));
      expect(calledUris[0].queryParameters['confmKey'], 'search-key');
      expect(calledUris[0].queryParameters['keyword'], '서울특별시 강남구 테헤란로 1');
      expect(calledUris[1].queryParameters['confmKey'], 'coord-key');
      expect(calledUris[1].queryParameters['admCd'], '1168010100');
    });

    test('⚠️ errorCode≠0 이면 검색 단계에서 멈추고 좌표를 부르지 않는다', () async {
      var coordCalled = false;
      final service = JusoGeocodingService(
        searchKey: 's',
        coordKey: 'c',
        get: (uri) async {
          if (uri.path.contains('addrCoordApi')) coordCalled = true;
          return _jsonResponse(searchBody(errorCode: 'E0005'), 200);
        },
      );
      final geo = await service.geocode('아무 주소');
      expect(geo, isNull);
      expect(coordCalled, isFalse);
    });

    test('⚠️ 좌표가 0,0 이면 "못 찾음"으로 처리한다', () async {
      final service = JusoGeocodingService(
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
          return _jsonResponse(coordBody('0', '0'), 200);
        },
      );
      expect(await service.geocode('서울특별시 강남구 테헤란로 1'), isNull);
    });

    test('검색 결과가 없으면 좌표를 부르지 않는다', () async {
      var coordCalled = false;
      final service = JusoGeocodingService(
        searchKey: 's',
        coordKey: 'c',
        get: (uri) async {
          if (uri.path.contains('addrCoordApi')) coordCalled = true;
          return _jsonResponse(searchBody(errorCode: '0', juso: []), 200);
        },
      );
      expect(await service.geocode('존재하지 않는 주소'), isNull);
      expect(coordCalled, isFalse);
    });

    test('HTTP 상태코드가 200이 아니면 실패로 처리한다', () async {
      final service = JusoGeocodingService(
        searchKey: 's',
        coordKey: 'c',
        get: (uri) async => _jsonResponse('서버 오류', 500),
      );
      expect(await service.geocode('아무 주소'), isNull);
    });

    test('⚠️ 통신 예외를 던져도 밖으로 새지 않는다', () async {
      final service = JusoGeocodingService(
        searchKey: 's',
        coordKey: 'c',
        get: (uri) async => throw Exception('네트워크 없음'),
      );
      expect(await service.geocode('아무 주소'), isNull);
    });

    test('빈 주소는 통신 없이 바로 null', () async {
      var called = false;
      final service = JusoGeocodingService(
        searchKey: 's',
        coordKey: 'c',
        get: (uri) async {
          called = true;
          return http.Response('', 200);
        },
      );
      expect(await service.geocode('   '), isNull);
      expect(called, isFalse);
    });
  });
}
