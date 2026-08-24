import 'package:connection_trace_ai_flutter/core/utils/address_grouping.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_clusters.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 지도 화면의 묶음 마커(P2-①)가 목록 화면(F-15)과 **같은 판정**을
/// 내리는지, 그리고 바텀시트 목록 행 계산이 맞는지를 검사한다.
///
/// 묶음 규칙 자체([groupContactsByAddress])는 `address_grouping_test.dart`가
/// 이미 고정하고 있으므로 여기서 다시 검사하지 않는다 — 여기서 확인할 것은
/// "지도가 그 함수를 그대로 쓰는가"와 "그 위에 얹은 지도 전용 계산
/// (대표 좌표, 바텀시트 행)이 맞는가"다.
void main() {
  ContactModel contactAt(
    String id,
    String name, {
    String? address,
    GeoPosition? geo,
    String title = '',
    String company = '',
  }) => ContactModel(
    id: id,
    name: name,
    company: company,
    title: title,
    phone: '',
    email: '',
    address: address,
    tags: const [],
    talkingPoints: const [],
    geo: geo,
  );

  group('computeMapMarkerGroups — F-15와 같은 판정', () {
    test('⭐ 같은 도로명 주소면 지도에서도 한 마커로 묶인다', () {
      final contacts = [
        contactAt(
          'a',
          '가나다',
          address: '서울특별시 강남구 테헤란로 123',
          geo: const GeoPosition(lat: 37.5, lng: 127.0),
        ),
        contactAt(
          'b',
          '라마바',
          address: '서울특별시 강남구 테헤란로 123',
          geo: const GeoPosition(lat: 37.5001, lng: 127.0001),
        ),
      ];

      final markers = computeMapMarkerGroups(contacts);

      expect(markers, hasLength(1));
      expect(markers.single.isGrouped, isTrue);
      expect(markers.single.count, 2);
    });

    test('⭐ 목록 화면과 지도 화면이 같은 함수 위에서 동일한 묶음을 만든다', () {
      // F-15(목록)와 P2-①(지도)이 서로 다른 규칙으로 묶으면 같은 데이터를
      // 두고 "목록엔 3명, 지도엔 낱개 2+묶음 1"처럼 어긋난다. 같은
      // 함수([groupContactsByAddress])를 감싸기만 했는지를 확인한다.
      final contacts = [
        contactAt(
          '가까움',
          '가까움',
          address: 'A로 1',
          geo: const GeoPosition(lat: 0, lng: 0),
        ),
        contactAt(
          '중간',
          '중간',
          address: 'B로 2',
          geo: const GeoPosition(lat: 1, lng: 1),
        ),
        contactAt(
          '멀지만같은건물',
          '멀지만같은건물',
          address: 'A로 1',
          geo: const GeoPosition(lat: 0.001, lng: 0.001),
        ),
      ];

      final listGroups = groupContactsByAddress(contacts);
      final mapMarkers = computeMapMarkerGroups(contacts);

      expect(mapMarkers, hasLength(listGroups.length));
      for (var i = 0; i < listGroups.length; i++) {
        expect(
          mapMarkers[i].group.contacts.map((c) => c.id).toList(),
          listGroups[i].contacts.map((c) => c.id).toList(),
          reason: '지도 마커의 묶음 구성이 목록의 묶음 구성과 달라졌다',
        );
      }
    });

    test('주소가 없으면 서로 묶지 않는다(낱개 마커)', () {
      final contacts = [
        contactAt('a', '가', geo: const GeoPosition(lat: 0, lng: 0)),
        contactAt(
          'b',
          '나',
          address: '',
          geo: const GeoPosition(lat: 0, lng: 0.0001),
        ),
      ];

      final markers = computeMapMarkerGroups(contacts);

      expect(markers, hasLength(2));
      expect(markers.every((m) => !m.isGrouped), isTrue);
    });

    test('마커 대표 좌표는 묶음 안 첫 인맥의 좌표를 쓴다', () {
      const first = GeoPosition(lat: 37.1, lng: 127.1);
      const second = GeoPosition(lat: 37.1002, lng: 127.1002);
      final contacts = [
        contactAt('첫째', '첫째', address: '같은로 1', geo: first),
        contactAt('둘째', '둘째', address: '같은로 1', geo: second),
      ];

      final markers = computeMapMarkerGroups(contacts);

      expect(markers.single.point.lat, first.lat);
      expect(markers.single.point.lng, first.lng);
    });

    test('빈 목록은 빈 결과', () {
      expect(computeMapMarkerGroups(const []), isEmpty);
    });
  });

  group('buildGroupSheetRows — 바텀시트 목록 구성', () {
    const origin = GeoPosition(lat: 0, lng: 0);

    test('⭐ 묶음의 인맥 순서를 그대로 유지한다(거리순이 깨지지 않는다)', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt(
            '첫째',
            '첫째',
            address: '테헤란로 123',
            geo: const GeoPosition(lat: 0, lng: 0.001),
          ),
          contactAt(
            '둘째',
            '둘째',
            address: '테헤란로 123',
            geo: const GeoPosition(lat: 0, lng: 0.001),
          ),
        ],
      );

      final rows = buildGroupSheetRows(group: group, origin: origin);

      expect(rows.map((r) => r.contact.id).toList(), ['첫째', '둘째']);
    });

    test('거리는 기준점(origin)에서 각 인맥 좌표까지로 계산한다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt(
            'a',
            '가',
            address: '테헤란로 123',
            geo: const GeoPosition(lat: 0, lng: 0.01), // 적도 위 약 1.1km
          ),
        ],
      );

      final rows = buildGroupSheetRows(group: group, origin: origin);

      expect(
        rows.single.distanceMeters,
        closeTo(
          GeoUtils.getDistanceMeters(
            origin,
            const GeoPosition(lat: 0, lng: 0.01),
          ),
          0.001,
        ),
      );
    });

    test('직함·회사가 모두 있으면 "직함 · 회사" 순서로 합친다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt(
            'a',
            '가',
            address: '테헤란로 123',
            title: '팀장',
            company: '커넥션센스',
            geo: const GeoPosition(lat: 0, lng: 0),
          ),
        ],
      );

      final rows = buildGroupSheetRows(group: group, origin: origin);

      expect(rows.single.subtitle, '팀장 · 커넥션센스');
    });

    test('직함·회사 중 하나만 있어도 구분자 없이 그 값만 남는다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt(
            'a',
            '가',
            address: '테헤란로 123',
            company: '커넥션센스',
            geo: const GeoPosition(lat: 0, lng: 0),
          ),
        ],
      );

      final rows = buildGroupSheetRows(group: group, origin: origin);

      expect(rows.single.subtitle, '커넥션센스');
    });

    test('빈 묶음은 빈 결과', () {
      const group = AddressGroup(address: '', contacts: []);
      expect(buildGroupSheetRows(group: group, origin: origin), isEmpty);
    });
  });

  group('groupCompanyLabel — 묶음 마커의 대표 회사명(추가 445, ②)', () {
    test('⭐ 가장 많은 명함이 속한 회사가 대표가 되고 나머지 수를 붙인다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt('a', '가', company: '크림하우스'),
          contactAt('b', '나', company: '크림하우스'),
          contactAt('c', '다', company: '다른회사'),
        ],
      );

      expect(groupCompanyLabel(group), '크림하우스 외 1');
    });

    test('전원이 같은 회사면 "외 N" 없이 회사명만 준다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt('a', '가', company: '크림하우스'),
          contactAt('b', '나', company: '크림하우스'),
        ],
      );

      expect(groupCompanyLabel(group), '크림하우스');
    });

    test('회사명이 모두 다르면(동률) 먼저 나온 회사가 대표가 된다', () {
      // 지시된 두 규칙("가장 많은 회사" 또는 "첫 명함의 회사")이 동률
      // 상황에서는 같은 답을 내야 한다 — 먼저 나온 회사가 곧 첫 명함의
      // 회사이기도 하다.
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt('a', '가', company: '먼저회사'),
          contactAt('b', '나', company: '나중회사'),
        ],
      );

      expect(groupCompanyLabel(group), '먼저회사 외 1');
    });

    test('회사명이 모두 비어 있으면 null — 호출부가 "같은 주소 N명"으로 대신한다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [contactAt('a', '가'), contactAt('b', '나')],
      );

      expect(groupCompanyLabel(group), isNull);
    });

    test('일부만 회사명이 있으면 회사명이 있는 사람들끼리만 비교한다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [
          contactAt('a', '가'), // 회사명 없음 — 집계에서 제외
          contactAt('b', '나', company: '크림하우스'),
          contactAt('c', '다', company: '크림하우스'),
        ],
      );

      // 전체 3명 중 대표 회사(크림하우스)는 2명 → 나머지 1명("외 1").
      expect(groupCompanyLabel(group), '크림하우스 외 1');
    });

    test('낱개(1명)여도 회사명이 있으면 그대로 준다', () {
      final group = AddressGroup(
        address: '테헤란로 123',
        contacts: [contactAt('a', '가', company: '크림하우스')],
      );

      expect(groupCompanyLabel(group), '크림하우스');
    });
  });

  group('bucketContactsByCompany — 겹친 마커 클러스터 시트의 회사 목록(추가 452)', () {
    test('⭐ 회사별로 나누고 인원 많은 회사가 앞선다', () {
      final contacts = [
        contactAt('a', '가', company: '크림하우스'),
        contactAt('b', '나', company: '다른회사'),
        contactAt('c', '다', company: '크림하우스'),
      ];

      final buckets = bucketContactsByCompany(contacts);

      expect(buckets.map((b) => b.label).toList(), ['크림하우스', '다른회사']);
      expect(buckets.first.contacts.map((c) => c.id).toList(), ['a', 'c']);
    });

    test('회사명이 없는 인맥은 "회사 정보 없음"으로 모으고, 인원이 많아도 맨 뒤로 보낸다', () {
      final contacts = [
        contactAt('a', '가'), // 회사 없음
        contactAt('b', '나'), // 회사 없음
        contactAt('c', '다'), // 회사 없음
        contactAt('d', '라', company: '작은회사'), // 1명뿐
      ];

      final buckets = bucketContactsByCompany(contacts);

      expect(buckets.last.label, kNoCompanyLabel);
      expect(buckets.last.contacts, hasLength(3));
      expect(buckets.first.label, '작은회사');
    });

    test('회사가 하나뿐이면 묶음도 하나뿐', () {
      final contacts = [
        contactAt('a', '가', company: '크림하우스'),
        contactAt('b', '나', company: '크림하우스'),
      ];

      final buckets = bucketContactsByCompany(contacts);

      expect(buckets, hasLength(1));
      expect(buckets.single.contacts, hasLength(2));
    });

    test('빈 목록은 빈 결과', () {
      expect(bucketContactsByCompany(const []), isEmpty);
    });
  });

  group('buildContactRows — buildGroupSheetRows와 같은 규칙을 공유한다', () {
    const origin = GeoPosition(lat: 0, lng: 0);

    test('여러 묶음을 합친 인맥 목록도 같은 방식으로 행이 된다', () {
      final contacts = [
        contactAt(
          'a',
          '가',
          title: '팀장',
          company: '크림하우스',
          geo: const GeoPosition(lat: 0, lng: 0.001),
        ),
      ];

      final rows = buildContactRows(contacts, origin);

      expect(rows.single.subtitle, '팀장 · 크림하우스');
      expect(rows.single.distanceMeters, isNonNegative);
    });
  });
}
