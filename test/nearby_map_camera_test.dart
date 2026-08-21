import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// 실측 좌표(2026-08-22, 폴드). 사용자는 용인 부근에 있었고 인맥은 서울에
/// 몰려 있었으며, 광주에 한 명이 있었다.
final me = LatLng(37.2411, 127.1776); // 용인 부근
final seoulA = LatLng(37.5045, 127.0490); // 강남 부근
final seoulB = LatLng(37.5445, 127.0560); // 성동 부근
final gwangju = LatLng(35.1595, 126.8526); // 광주 — 230.3km

/// 화면에서 읽은 거리들(km). **전부는 아니고 캡처에서 읽힌 것**이다.
/// 꼬리가 38.3 · 38.3 · 45.8이고 그다음이 230.3으로 크게 뛴다 — 여기가
/// 이상값을 가르는 자리다.
const observedKm = <double>[
  6.7, 12.0, 20.4, 25.3, 28.3, 28.8, 29.1, 29.3, 32.2, 33.4,
  34.7, 35.3, 37.1, 37.4, 37.4, 37.9, 38.3, 38.3, 45.8, 230.3,
];

List<({LatLng point, double distanceMeters})> contactsFrom(
  List<double> km, {
  LatLng? farthest,
}) {
  return [
    for (var i = 0; i < km.length; i++)
      (
        point: i == km.length - 1 && farthest != null
            ? farthest
            : (i.isEven ? seoulA : seoulB),
        distanceMeters: km[i] * 1000,
      ),
  ];
}

void main() {
  group('resolveMapFit — 맞춤을 쓸지 말지', () {
    test('반경이 유한하면 맞춤을 쓰지 않는다 — 반경 원이 이미 척도다', () {
      final plan = resolveMapFit(
        radiusMeters: 3000,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(const [1.0]),
      );
      expect(plan.usesFit, isFalse);
      expect(plan.outsideCount, 0);
    });

    test('반경이 "전체"라도 그릴 인맥이 없으면 맞춤을 쓰지 않는다', () {
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: const [],
      );
      expect(plan.usesFit, isFalse);
    });
  });

  group('resolveMapFit — 이상값', () {
    test('실측 분포에서 230.3km 하나만 빠지고 45.8km는 남는다', () {
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(observedKm, farthest: gwangju),
      );

      expect(plan.outsideCount, 1, reason: '광주 한 명만 첫 화면 밖');
      expect(plan.coordinates, isNotNull);
      // 광주가 빠졌으니 담긴 좌표에 광주는 없다.
      expect(plan.coordinates, isNot(contains(gwangju)));
      // 내 위치와 기준점은 언제나 담는다.
      expect(plan.coordinates, contains(me));
    });

    test('45.8km가 잘리지 않는 것이 핵심이다 — 문턱이 그보다 커야 한다', () {
      final threshold = bulkThresholdMeters(
        [for (final km in observedKm) km * 1000],
      );
      expect(threshold, greaterThan(45.8 * 1000));
      expect(threshold, lessThan(230.3 * 1000));
    });

    test('뭉쳐 있으면 아무도 빼지 않는다', () {
      final tight = observedKm.sublist(0, observedKm.length - 1); // 230.3 제외
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(tight),
      );
      expect(plan.outsideCount, 0);
    });

    test('전체 보기를 고르면 이상값까지 담는다', () {
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(observedKm, farthest: gwangju),
        includeAll: true,
      );
      expect(plan.outsideCount, 0);
      expect(plan.coordinates, contains(gwangju));
    });

    test('인맥이 하나뿐이면 그 하나는 반드시 담는다', () {
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(const [230.3], farthest: gwangju),
      );
      expect(plan.outsideCount, 0);
      expect(plan.coordinates, contains(gwangju));
    });

    test('전부 같은 자리(거리 0)여도 빈 화면이 되지 않는다', () {
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: me,
        myPoint: me,
        contactsNearestFirst: contactsFrom(const [0, 0, 0]),
      );
      expect(plan.outsideCount, 0);
      expect(plan.coordinates!.length, greaterThan(2));
    });

    test('기준점이 내 위치와 다르면(F-13) 둘 다 담는다', () {
      final anchor = LatLng(37.3800, 127.1200);
      final plan = resolveMapFit(
        radiusMeters: double.infinity,
        center: anchor,
        myPoint: me,
        contactsNearestFirst: contactsFrom(const [10.0]),
      );
      expect(plan.coordinates, containsAll(<LatLng>[anchor, me]));
    });
  });
}
