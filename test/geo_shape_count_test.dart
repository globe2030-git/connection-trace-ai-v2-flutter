import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 추가 404 — 진단 화면의 형태 집계가 비어 있던 문제.
///
/// 쌓아 둔 실패 집계는 "그 주소의 첫 실패"에서만 늘고, 3회 실패한 명함은
/// 재시도조차 안 하며, 계측은 나중에 붙었다. 그래서 **이미 실패한 것은 영영
/// 집계에 못 들어온다** — 실기기에서 좌표 없는 명함 67장인데 집계는 0줄이었다.
///
/// `countShapesWithoutGeo`는 **지금 명함 목록에서** 세므로 그 공백이 없다.
ContactModel _contact({
  required String id,
  String? address,
  GeoPosition? geo,
}) => ContactModel(
  id: id,
  name: '테스트$id',
  company: '회사',
  title: '직함',
  phone: '010-0000-0000',
  email: 'a@b.c',
  address: address,
  geo: geo,
  tags: const [],
  talkingPoints: const [],
);

void main() {
  group('countShapesWithoutGeo', () {
    test('좌표가 없는 명함만 센다', () {
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1', address: '서울 강남구 테헤란로 123'),
        _contact(
          id: '2',
          address: '서울 강남구 테헤란로 456',
          geo: const GeoPosition(lat: 37.5, lng: 127.0),
        ),
      ]);
      expect(counts.values.fold<int>(0, (a, b) => a + b), 1);
    });

    test('주소가 없으면 세지 않는다 — 좌표를 만들 대상이 아니다', () {
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1'),
        _contact(id: '2', address: '   '),
      ]);
      expect(counts, isEmpty);
    });

    test('같은 형태는 한 칸에 모인다', () {
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1', address: '서울 강남구 테헤란로 123'),
        _contact(id: '2', address: '서울 서초구 반포대로 456'),
      ]);
      // 둘 다 도로명 + 숫자 + 건물명 없음 + 같은 길이 구간 → 같은 코드
      expect(counts.length, 1);
      expect(counts.values.first, 2);
    });

    test('형태가 다르면 갈린다 — 도로명과 지번', () {
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1', address: '서울 강남구 테헤란로 123'),
        _contact(id: '2', address: '서울 관악구 봉천동 1659-5'),
      ]);
      expect(counts.length, 2);
    });

    test('⚠️ 시도 여부와 무관하게 센다 — 이것이 추가 404의 요지다', () {
      // 한 번도 시도한 적 없는 명함이든, 3회 실패해 포기된 명함이든
      // 여기서는 똑같이 잡힌다. 쌓아 둔 집계는 전자를 못 본다.
      final counts = GeoBackfillService.countShapesWithoutGeo([
        for (var i = 0; i < 67; i++)
          _contact(id: '$i', address: '서울 강남구 테헤란로 $i'),
      ]);
      expect(counts.values.fold<int>(0, (a, b) => a + b), 67);
    });

    test('빈 목록이면 빈 결과', () {
      expect(GeoBackfillService.countShapesWithoutGeo(const []), isEmpty);
    });

    test('세는 값에 주소 원문이 남지 않는다', () {
      const address = '서울특별시 강남구 테헤란로 123 무슨빌딩 4층';
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1', address: address),
      ]);
      final key = counts.keys.single;
      // 형태 코드만 남아야 한다 — 동 이름·번지·건물명이 새면 안 된다.
      expect(
        key,
        matches(
          RegExp(r'^road=[01];jibun=[01];digit=[01];bldg=[01];len=[SML]$'),
        ),
      );
      for (final piece in ['강남', '테헤란', '무슨빌딩', '123']) {
        expect(key.contains(piece), isFalse, reason: '원문 조각이 샜다: $piece');
      }
    });

    test('푸는 함수가 그 코드를 사람 말로 바꿔 준다', () {
      final counts = GeoBackfillService.countShapesWithoutGeo([
        _contact(id: '1', address: '서울 강남구 테헤란로 123'),
      ]);
      final described = GeoBackfillService.describeFailureShape(
        counts.keys.single,
      );
      expect(described, isNotEmpty);
      expect(described, isNot(contains('road=')));
    });
  });
}
