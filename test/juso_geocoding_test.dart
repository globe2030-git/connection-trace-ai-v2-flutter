import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/juso_geocoding.dart';

/// 행안부 주소 API 해석·판정 테스트.
///
/// ⚠️ 이 앱은 좌표를 **저장**한다. 카카오·브이월드는 결과 저장을 금지하므로
/// 행안부로 간다 — 성능이 아니라 **약관** 때문이다.
///
/// 📌 2026-08-21 실측(같은 명함 표본): 기기 지오코더 32.3% · 행안부 82.2%.
void main() {
  String searchBody({required String errorCode, List<Map<String, String>> juso = const []}) =>
      jsonEncode({
        'results': {
          'common': {'errorCode': errorCode, 'errorMessage': ''},
          'juso': juso,
        },
      });

  Map<String, String> item(String road, {String bul = '1'}) => {
        'roadAddr': road,
        'jibunAddr': '지번 $road',
        'admCd': '1168010100',
        'rnMgtSn': '116804166044',
        'udrtYn': '0',
        'buldMnnm': bul,
        'buldSlno': '0',
      };

  group('검색 응답 해석', () {
    test('정상 응답에서 후보를 뽑는다', () {
      final list = parseSearchResponse(
        searchBody(errorCode: '0', juso: [item('서울특별시 강남구 테헤란로 1')]),
      );
      expect(list, hasLength(1));
      expect(list.single.roadAddress, '서울특별시 강남구 테헤란로 1');
      expect(list.single.admCd, '1168010100');
    });

    test('⚠️ errorCode 를 먼저 본다 — HTTP 200 이어도 본문에 오류가 온다', () {
      // 카카오·네이버 토큰 응답에서 겪은 것과 같은 유형이다.
      final list = parseSearchResponse(
        searchBody(errorCode: 'E0005', juso: [item('서울특별시 강남구 테헤란로 1')]),
      );
      expect(list, isEmpty, reason: '오류인데 결과를 쓰면 엉뚱한 좌표가 저장된다');
    });

    test('⚠️ 좌표 조회에 필요한 코드가 없는 후보는 버린다', () {
      // 코드가 없으면 다음 단계에서 어차피 좌표를 못 얻는다.
      final broken = item('서울특별시 강남구 테헤란로 1')..['admCd'] = '';
      expect(parseSearchResponse(searchBody(errorCode: '0', juso: [broken])), isEmpty);
    });

    test('⚠️ 깨진 JSON·빈 응답에도 예외를 던지지 않는다', () {
      // 여기서 던지면 명함 저장 흐름이 통째로 멈춘다.
      expect(parseSearchResponse('<html>error</html>'), isEmpty);
      expect(parseSearchResponse(''), isEmpty);
      expect(parseSearchResponse('{}'), isEmpty);
    });
  });

  group('⭐ 어느 결과를 쓸지 — 규칙은 실측으로 정했다', () {
    test('첫 결과를 쓴다', () {
      // 90건 대조에서 규칙별 적중률:
      //   무조건 1순위 82.2% · 결과 1건일 때만 63.3% · 도로명 대조 42.2%
      // 가장 단순한 것이 가장 좋았다.
      final list = parseSearchResponse(searchBody(errorCode: '0', juso: [
        item('서울특별시 강남구 테헤란로 1'),
        item('서울특별시 강남구 테헤란로 2'),
      ]));
      expect(pickBest(list)!.roadAddress, endsWith('테헤란로 1'));
    });

    test('⚠️ 결과가 여러 개여도 포기하지 않는다', () {
      // "결과가 1건일 때만 쓴다"로 두면 63.3%로 떨어진다 —
      // 포기한 만큼 그 명함이 지도에서 사라진다.
      final list = parseSearchResponse(searchBody(errorCode: '0', juso: [
        item('서울특별시 강남구 테헤란로 1'),
        item('서울특별시 강남구 테헤란로 2'),
        item('서울특별시 강남구 테헤란로 3'),
      ]));
      expect(pickBest(list), isNotNull);
    });

    test('결과가 없으면 고르지 않는다', () {
      expect(pickBest(const []), isNull);
    });
  });

  group('좌표 응답 해석', () {
    String coordBody(String x, String y, {String errorCode = '0'}) => jsonEncode({
          'results': {
            'common': {'errorCode': errorCode},
            'juso': [
              {'entX': x, 'entY': y},
            ],
          },
        });

    test('⭐ UTM-K 를 위경도로 바꾼다 — 그대로 쓰면 한국이 아니다', () {
      // 행안부가 주는 것은 위경도가 아니라 EPSG:5179 다.
      final p = parseCoordResponse(coordBody('958869.634', '1953711.348'));
      expect(p, isNotNull);
      expect(p!.lat, closeTo(37.5, 0.5), reason: '서울 근처여야 한다');
      expect(p.lng, closeTo(127.0, 0.5));
    });

    test('⚠️ 0,0 은 "못 찾음"이다 — 그대로 쓰면 아프리카 서쪽 바다다', () {
      expect(parseCoordResponse(coordBody('0', '0')), isNull);
    });

    test('오류 응답이면 좌표를 만들지 않는다', () {
      expect(parseCoordResponse(coordBody('958869', '1953711', errorCode: 'E0005')), isNull);
    });

    test('⚠️ 숫자가 아닌 값·빈 응답에도 예외를 던지지 않는다', () {
      expect(parseCoordResponse(coordBody('', '')), isNull);
      expect(parseCoordResponse('{"results":{"common":{"errorCode":"0"},"juso":[]}}'), isNull);
      expect(parseCoordResponse('깨진 값'), isNull);
    });
  });
}
