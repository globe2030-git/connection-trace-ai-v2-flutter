/// 행정안전부 주소 API로 **주소를 좌표로** 바꾸는 순수 로직.
///
/// 통신은 하지 않는다 — 요청 주소를 만들고 응답을 해석하는 것까지만 한다.
/// 실제 호출은 [JusoGeocodingService]가 맡는다. 이렇게 갈라 두면 실기기나
/// 키 없이도 판정 규칙을 테스트로 고정할 수 있다.
///
/// ## 왜 행안부인가 — 성능이 아니라 **약관** 때문이다
///
/// ```
/// 카카오·브이월드   결과 저장 금지   ⚠️ 우리는 좌표를 저장한다 → 약관 위반
/// 행안부            "이용허락범위 제한 없음"
/// ```
///
/// 성능도 낫다(2026-08-21 실측, 같은 명함 표본).
///
/// ```
/// 기기 지오코더   30/93 = 32.3%
/// 행안부          74/90 = 82.2%   ⭐ 2.5배
/// ```
///
/// ## 두 번 부른다
///
/// ```
/// 1) addrLinkApi   주소 문자열 → 주소 목록(도로명·행정코드·건물번호)
/// 2) addrCoordApi  그 코드들 → 좌표(entX·entY, EPSG:5179 UTM-K)
/// 3) utm_k.dart    UTM-K → 위경도
/// ```
///
/// ⚠️ **검색 키와 좌표 키가 다르다.** 각각 따로 신청·발급받는다.
library;

import 'dart:convert';

import '../utils/geo_utils.dart';
import '../utils/utm_k.dart';

/// 검색 결과 한 건. 좌표를 얻는 데 필요한 것만 담는다.
class JusoCandidate {
  final String roadAddress;
  final String jibunAddress;

  /// 좌표 조회에 그대로 넘겨야 하는 값들.
  final String admCd;
  final String rnMgtSn;
  final String udrtYn;
  final String buldMnnm;
  final String buldSlno;

  const JusoCandidate({
    required this.roadAddress,
    required this.jibunAddress,
    required this.admCd,
    required this.rnMgtSn,
    required this.udrtYn,
    required this.buldMnnm,
    required this.buldSlno,
  });
}

/// 검색 응답을 해석한다. 실패해도 예외를 던지지 않고 빈 목록을 준다.
///
/// ⚠️ **errorCode를 먼저 본다.** HTTP 200이어도 본문에 오류가 담겨 온다 —
/// 카카오·네이버 토큰 응답에서 겪은 것과 같은 유형이다.
List<JusoCandidate> parseSearchResponse(String body) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return const [];
  }
  final results = json['results'] as Map<String, dynamic>?;
  if (results == null) return const [];
  final common = results['common'] as Map<String, dynamic>?;
  if (common?['errorCode'] != '0') return const [];
  final list = results['juso'];
  if (list is! List) return const [];

  return list.whereType<Map<String, dynamic>>().map((j) {
    String s(String k) => (j[k] ?? '').toString().trim();
    return JusoCandidate(
      roadAddress: s('roadAddr'),
      jibunAddress: s('jibunAddr'),
      admCd: s('admCd'),
      rnMgtSn: s('rnMgtSn'),
      udrtYn: s('udrtYn'),
      buldMnnm: s('buldMnnm'),
      buldSlno: s('buldSlno'),
    );
  }).where((c) => c.admCd.isNotEmpty && c.rnMgtSn.isNotEmpty).toList();
}

/// 검색 결과 중 **어느 것을 쓸지** 고른다.
///
/// ## ⚠️ 규칙은 실측으로 정했다 — 짐작이 아니다
///
/// 등록 명함 90건(정답 대조 가능분)으로 네 규칙을 비교했다(2026-08-21).
/// 정답 주소와 등록 주소를 **똑같이 API에 통과시켜** 비교했다 — 명함에
/// 도로명이 찍혔든 지번이 찍혔든 같은 형태가 되도록.
///
/// ```
/// 규칙                          맞음  오매칭  못고름   적중률
/// A 무조건 1순위                 74     2     14    82.2%  ⭐
/// B 결과가 1건일 때만             57     2     31    63.3%
/// C 입력 도로명+번호가 결과에 포함    38     0     52    42.2%
/// ```
///
/// ⭐ **가장 단순한 A가 가장 좋았다.** C는 오매칭이 0이지만 절반 넘게
/// 포기해서, 그만큼 명함이 지도에서 사라진다.
///
/// ⚠️ 그 전에 보고했던 67.7%·43.0%는 **API의 성능이 아니라 내가 만든 비교
/// 방식의 성능**이었다. 규칙을 고르기 전에 **재는 방법부터 맞춰야 했다.**
JusoCandidate? pickBest(List<JusoCandidate> candidates) {
  if (candidates.isEmpty) return null;
  return candidates.first;
}

/// 좌표 응답을 해석해 위경도로 바꾼다. 못 얻으면 `null`.
///
/// ⚠️ 행안부가 주는 것은 **위경도가 아니라 UTM-K(EPSG:5179)** 다. 그대로
/// 쓰면 한국 어디에도 없는 곳을 가리킨다 — 변환은 [utmKToWgs84]가 한다.
GeoPosition? parseCoordResponse(String body) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final results = json['results'] as Map<String, dynamic>?;
  if (results == null) return null;
  if ((results['common'] as Map<String, dynamic>?)?['errorCode'] != '0') {
    return null;
  }
  final list = results['juso'];
  if (list is! List || list.isEmpty) return null;
  final first = list.first;
  if (first is! Map<String, dynamic>) return null;

  final x = double.tryParse((first['entX'] ?? '').toString().trim());
  final y = double.tryParse((first['entY'] ?? '').toString().trim());
  if (x == null || y == null) return null;
  // ⚠️ 0,0 은 "못 찾음"을 뜻하는 값으로 실제로 온다. 그대로 쓰면 아프리카
  // 서쪽 바다를 가리킨다.
  if (x == 0 || y == 0) return null;
  return UtmK.toWgs84(x, y);
}
