// 주소 검색 웹뷰에서 **좌표를 함께 받는 것**(추가 348).
//
// ## 이 테스트가 지키는 두 가지
//
// **① 키가 없어도 주소 검색이 멀쩡해야 한다.**
// 좌표는 "있으면 좋은 것"이지 주소 선택의 조건이 아니다. 키 발급은 사용자가
// 직접 하는 작업이라 **없는 상태로 빌드되는 시기가 실제로 있다.**
//
// **② 엉뚱한 좌표는 없는 것보다 나쁘다.**
// 좌표가 틀리면 그 명함이 레이더의 **엉뚱한 자리**에 뜬다. 없으면 안 뜰 뿐이다.
// 특히 위도·경도가 뒤바뀌면 **화면에는 "좌표 있음"으로 보여서** 지도를 열기
// 전에는 티가 안 난다 — 그래서 범위 검사로 막는다.
import 'package:connection_trace_ai_flutter/presentation/common/address_search_view.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
<script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=__KAKAO_JS_KEY__&libraries=services&autoload=false"></script>
<div id="layer"></div>
''';

void main() {
  group('카카오 키 주입', () {
    test('키가 있으면 자리표시자가 실제 키로 바뀐다', () {
      final out = injectKakaoJsKey(_html, 'abc123');
      expect(out, contains('appkey=abc123'));
      expect(out, isNot(contains(kKakaoJsKeyToken)));
    });

    test('키에 특수문자가 있어도 URL로 안전하게 들어간다', () {
      final out = injectKakaoJsKey(_html, 'a b&c');
      expect(out, isNot(contains('a b&c')), reason: '그대로 넣으면 URL이 깨진다');
      expect(out, contains('appkey=a%20b%26c'));
    });

    group('⚠️ 키가 없을 때 — 여기가 제일 중요하다', () {
      test('SDK 스크립트 태그를 통째로 들어낸다', () {
        final out = injectKakaoJsKey(_html, '');
        expect(out, isNot(contains('dapi.kakao.com')));
        expect(
          out,
          isNot(contains(kKakaoJsKeyToken)),
          reason: '자리표시자를 남기면 카카오가 401을 돌려주고 콘솔이 시끄러워진다',
        );
      });

      test('우편번호 위젯은 **그대로 남는다** — 주소 검색이 망가지면 안 된다', () {
        final out = injectKakaoJsKey(_html, '');
        expect(out, contains('postcode.v2.js'));
        expect(out, contains('id="layer"'));
      });

      test('공백만 있는 키도 없는 것으로 본다', () {
        expect(injectKakaoJsKey(_html, '   '), isNot(contains('dapi.kakao.com')));
      });
    });

    test('초기 검색어 주입과 함께 써도 서로 안 건드린다', () {
      const both = "var Q = '__INITIAL_QUERY__';\n$_html";
      final out = injectKakaoJsKey(injectInitialQuery(both, '판교역로'), 'k1');
      expect(out, contains('appkey=k1'));
      expect(out, contains('"판교역로"'));
    });
  });

  group('좌표 결과 담기', () {
    test('좌표가 없으면 null이고 주소는 그대로다', () {
      const r = AddressSearchResult(address: '서울시 어디구 어디로 1');
      expect(r.geo, isNull);
      expect(r.address, '서울시 어디구 어디로 1');
    });
  });

  group('⚠️ 좌표 범위 검사 — 엉뚱한 좌표는 없는 것보다 나쁘다', () {
    test('서울 좌표는 통과한다', () {
      final g = parseGeoFromWebView(37.5665, 126.9780);
      expect(g, isNotNull);
      expect(g!.lat, closeTo(37.5665, 0.0001));
      expect(g.lng, closeTo(126.9780, 0.0001));
    });

    test('제주도 좌표도 통과한다 — 남단이 범위 밖으로 잘리면 안 된다', () {
      expect(parseGeoFromWebView(33.24, 126.56), isNotNull);
    });

    test('⭐ 위도·경도가 뒤바뀌면 걸러낸다', () {
      // 카카오는 x=경도, y=위도로 준다. 뒤집어 넣으면 위도 자리에 126이 온다.
      // **뒤집혀도 화면에는 "좌표 있음"으로 보여서** 지도를 열기 전엔 티가 안
      // 난다 — 그래서 여기서 막는다.
      expect(parseGeoFromWebView(126.9780, 37.5665), isNull);
    });

    test('대한민국 밖은 버린다', () {
      expect(parseGeoFromWebView(35.68, 139.76), isNull, reason: '도쿄');
      expect(parseGeoFromWebView(0, 0), isNull, reason: '적도 기니만 — 좌표 오류의 단골');
    });

    test('숫자가 아니거나 없으면 null', () {
      expect(parseGeoFromWebView(null, null), isNull);
      expect(parseGeoFromWebView('37.5', '127.0'), isNull, reason: '문자열은 안 받는다');
      expect(parseGeoFromWebView(37.5, null), isNull);
      expect(parseGeoFromWebView(double.nan, 127.0), isNull);
      expect(parseGeoFromWebView(double.infinity, 127.0), isNull);
    });
  });
}
