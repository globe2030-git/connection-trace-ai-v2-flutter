import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/address_geocoding_service.dart';

/// 우편번호 서비스에서 고른 주소에는 참고항목(법정동·건물명)이 괄호로 붙는다.
/// 저장은 괄호를 포함한 원본 그대로 하되, 좌표 조회 질의에서는 떼어내야
/// OS 지오코더가 주소를 찾는다(backlog 추가 83).
void main() {
  group('stripReferenceText', () {
    test('끝에 붙은 참고항목 괄호를 떼어낸다', () {
      expect(
        stripReferenceText('경기 성남시 분당구 판교역로 235 (삼평동, 에이치스퀘어)'),
        '경기 성남시 분당구 판교역로 235',
      );
    });

    test('괄호가 없으면 그대로 둔다', () {
      expect(
        stripReferenceText('서울 영등포구 양평로21가길 19'),
        '서울 영등포구 양평로21가길 19',
      );
    });

    test('중간에 있는 괄호는 건드리지 않는다', () {
      // 끝의 참고항목만 대상이다.
      expect(
        stripReferenceText('서울 (구)중구 세종대로 110'),
        '서울 (구)중구 세종대로 110',
      );
    });

    test('괄호만 남는 경우에는 원본을 유지한다', () {
      expect(stripReferenceText('(삼평동)'), '(삼평동)');
    });

    test('앞뒤 공백을 정리한다', () {
      expect(stripReferenceText('  세종대로 110 (정동)  '), '세종대로 110');
    });
  });
}
