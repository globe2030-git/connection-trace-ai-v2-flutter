// 좌표 조회 재시도용 "대체 주소" 선택 규칙 검증.
//
// 2026-08-14: OS 지오코더가 도로명 주소로는 좌표를 못 찾는데 지번으로는 찾는
// 경우가 실사용에서 확인됐고, 그 반대도 있을 수 있다. 좌표가 없으면 그 인맥은
// 주변 지도에 아예 안 뜬다. 우편번호 서비스는 두 표기를 함께 주므로, 표시하지
// 않은 쪽을 재시도에 쓴다.
//
// 화면(웹뷰)이 아니라 이 선택 규칙만 따로 검증한다 — 실제 좌표 조회는 OS
// 지오코더라 기기에서만 돌고, 여기서 확인할 수 있는 것은 "어느 주소로 다시
// 물어볼지"까지다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/presentation/common/address_search_view.dart';

void main() {
  group('대체 주소 선택 — 표시하지 않은 쪽을 쓴다', () {
    test('도로명을 표시했으면 지번을 재시도에 쓴다', () {
      const r = AddressSearchResult(
        address: '서울특별시 영등포구 양평로21가길 19',
        roadAddress: '서울특별시 영등포구 양평로21가길 19',
        jibunAddress: '서울특별시 영등포구 양평동4가 62-1',
      );
      expect(r.geocodeFallback, '서울특별시 영등포구 양평동4가 62-1');
    });

    test('지번을 표시했으면 도로명을 재시도에 쓴다 — 반대 방향도 지원', () {
      const r = AddressSearchResult(
        address: '서울특별시 영등포구 양평동4가 62-1',
        roadAddress: '서울특별시 영등포구 양평로21가길 19',
        jibunAddress: '서울특별시 영등포구 양평동4가 62-1',
      );
      expect(r.geocodeFallback, '서울특별시 영등포구 양평로21가길 19');
    });

    test('표시 주소에 참고항목이 붙어 있어도 같은 주소로 본다', () {
      // 목록에 보이는 문장은 "… 235 (삼평동, 에이치스퀘어)"처럼 괄호가 붙는다.
      // 그 안에 도로명이 통째로 들어 있으면 같은 표기로 보고 지번을 쓴다.
      const r = AddressSearchResult(
        address: '경기 성남시 분당구 판교역로 235 (삼평동, 에이치스퀘어)',
        roadAddress: '경기 성남시 분당구 판교역로 235',
        jibunAddress: '경기 성남시 분당구 삼평동 681',
      );
      expect(r.geocodeFallback, '경기 성남시 분당구 삼평동 681');
    });

    test('한쪽만 있으면 그것이 표시 주소와 같을 때 재시도하지 않는다', () {
      const r = AddressSearchResult(
        address: '서울특별시 영등포구 양평로21가길 19',
        roadAddress: '서울특별시 영등포구 양평로21가길 19',
      );
      expect(r.geocodeFallback, isNull);
    });

    test('둘 다 없으면 재시도하지 않는다 — 예전 저장분 호환', () {
      const r = AddressSearchResult(address: '서울특별시 영등포구 양평로21가길 19');
      expect(r.geocodeFallback, isNull);
    });

    test('빈 문자열은 재시도 대상이 아니다', () {
      const r = AddressSearchResult(
        address: '서울특별시 영등포구 양평로21가길 19',
        jibunAddress: '   ',
      );
      expect(r.geocodeFallback, isNull);
    });
  });
}
