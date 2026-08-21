import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// 실측에서 가져온 좌표. 사용자는 용인 근처에 있었고 인맥은 서울에 몰려 있어
/// 둘 사이가 약 30km였다 — 이 거리가 예전 배율(줌 12, 세로 약 18km)에 안
/// 들어가서 핀이 하나도 없는 지도가 열렸다.
final me = LatLng(37.2411, 127.1776); // 용인 부근
final seoulA = LatLng(37.5045, 127.0490); // 강남 부근
final seoulB = LatLng(37.5445, 127.0560); // 성동 부근

void main() {
  group('mapFitCoordinates', () {
    test('반경이 유한하면 맞춤을 쓰지 않는다 — 반경 원이 이미 척도다', () {
      final result = mapFitCoordinates(
        radiusMeters: 3000,
        center: me,
        myPoint: me,
        contactPoints: [seoulA],
      );
      expect(result, isNull);
    });

    test('반경이 "전체"라도 그릴 인맥이 없으면 맞춤을 쓰지 않는다', () {
      final result = mapFitCoordinates(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactPoints: const [],
      );
      expect(result, isNull);
    });

    test('반경이 "전체"면 내 위치와 인맥을 모두 담는다', () {
      final result = mapFitCoordinates(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactPoints: [seoulA, seoulB],
      );
      expect(result, isNotNull);
      expect(result, contains(me));
      expect(result, contains(seoulA));
      expect(result, contains(seoulB));
    });

    test('기준점이 내 위치와 다르면(F-13) 둘 다 담는다', () {
      final anchor = LatLng(37.3800, 127.1200);
      final result = mapFitCoordinates(
        radiusMeters: double.infinity,
        center: anchor,
        myPoint: me,
        contactPoints: [seoulA],
      );
      expect(result, containsAll(<LatLng>[anchor, me, seoulA]));
    });

    test('담을 좌표의 남북 폭이 실제 거리(약 30km)를 덮는다', () {
      final result = mapFitCoordinates(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactPoints: [seoulA, seoulB],
      )!;
      final lats = result.map((p) => p.latitude);
      final span = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(lats.reduce((a, b) => a < b ? a : b), me.longitude),
        LatLng(lats.reduce((a, b) => a > b ? a : b), me.longitude),
      );
      // 예전 줌 12가 담던 세로 범위가 약 18km였다 — 그보다 넓어야 한다.
      expect(span, greaterThan(18));
    });
  });
}
