import 'dart:convert';

import 'package:connection_trace_ai_flutter/presentation/common/address_search_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨 **주소 검색 결과 해석** — globe2030님 제보로 처음 잠근다(2026-08-28).
///
/// > *"검색 후 주소를 가져오는데 우편번호는 가져오지 않아"*
///
/// ## ⚠️ 이 경로에 테스트가 하나도 없었다
///
/// `test/` 전체에 `zonecode`가 한 번도 안 나왔다. **그런데 "안 만들어서"가
/// 아니라 "만들 수 없어서"였다** — 해석이 웹뷰 채널 콜백 안에 붙어 있어
/// 기기 없이는 부를 수가 없었다.
///
/// 📌 그래서 함수로 떼어낸 뒤 여기서 잠근다. **떼어낸 것이 곧 고치는 일의
/// 절반**이다 — 이제 웹이 무엇을 보내든 재현할 수 있다.
///
/// ## 무엇을 지키나
///
/// 다음 우편번호 위젯이 실제로 보내는 모양(`assets/web/address_search.html`
/// 의 `oncomplete` payload)을 그대로 넣고, **네 값이 다 살아 나오는지** 본다.
void main() {
  /// `address_search.html:156~163`이 만드는 payload 그대로.
  String payload({
    String road = '서울특별시 강남구 테헤란로 152',
    String jibun = '서울특별시 강남구 역삼동 737',
    String zonecode = '06236',
    String building = '강남파이낸스센터',
    String? full,
    double? lat,
    double? lng,
  }) => jsonEncode({
    'roadAddress': road,
    'jibunAddress': jibun,
    'zonecode': zonecode,
    'buildingName': building,
    'fullAddress': full ?? '$road ($building)',
    if (lat != null) 'lat': lat else 'lat': null,
    if (lng != null) 'lng': lng else 'lng': null,
  });

  group('🚨 우편번호가 살아서 온다', () {
    test('⭐ 도로명을 고른 경우', () {
      final r = parseAddressSearchMessage(payload());
      expect(r, isNotNull);
      expect(
        r!.postalCode,
        '06236',
        reason: 'globe2030님 제보가 바로 이 값이다 — 주소는 오는데 이것만 '
            '안 온다고 하셨다',
      );
    });

    test('⭐ 지번을 고른 경우에도 온다', () {
      // 위젯은 userSelectedType과 무관하게 zonecode를 함께 준다.
      final r = parseAddressSearchMessage(
        payload(full: '서울특별시 강남구 역삼동 737'),
      );
      expect(r!.postalCode, '06236');
    });

    test('⭐ 좌표가 함께 와도 우편번호가 안 밀린다', () {
      final r = parseAddressSearchMessage(payload(lat: 37.5, lng: 127.0));
      expect(r!.postalCode, '06236');
      expect(r.geo, isNotNull);
    });

    test('⭐ 앞뒤 공백은 다듬어 담는다', () {
      final r = parseAddressSearchMessage(payload(zonecode: '  06236  '));
      expect(r!.postalCode, '06236');
    });

    test('빈 우편번호는 null — 빈 문자열을 칸에 넣지 않는다', () {
      final r = parseAddressSearchMessage(payload(zonecode: ''));
      expect(
        r!.postalCode,
        isNull,
        reason: '빈 문자열을 넣으면 "채워진 것"으로 보여 OCR 값을 덮어쓴다',
      );
    });
  });

  group('나머지 값도 함께 온다 — 하나가 다른 것을 밀어내지 않는지', () {
    test('⭐ 네 값이 한 번에 다 온다', () {
      final r = parseAddressSearchMessage(payload())!;
      expect(r.address, '서울특별시 강남구 테헤란로 152 (강남파이낸스센터)');
      expect(r.roadAddress, '서울특별시 강남구 테헤란로 152');
      expect(r.jibunAddress, '서울특별시 강남구 역삼동 737');
      expect(r.buildingName, '강남파이낸스센터');
      expect(r.postalCode, '06236');
    });

    test('fullAddress가 없으면 도로명으로 물러선다 — 옛 저장분 호환', () {
      final r = parseAddressSearchMessage(
        jsonEncode({
          'roadAddress': '서울특별시 강남구 테헤란로 152',
          'zonecode': '06236',
        }),
      )!;
      expect(r.address, '서울특별시 강남구 테헤란로 152');
      expect(r.postalCode, '06236');
    });
  });

  group('🚨 깨진 입력이 흐름을 막지 않는다', () {
    test('JSON이 아니면 null', () {
      expect(parseAddressSearchMessage('{ not json'), isNull);
    });

    test('주소가 비면 null — 빈 결과로 화면을 닫는다', () {
      expect(
        parseAddressSearchMessage(jsonEncode({'zonecode': '06236'})),
        isNull,
        reason: '우편번호만 있고 주소가 없으면 쓸 수 없다',
      );
    });
  });
}
