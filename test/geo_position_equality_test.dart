/// 좌표는 **값으로** 비교한다(2026-08-29, 추가 578).
///
/// ## 왜 이 검사가 있나
///
/// 🚨 `==`가 없으면 **값이 같아도 다른 객체면 다르다**고 나온다. 추가 572
/// (같은 명함 판정)에서 실제로 물릴 뻔했다 — **두 기기가 같은 주소를 각자
/// 계산한 흔한 경우**가 「좌표가 부딪힌다」로 읽혀 **영영 안 합쳐질 뻔했다.**
/// 기능이 막으려는 것과 **정반대로 도는 자리**였다.
///
/// 📌 그때는 부르는 쪽에서 `lat`·`lng`를 직접 비교해 피했다. 그런데 **다음
/// 사람이 그 사정을 모르고 `==`를 쓰면 같은 함정에 빠진다.**
library;

import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = GeoPosition(lat: 37.5, lng: 127.0);

  test('⭐ 값이 같으면 같다 — 다른 객체여도', () {
    expect(a == const GeoPosition(lat: 37.5, lng: 127.0), isTrue);
  });

  test('값이 다르면 다르다', () {
    expect(a == const GeoPosition(lat: 37.5, lng: 127.1), isFalse);
    expect(a == const GeoPosition(lat: 35.1, lng: 127.0), isFalse);
  });

  test('🚨 Set 에 넣으면 중복이 걸러진다 — 없으면 안 걸러졌다', () {
    // 값을 계산해서 넣는다 — 리터럴 둘을 나란히 두면 정적 검사가 먼저 잡아
    // 「같은 값을 두 번 넣었다」고 경고한다. 여기서 보려는 것은 **실행 결과**다.
    final b = GeoPosition(lat: double.parse('37.5'), lng: double.parse('127.0'));
    expect({a, b}.length, 1);
  });

  test('Map 키로 써도 같은 자리를 가리킨다', () {
    final m = <GeoPosition, String>{a: '서울'};
    expect(m[const GeoPosition(lat: 37.5, lng: 127.0)], '서울');
  });

  test('다른 타입과는 같지 않다', () {
    final Object other = '37.5,127.0';
    expect(a == other, isFalse);
  });
}
