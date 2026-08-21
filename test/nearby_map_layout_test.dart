import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// 주변 홈 지도 카드(⑥-C)의 "거리·방위 → 화면 좌표" 순수 계산만 검사한다.
/// 실제로 원을 그리는 일은 `nearby_map_card.dart`가 하므로 여기서는 위젯을
/// 전혀 띄우지 않는다 — 좌표 계산이 맞는지는 화면 없이도 확인할 수 있다.
void main() {
  const origin = GeoPosition(lat: 0, lng: 0);

  ContactModel contactAt(
    String id,
    String name,
    GeoPosition geo, {
    String? address,
  }) => ContactModel(
    id: id,
    name: name,
    company: '',
    title: '',
    phone: '',
    email: '',
    address: address,
    tags: const [],
    talkingPoints: const [],
    geo: geo,
  );

  group('GeoUtils.getBearingDegrees', () {
    test('정북은 0도', () {
      expect(
        GeoUtils.getBearingDegrees(origin, const GeoPosition(lat: 1, lng: 0)),
        closeTo(0, 0.01),
      );
    });

    test('정동은 90도', () {
      expect(
        GeoUtils.getBearingDegrees(origin, const GeoPosition(lat: 0, lng: 1)),
        closeTo(90, 0.01),
      );
    });

    test('정남은 180도', () {
      expect(
        GeoUtils.getBearingDegrees(
          origin,
          const GeoPosition(lat: -1, lng: 0),
        ),
        closeTo(180, 0.01),
      );
    });

    test('정서는 270도', () {
      expect(
        GeoUtils.getBearingDegrees(
          origin,
          const GeoPosition(lat: 0, lng: -1),
        ),
        closeTo(270, 0.01),
      );
    });
  });

  group('computeNearbyMapDots — 좌표 매핑', () {
    test('⭐ 정북·반경 절반 거리 = 카드 중심 기준 (0, -0.5) 근방', () {
      // 위도 1도 ≈ 111km. 반경을 111km로 두면 위도 0.5도 거리는 fraction 0.5.
      final c = contactAt('a', '김철수', const GeoPosition(lat: 0.5, lng: 0));
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [c],
        displayRadiusMeters: 111000,
      );
      expect(dots, hasLength(1));
      expect(dots.first.dx, closeTo(0, 0.02));
      expect(dots.first.dy, closeTo(-0.5, 0.02), reason: '북쪽은 화면 위쪽(음수)');
    });

    test('⭐ 정동은 화면 오른쪽(양수 dx), 세로 이동 없음', () {
      final c = contactAt('a', '박영희', const GeoPosition(lat: 0, lng: 1));
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [c],
        displayRadiusMeters: 200000, // 충분히 넉넉한 반경
      );
      expect(dots.first.dx, greaterThan(0));
      expect(dots.first.dy, closeTo(0, 0.02));
    });

    test('반경을 벗어나는 사람은 링 가장자리(fraction 1)에 붙는다', () {
      final c = contactAt('a', '먼사람', const GeoPosition(lat: 5, lng: 0));
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [c],
        displayRadiusMeters: 1000, // 실제 거리(약 555km)보다 훨씬 작다
      );
      final r = dots.first.dx * dots.first.dx + dots.first.dy * dots.first.dy;
      expect(r, closeTo(1, 0.01), reason: 'dx²+dy²=1이면 정확히 가장자리');
    });
  });

  group('computeNearbyMapDots — 이니셜·같은 주소 묶음(F-15)', () {
    test('낱개는 이름 첫 글자를 라벨로 쓴다', () {
      final c = contactAt('a', '김철수', const GeoPosition(lat: 0.1, lng: 0));
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [c],
        displayRadiusMeters: 50000,
      );
      expect(dots.first.label, '김');
      expect(dots.first.isBadge, isFalse);
      expect(dots.first.count, 1);
    });

    test('⭐ 같은 주소 2명은 숫자 배지 하나로 묶인다 — F-15와 같은 규칙', () {
      final a = contactAt(
        'a',
        '김철수',
        const GeoPosition(lat: 0.1, lng: 0),
        address: '서울시 강남구 테헤란로 1',
      );
      final b = contactAt(
        'b',
        '이영희',
        const GeoPosition(lat: 0.1, lng: 0),
        address: '서울시 강남구 테헤란로 1',
      );
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [a, b],
        displayRadiusMeters: 50000,
      );
      expect(dots, hasLength(1), reason: '같은 주소는 점 하나로 묶인다');
      expect(dots.first.isBadge, isTrue);
      expect(dots.first.label, '2');
      expect(dots.first.count, 2);
    });

    test('주소가 없으면 서로 묶이지 않는다', () {
      final a = contactAt('a', '김철수', const GeoPosition(lat: 0.1, lng: 0));
      final b = contactAt('b', '이영희', const GeoPosition(lat: 0.1, lng: 0));
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: [a, b],
        displayRadiusMeters: 50000,
      );
      expect(dots, hasLength(2));
    });
  });

  group('computeNearbyMapDots — 표시 상한 초과 시 묶음(브리프 ⑥-C 3항)', () {
    test('상한을 넘기면 가까운 (maxDots-1)개는 낱개, 나머지는 "+N" 하나로', () {
      // 서로 다른 방위(동쪽으로 조금씩 벌려서)에 8명, 주소는 전부 다르다.
      final contacts = List.generate(
        8,
        (i) => contactAt(
          'c$i',
          '인맥$i',
          GeoPosition(lat: 0.01 * (i + 1), lng: 0.01 * i),
        ),
      );
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: contacts,
        displayRadiusMeters: 50000,
        maxDots: 6,
      );
      expect(dots, hasLength(6), reason: '5개 낱개 + 뭉침 1개 = 6개');
      final singles = dots.where((d) => !d.isBadge);
      final overflow = dots.where((d) => d.isBadge);
      expect(singles, hasLength(5));
      expect(overflow, hasLength(1));
      expect(
        overflow.first.count,
        3,
        reason: '8명 중 5명을 낱개로 보여주면 나머지 3명이 뭉친다',
      );
      expect(overflow.first.label, '3');
    });

    test('상한 이하면 뭉치지 않는다', () {
      final contacts = List.generate(
        3,
        (i) => contactAt(
          'c$i',
          '인맥$i',
          GeoPosition(lat: 0.01 * (i + 1), lng: 0),
        ),
      );
      final dots = computeNearbyMapDots(
        origin: origin,
        contactsSortedByDistance: contacts,
        displayRadiusMeters: 50000,
        maxDots: 6,
      );
      expect(dots, hasLength(3));
      expect(dots.every((d) => !d.isBadge), isTrue);
    });
  });

  group('computeNearbyMapDots — 방어', () {
    test('반경이 0 이하이거나 무한대면 빈 목록', () {
      final c = contactAt('a', '김철수', const GeoPosition(lat: 0.1, lng: 0));
      expect(
        computeNearbyMapDots(
          origin: origin,
          contactsSortedByDistance: [c],
          displayRadiusMeters: 0,
        ),
        isEmpty,
      );
      expect(
        computeNearbyMapDots(
          origin: origin,
          contactsSortedByDistance: [c],
          displayRadiusMeters: double.infinity,
        ),
        isEmpty,
      );
    });

    test('인맥이 없으면 빈 목록', () {
      expect(
        computeNearbyMapDots(
          origin: origin,
          contactsSortedByDistance: const [],
          displayRadiusMeters: 1000,
        ),
        isEmpty,
      );
    });
  });

  group('resolveDisplayRadiusMeters', () {
    test('반경이 유한하면 그 값을 그대로 척도로 쓴다', () {
      expect(
        resolveDisplayRadiusMeters(
          selectedRadiusMeters: 1000,
          distancesMeters: [5000, 200],
        ),
        1000,
      );
    });

    test('"전체"(무제한)면 가장 먼 사람의 거리를 척도로 쓴다', () {
      expect(
        resolveDisplayRadiusMeters(
          selectedRadiusMeters: double.infinity,
          distancesMeters: [500, 3200, 900],
        ),
        3200,
      );
    });

    test('"전체"인데 인맥도 없으면 기본값으로 폴백한다', () {
      expect(
        resolveDisplayRadiusMeters(
          selectedRadiusMeters: double.infinity,
          distancesMeters: [],
          fallbackMeters: 1234,
        ),
        1234,
      );
    });
  });
}
