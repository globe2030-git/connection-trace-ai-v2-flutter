/// 행정안전부 주소 API(business.juso.go.kr)를 실제로 호출하는 통신 층.
///
/// 판정 규칙(어느 후보를 쓸지·UTM-K 변환)은 [juso_geocoding.dart]에 이미
/// 실측으로 고정돼 있다 — 여기서는 그 함수들에 응답 문자열을 넘기는 것과
/// HTTP 요청을 만드는 것만 한다. 그래야 통신 없이도 판정 규칙을 테스트로
/// 잠글 수 있다(그 테스트는 이미 있다, `test/juso_geocoding_test.dart`).
///
/// ## 키가 두 개다 — 검색 키 ≠ 좌표 키
///
/// `addrLinkApi.do`(주소 검색)와 `addrCoordApi.do`(좌표 조회)는 **따로
/// 신청·발급받는 키**를 쓴다. 하나만 있으면 절반만 되는 게 아니라 아예 안
/// 된다 — 검색이 되어도 좌표를 못 얻으면 지오코딩 결과가 없는 것과 같다.
/// 그래서 [isConfigured]는 **둘 다** 있어야 true다.
///
/// ## 왜 예외를 던지지 않나
///
/// 이 서비스는 [AddressGeocodingService.validateAndConvert]의 "1차 시도"로
/// 붙는다. 여기서 던지면 폴백(OS 지오코더)으로 못 넘어가고 등록 흐름 전체가
/// 멈춘다. 그래서 키가 없거나 통신이 실패하거나 응답이 이상해도 전부
/// `null`로 조용히 돌려준다 — "안 되면 다음 수단"이 이 서비스의 계약이다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/geo_utils.dart';
import 'juso_geocoding.dart';

class JusoGeocodingService {
  static const _timeout = Duration(seconds: 8);

  static const String _searchUrl =
      'https://business.juso.go.kr/addrlink/addrLinkApi.do';
  static const String _coordUrl =
      'https://business.juso.go.kr/addrlink/addrCoordApi.do';

  // `--dart-define=JUSO_SEARCH_KEY=...`/`JUSO_COORD_KEY=...`로 빌드 시점에
  // 넣는다(KAKAO_JS_KEY와 같은 패턴). 둘 다 안 넣으면 빈 문자열 — 그러면
  // isConfigured가 false가 되어 이 서비스는 조용히 비켜선다.
  static const String _envSearchKey = String.fromEnvironment(
    'JUSO_SEARCH_KEY',
  );
  static const String _envCoordKey = String.fromEnvironment('JUSO_COORD_KEY');

  final String _searchKey;
  final String _coordKey;

  /// 실제 통신 없이 검증할 수 있도록 주입 가능하게 열어 둔다
  /// (`GeoBackfillService`가 지오코딩 함수를 주입하는 것과 같은 패턴).
  final Future<http.Response> Function(Uri uri) _get;

  JusoGeocodingService({
    String? searchKey,
    String? coordKey,
    Future<http.Response> Function(Uri uri)? get,
  }) : _searchKey = searchKey ?? _envSearchKey,
       _coordKey = coordKey ?? _envCoordKey,
       _get = get ?? http.get;

  /// 검색 키·좌표 키가 **둘 다** 있어야 쓸 수 있다.
  bool get isConfigured => _searchKey.isNotEmpty && _coordKey.isNotEmpty;

  /// 주소 문자열 → 좌표. 키가 없거나, 검색 결과가 없거나, 좌표를 못 얻으면
  /// `null`(예외를 던지지 않는다 — 위 문서 참고).
  Future<GeoPosition?> geocode(String address) async {
    if (!isConfigured) return null;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;

    try {
      final candidates = await _search(trimmed);
      final best = pickBest(candidates);
      if (best == null) return null;
      return await _coord(best);
    } catch (e) {
      // 개인정보(주소 원문)는 남기지 않는다 — 실패 유형만.
      debugPrint('행안부 지오코딩 실패: ${e.runtimeType}');
      return null;
    }
  }

  Future<List<JusoCandidate>> _search(String keyword) async {
    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {
        'confmKey': _searchKey,
        'keyword': keyword,
        'resultType': 'json',
        'currentPage': '1',
        'countPerPage': '10',
      },
    );
    final response = await _get(uri).timeout(_timeout);
    if (response.statusCode != 200) return const [];
    return parseSearchResponse(response.body);
  }

  Future<GeoPosition?> _coord(JusoCandidate candidate) async {
    final uri = Uri.parse(_coordUrl).replace(
      queryParameters: {
        'confmKey': _coordKey,
        'resultType': 'json',
        'admCd': candidate.admCd,
        'rnMgtSn': candidate.rnMgtSn,
        'udrtYn': candidate.udrtYn,
        'buldMnnm': candidate.buldMnnm,
        'buldSlno': candidate.buldSlno,
      },
    );
    final response = await _get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;
    return parseCoordResponse(response.body);
  }
}
