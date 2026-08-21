// UTM-K(EPSG:5179) → 위경도 변환(추가 360).
//
// ## 이 테스트가 무엇을 막나
//
// 좌표계 변환은 **틀려도 그럴듯한 숫자가 나온다.** 상수 하나를 잘못 넣어도
// 결과는 여전히 소수점 아래 여섯 자리의 위경도처럼 보인다. 그래서 눈으로는
// 검증이 안 되고, **못을 박아 두는 수밖에 없다.**
//
// 아래 세 가지가 못이다.
//   ① 투영 원점 — lat_0/lon_0/x_0/y_0 를 하나라도 틀리면 여기서 깨진다
//   ② 축척과 방향 — 1도 동쪽이 실제로 동쪽으로 88km쯤 가는지
//   ③ 국내 범위 — 서울 근방 값이 서울 근방으로 떨어지는지
//
// ⚠️ **실물 대조는 아직 못 했다.** 행안부 좌표제공 API 승인키가 나오면
// "서울특별시 중구 세종대로 110"의 entX/entY를 넣어 37.566/126.978 근처가
// 나오는지 확인해야 한다. 그때까지 이 테스트는 **자체 정합성만** 지킨다.
import 'package:connection_trace_ai_flutter/core/utils/utm_k.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('⭐ 투영 원점 — 상수를 틀리면 여기서 걸린다', () {
    test('x_0/y_0 자리는 정확히 lat_0/lon_0 이다', () {
      final g = UtmK.toWgs84(1000000, 2000000);
      expect(g, isNotNull);
      // EPSG:5179 정의: +lat_0=38 +lon_0=127.5 +x_0=1000000 +y_0=2000000
      expect(g!.lat, closeTo(38.0, 1e-7));
      expect(g.lng, closeTo(127.5, 1e-7));
    });

    test('원점보다 북쪽이면 위도가 커진다', () {
      final g = UtmK.toWgs84(1000000, 2100000);
      expect(g!.lat, greaterThan(38.0));
      expect(g.lng, closeTo(127.5, 1e-6), reason: '중앙자오선 위에서는 경도가 안 변한다');
    });

    test('원점보다 동쪽이면 경도가 커진다', () {
      final g = UtmK.toWgs84(1100000, 2000000);
      expect(g!.lng, greaterThan(127.5));
    });
  });

  group('축척 — 방향만 맞고 크기가 틀리는 경우를 막는다', () {
    test('북쪽으로 100km 가면 위도가 약 0.9도 오른다', () {
      final g = UtmK.toWgs84(1000000, 2100000);
      // 위도 1도 ≈ 111km. k0=0.9996 이므로 100km/0.9996 ≈ 100.04km ≈ 0.900도.
      expect(g!.lat - 38.0, closeTo(0.900, 0.005));
    });

    test('원점에서 동쪽 88km 는 경도 1도쯤이다', () {
      // 위도 38도에서 경도 1도 ≈ 87.8km.
      final g = UtmK.toWgs84(1000000 + 87800, 2000000);
      expect(g!.lng - 127.5, closeTo(1.0, 0.02));
    });
  });

  group('국내 범위 — 실제로 한국 안에 떨어지는가', () {
    test('서울 근방 UTM-K 값이 서울 근방으로 나온다', () {
      // 서울 도심은 UTM-K 대략 (953000, 1952000) 언저리다.
      final g = UtmK.toWgs84(953000, 1952000);
      expect(g, isNotNull);
      expect(g!.lat, inInclusiveRange(37.4, 37.7), reason: '서울 위도대');
      expect(g.lng, inInclusiveRange(126.8, 127.2), reason: '서울 경도대');
    });

    test('제주 근방도 한국 범위 안이다', () {
      final g = UtmK.toWgs84(915000, 1490000);
      expect(g!.lat, inInclusiveRange(33.0, 34.0));
      expect(g.lng, inInclusiveRange(126.0, 127.0));
    });

    test('⚠️ 변환 결과는 앱의 범위 검사를 통과하는 값이어야 한다', () {
      // parseGeoFromWebView 의 대한민국 범위(32~39.5, 124~132)와 같은 기준.
      final g = UtmK.toWgs84(953000, 1952000)!;
      expect(g.lat, inInclusiveRange(32.0, 39.5));
      expect(g.lng, inInclusiveRange(124.0, 132.0));
    });
  });

  group('입력 방어', () {
    test('유한하지 않은 값은 null', () {
      expect(UtmK.toWgs84(double.nan, 2000000), isNull);
      expect(UtmK.toWgs84(1000000, double.infinity), isNull);
    });

    test('문자열 좌표를 받는다 — 응답이 String 이다', () {
      final g = UtmK.parse('1000000', '2000000');
      expect(g!.lat, closeTo(38.0, 1e-7));
      expect(g.lng, closeTo(127.5, 1e-7));
    });

    test('소수점이 붙은 문자열도 받는다', () {
      expect(UtmK.parse('1000000.0', '2000000.0'), isNotNull);
    });

    test('숫자가 아니거나 없으면 null', () {
      expect(UtmK.parse(null, null), isNull);
      expect(UtmK.parse('', ''), isNull);
      expect(UtmK.parse('없음', '2000000'), isNull);
    });

    test('num 으로 와도 받는다', () {
      expect(UtmK.parse(1000000, 2000000), isNotNull);
    });
  });

  group('⚠️ 뒤집힌 입력 — x와 y를 바꿔 넣는 실수', () {
    test('서울 좌표를 뒤집어 넣으면 한국 밖으로 나간다', () {
      // 이 실수는 조용히 지나가면 안 된다. 범위 검사가 잡을 수 있어야 한다.
      final flipped = UtmK.toWgs84(1952000, 953000);
      final ok =
          flipped != null &&
          flipped.lat >= 32.0 &&
          flipped.lat <= 39.5 &&
          flipped.lng >= 124.0 &&
          flipped.lng <= 132.0;
      expect(ok, isFalse, reason: '뒤집힌 좌표가 범위 검사를 통과하면 엉뚱한 자리에 찍힌다');
    });
  });
}
