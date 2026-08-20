// 주소 검색(카카오 지도 SDK)에서 받은 좌표를 저장 시점에 재사용해도 되는지
// 판단하는 순수 함수 canTrustPickedGeo를 검증한다(추가 350).
//
// PR #365로 AddressSearchResult.geo가 생겼지만 아무도 안 쓰고 있었다 —
// 명함 등록 화면은 주소를 검색으로 골라도 저장할 때마다 OS 지오코더를 또
// 불러 같은 주소의 좌표를 다시 구했다. 이 테스트는 "언제 그 중복 호출을
// 건너뛰어도 안전한지"를 판단 실물로 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/add_card_modal_view.dart';

void main() {
  group('canTrustPickedGeo', () {
    const geo = GeoPosition(lat: 37.4, lng: 127.1);
    const address = '경기 성남시 분당구 판교역로 235';

    test('검색으로 좌표를 받았고 주소를 그대로 저장하면 신뢰한다', () {
      final trust = canTrustPickedGeo(
        pickedGeo: geo,
        pickedGeoAddress: address,
        rawAddress: address,
      );
      expect(trust, isTrue);
    });

    test('애초에 주소를 검색으로 안 골랐으면(pickedGeo == null) 신뢰하지 않는다', () {
      final trust = canTrustPickedGeo(
        pickedGeo: null,
        pickedGeoAddress: null,
        rawAddress: address,
      );
      expect(trust, isFalse);
    });

    test('카카오가 좌표를 못 줬으면(geo == null) 신뢰하지 않는다 — OS 지오코더로 폴백', () {
      final trust = canTrustPickedGeo(
        pickedGeo: null,
        pickedGeoAddress: address, // 주소는 검색으로 골랐지만 좌표는 없었던 경우
        rawAddress: address,
      );
      expect(trust, isFalse);
    });

    test('검색으로 고른 뒤 주소를 손으로 편집하면 옛 좌표를 신뢰하지 않는다', () {
      const editedAddress = '경기 성남시 분당구 판교역로 235-1';
      final trust = canTrustPickedGeo(
        pickedGeo: geo,
        pickedGeoAddress: address,
        rawAddress: editedAddress,
      );
      expect(
        trust,
        isFalse,
        reason: '편집된 주소는 검색 시점의 좌표와 더는 대응하지 않는다',
      );
    });

    test('편집했다가 정확히 같은 문자열로 되돌리면 다시 신뢰해도 된다', () {
      // 우연히도 최종 문자열이 검색 결과와 같다면, 그 좌표를 쓰는 것은
      // 정확한 동작이다(주소가 같으므로 좌표도 같다) — 별도 "무효화됨" 플래그
      // 없이 문자열 비교만으로 판단하는 설계가 의도한 동작.
      final trust = canTrustPickedGeo(
        pickedGeo: geo,
        pickedGeoAddress: address,
        rawAddress: address,
      );
      expect(trust, isTrue);
    });
  });
}
