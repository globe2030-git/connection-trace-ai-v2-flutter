import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/address_region.dart';

/// ⚠️ 이 파서가 하는 일은 **좌표를 못 얻은 명함을 목록에 되살리는 것**이다.
///
/// 주변 인맥은 좌표로 거리를 잰다. 좌표가 없으면 그 명함은 목록에서 조용히
/// 빠진다(추가 79에서 실기기로 겪었다). 주소 문자열에서 구까지만 뽑아도
/// "같은 지역" 구획으로 보여줄 수 있다.
///
/// 📌 2026-08-21 실측: 등록 명함 93건에서 **하나도 빠짐없이** 뽑혔다.
void main() {
  group('시/도', () {
    test('정식 명칭', () {
      expect(regionOf('서울특별시 강남구 테헤란로 123').sido, '서울특별시');
      expect(regionOf('경기도 성남시 분당구 판교역로 235').sido, '경기도');
    });

    test('⚠️ 명함에 흔한 줄임말도 잡는다 — 자리가 좁아 줄여 쓴다', () {
      expect(regionOf('서울 강남구 테헤란로 123').sido, '서울특별시');
      expect(regionOf('경기 성남시 분당구 판교역로 235').sido, '경기도');
      expect(regionOf('충남 천안시 서북구 불당대로 1').sido, '충청남도');
    });

    test('"서울시" 처럼 시를 붙여 쓴 것도 잡는다', () {
      expect(regionOf('서울시 종로구 세종대로 1').sido, '서울특별시');
    });

    test('⚠️ 도로명이 시/도 이름으로 시작해도 오인하지 않는다', () {
      // "서울대로"를 "서울"로 읽어 버리면 엉뚱한 지역으로 묶인다.
      expect(regionOf('경기도 안양시 서울대로 100').sido, '경기도');
    });

    test('⚠️ 긴 이름이 짧은 이름에 먹히지 않는다', () {
      // "전라북도"가 "전북"보다 먼저 확인돼야 한다.
      expect(regionOf('전라북도 전주시 완산구 관선1길 1').sido, '전라북도');
    });
  });

  group('시군구', () {
    test('구 하나', () {
      expect(regionOf('서울특별시 강남구 테헤란로 123').sigungu, '강남구');
    });

    test('⭐ 시 + 구 둘 다 나오면 둘 다 담는다', () {
      // "성남시"만 담으면 분당구와 수정구가 한 덩어리가 된다.
      expect(regionOf('경기도 성남시 분당구 판교역로 235').sigungu, '성남시 분당구');
    });

    test('군', () {
      expect(regionOf('강원특별자치도 양양군 양양읍 도로 1').sigungu, '양양군');
    });

    test('⚠️ 도로명에 든 "구"를 시군구로 오인하지 않는다', () {
      // 뒤에 공백이나 끝이 와야 인정한다.
      final r = regionOf('서울특별시 구로구 디지털로 32길 30');
      expect(r.sigungu, '구로구');
    });
  });

  group('묶음 키와 표시 이름', () {
    test('⚠️ 구가 있으면 구까지 묶는다 — 시/도만으로는 거의 한 덩어리가 된다', () {
      // 실측 표본 93건 중 84건이 서울이었다. 시/도로 묶으면 의미가 없다.
      expect(regionOf('서울특별시 강남구 테헤란로 1').groupKey, '서울특별시 강남구');
      expect(regionOf('서울특별시 서초구 서초대로 1').groupKey, '서울특별시 서초구');
    });

    test('구를 못 뽑으면 시/도로 물러난다 — 아예 빠지는 것보다 낫다', () {
      final r = regionOf('서울특별시 어딘가로 123');
      expect(r.sigungu, isNull);
      expect(r.groupKey, '서울특별시');
    });

    test('화면에는 짧게 보여준다', () {
      expect(regionOf('서울특별시 강남구 테헤란로 1').shortLabel, '강남구');
      expect(regionOf('서울특별시 어딘가로 1').shortLabel, '서울');
    });
  });

  group('⚠️ 실측이 잡은 형태들 — 붙여 쓴 주소', () {
    // 실제 등록 명함 93건으로 대조하다 **세 번 고쳤다.** 처음 규칙은 뒤에
    // 공백이 오는 것만 인정했는데, 명함은 자리가 좁아 공백을 지운다.
    test('⭐ 시/도와 구를 붙여 썼다', () {
      final r = regionOf('서울강남구테헤란로123');
      expect(r.sido, '서울특별시');
      expect(r.sigungu, '강남구');
    });

    test('⭐ 시/도 + 시 + 구까지 전부 붙여 썼다', () {
      final r = regionOf('서울시강남구테헤란로123');
      expect(r.sido, '서울특별시');
      expect(r.sigungu, '강남구');
    });

    test('⚠️ 구가 아예 없으면 시/도라도 살린다', () {
      // 실측 5건이 이 형태였다(한글 + 영문, 구 없음).
      // 통째로 빠지는 것보다 "서울" 묶음에라도 들어가는 편이 낫다.
      final r = regionOf('서울역삼동 ABCD Tower');
      expect(r.sido, '서울특별시');
      expect(r.groupKey, isNotNull);
    });

    test('⚠️ "경기시흥시"에서 시를 떼면 안 된다', () {
      // "서울시강남구"의 시는 접미사지만 "시흥시"의 시는 지명의 일부다.
      // 가르는 기준은 떼고 난 뒤가 '구'로 끝나는가다.
      final r = regionOf('경기시흥시정왕대로 1');
      expect(r.sido, '경기도');
      expect(r.sigungu, startsWith('시흥시'));
    });

    test('⚠️ 그래도 도로명은 시/도로 오인하지 않는다', () {
      // "서울대로"·"서울로"·"서울길".
      expect(regionOf('서울대로 123').sido, isNull);
      expect(regionOf('서울로 45').sido, isNull);
    });
  });

  group('빈 값·이상한 값', () {
    test('비어 있으면 조용히 빈 결과', () {
      expect(regionOf(null).isEmpty, isTrue);
      expect(regionOf('').isEmpty, isTrue);
      expect(regionOf('   ').isEmpty, isTrue);
    });

    test('⚠️ 주소가 아니어도 예외를 던지지 않는다', () {
      // OCR이 엉뚱한 값을 넣을 수 있다. 여기서 던지면 목록이 통째로 깨진다.
      expect(regionOf('오류').isEmpty, isTrue);
      expect(() => regionOf('!@#\$%'), returnsNormally);
    });
  });
}
