// 좌표 실패의 **분모**를 세는 것(추가 344).
//
// ## 왜 필요했나
//
// 진단 화면이 실패 **건수**만 보여 줘서 *"11건이 많은 건가 적은 건가"*를 말할 수
// 없었다(추가 343). 분모가 있어야 판단이 선다 — 주소 있는 명함 20장 중 11건이면
// 시급하고, 150장 중이면 뒤로 미뤄도 된다.
//
// ⚠️ **시도 횟수를 새로 세지 않았다.** 새 카운터는 0부터 시작해서, 이미 쌓인
// 실패 11건과 짝이 안 맞는다(*"실패 11건 / 시도 0건"*). **지금 상태를 직접
// 세면** 기록이 언제 시작됐는지와 무관하다.
import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel _c({String? address, GeoPosition? geo}) => ContactModel(
  id: 'id-${address ?? ''}-${geo?.lat ?? ''}',
  name: '홍길동',
  company: '(주)어디어디',
  title: '부장',
  phone: '010-0000-0001',
  officePhone: '02-0000-0002',
  email: 'a@b.com',
  address: address,
  geo: geo,
  tags: const [],
  talkingPoints: const [],
);

void main() {
  group('좌표 채움 세기', () {
    test('아무것도 없으면 0', () {
      final r = GeoBackfillService.countGeoCoverage(const []);
      expect(r.withAddress, 0);
      expect(r.missingGeo, 0);
    });

    test('주소 없는 명함은 분모에 안 넣는다', () {
      final r = GeoBackfillService.countGeoCoverage([
        _c(),
        _c(address: ''),
        _c(address: '   '),
      ]);
      expect(r.withAddress, 0, reason: '빈 문자열·공백도 주소가 아니다');
    });

    test('주소 있고 좌표 있으면 성공으로 센다', () {
      final r = GeoBackfillService.countGeoCoverage([
        _c(address: '서울시 어디구 어디로 1', geo: const GeoPosition(lat: 1, lng: 2)),
      ]);
      expect(r.withAddress, 1);
      expect(r.missingGeo, 0);
    });

    test('주소 있고 좌표 없으면 실패로 센다', () {
      final r = GeoBackfillService.countGeoCoverage([
        _c(address: '서울시 어디구 어디로 1'),
      ]);
      expect(r.withAddress, 1);
      expect(r.missingGeo, 1);
    });

    test('섞여 있으면 각각 센다', () {
      final r = GeoBackfillService.countGeoCoverage([
        _c(address: '주소1', geo: const GeoPosition(lat: 1, lng: 2)),
        _c(address: '주소2'),
        _c(address: '주소3'),
        _c(), // 주소 없음 — 분모 밖
      ]);
      expect(r.withAddress, 3);
      expect(r.missingGeo, 2);
    });

    test('⚠️ 분모가 0이면 비율을 만들지 않는다 — 나눗셈이 터진다', () {
      final r = GeoBackfillService.countGeoCoverage([_c()]);
      expect(r.withAddress, 0);
      // 화면은 withAddress > 0 일 때만 비율을 그린다.
    });
  });
}
