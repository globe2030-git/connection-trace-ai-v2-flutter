import 'dart:math';

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

  /// 원점에서 정북으로 [meters] 떨어진 좌표. 실측 분포 재현용 — 정확한
  /// haversine 대신 소각 근사(위도 1라디안 ≈ 지구 반지름)를 쓰지만, 오차는
  /// 미터 단위라 이 테스트가 쓰는 km 단위 허용오차 안에서 무시할 만하다.
  GeoPosition northOffset(double meters) {
    const earthRadiusM = 6371000.0;
    final latDeg = (meters / earthRadiusM) * 180 / pi;
    return GeoPosition(lat: latDeg, lng: 0);
  }

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

    test(
      '⭐ 뭉침 점은 뭉친 것 중 가장 먼 사람 자리를 쓴다(가장 가까운 자리가 아니라) — backlog 391',
      () {
        // 8명 중 가장 먼 c7이 overflow(5명 넘긴 나머지 3명: c5,c6,c7)에
        // 속한다. 옛 로직은 overflow 중 "가장 가까운" c5 자리를 썼는데,
        // 그러면 척도를 밀어올린 먼 인맥이 화면에서 숨는다.
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
        final overflow = dots.firstWhere((d) => d.isBadge);
        final farthestDistance = GeoUtils.getDistanceMeters(
          origin,
          contacts.last.geo, // c7 — 8명 중 가장 멀다
        );
        expect(
          overflow.distanceMeters,
          closeTo(farthestDistance, 1),
          reason: '뭉침 자리가 overflow 중 가장 먼 사람(c7) 위치를 써야 한다',
        );
      },
    );

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

    test('"전체"(무제한)·표본이 적으면 가장 먼 사람의 거리와 같아진다', () {
      // 표본 3개의 90번째 백분위수(최근접 순위)는 최댓값과 일치한다 —
      // 이상치 배제 효과는 표본이 많아야(아래 실측 분포 테스트) 드러난다.
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

    group('실측 분포(2026-08-22 릴리스, 폴드·아이폰 — backlog 391)', () {
      // 반경 "전체", 인맥 30명 — 29명은 28.3~36.8km 무리, 1명은 230.3km
      // 이상치. 결함(1): 옛 로직(최댓값)은 척도를 230.3km로 잡아 나머지
      // 29명이 척도의 12~16%(카드 중심 27px 반경 안, 점 자체 크기보다
      // 작은 영역)에 겹쳐 그려졌다.
      final clusterDistances = List<double>.generate(
        29,
        (i) => 28300.0 + i * 300.0, // 28,300m ~ 36,700m, 300m 간격
      );
      final outlierDistance = 230300.0;
      final allDistances = [...clusterDistances, outlierDistance];

      test('척도가 이상치(230.3km)에 안 끌려간다', () {
        final scale = resolveDisplayRadiusMeters(
          selectedRadiusMeters: double.infinity,
          distancesMeters: allDistances,
        );
        // 90번째 백분위수(최근접 순위, n=30) = 정렬된 30개 중 27번째
        // (0-index 26) = 무리의 clusterDistances[26] = 36,100m.
        expect(
          scale,
          closeTo(36100, 1),
          reason: '이상치를 빼고 무리 상단을 척도로 써야 한다',
        );
        expect(
          scale,
          lessThan(outlierDistance / 2),
          reason: '옛 로직처럼 이상치 근처 값이 나오면 실패 — 척도가 뺏긴 것',
        );
      });

      test(
        '⭐ 척도가 안 뺏기면 무리가 링 중심이 아니라 가장자리 쪽에 실제로 퍼진다',
        () {
          final contacts = [
            for (var i = 0; i < clusterDistances.length; i++)
              contactAt('c$i', '인맥$i', northOffset(clusterDistances[i])),
            contactAt('outlier', '먼사람', northOffset(outlierDistance)),
          ];
          final displayRadius = resolveDisplayRadiusMeters(
            selectedRadiusMeters: double.infinity,
            distancesMeters: contacts
                .map((c) => GeoUtils.getDistanceMeters(origin, c.geo))
                .toList(),
          );
          final dots = computeNearbyMapDots(
            origin: origin,
            contactsSortedByDistance: contacts, // 생성 순서가 이미 거리순
            displayRadiusMeters: displayRadius,
          );

          expect(dots, hasLength(6), reason: '5명 낱개 + "+N" 뭉침 1개');
          final kept = dots.where((d) => !d.isBadge).toList();
          expect(kept, hasLength(5));
          for (final d in kept) {
            final fraction = sqrt(d.dx * d.dx + d.dy * d.dy);
            expect(
              fraction,
              greaterThan(0.5),
              reason:
                  '옛 결함에서는 이 값이 0.12~0.16이었다(중심 27px 안에 겹침). '
                  '척도가 안 뺏기면 무리가 링의 절반 밖에 찍혀야 한다',
            );
          }

          final overflow = dots.firstWhere((d) => d.isBadge);
          expect(
            overflow.count,
            25,
            reason: '30명 중 5명 낱개 + 나머지 25명(이상치 포함) 뭉침',
          );
          final overflowFraction = sqrt(
            overflow.dx * overflow.dx + overflow.dy * overflow.dy,
          );
          expect(
            overflowFraction,
            closeTo(1.0, 0.01),
            reason:
                '척도를 밀어올린 이상치(230.3km)가 뭉침 앵커(가장 먼 자리)라 '
                '링 가장자리에 붙는다 — 옛 로직처럼 중심 근처에 숨지 않는다',
          );
        },
      );
    });
  });
}
