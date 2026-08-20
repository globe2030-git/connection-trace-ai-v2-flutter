// "도로명 주소로 변경하시겠습니까?" 팝업이 다시 떠야 할 때/뜨면 안 될 때를
// 검증한다.
//
// 테스터 A(갤럭시 폴드7, 1.0.0(8))가 "기존 입력 유지"를 눌러도 저장할 때마다
// 같은 팝업이 계속 다시 뜬다고 제보했다. 원인은 "네, 도로명으로 변경" 쪽만
// _confirmedRoadNameAddress를 갱신하고 "기존 입력 유지" 쪽은 아무 상태도
// 바꾸지 않는 비대칭 구조였다 — 팝업을 실제로 띄우려면 카메라·주소 검색·
// Provider까지 갖춘 전체 화면을 띄워야 하므로, 그 판단만 순수 함수로 뽑아
// 여기서 검증한다(shouldShowRoadNameConversionDialog).
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/add_card_modal_view.dart';

void main() {
  group('shouldShowRoadNameConversionDialog', () {
    test('아직 아무 결정도 안 됐고 도로명 주소가 원본과 다르면 뜬다', () {
      final show = shouldShowRoadNameConversionDialog(
        roadNameAddress: '서울특별시 강남구 테헤란로 123',
        rawAddress: '서울시 강남구 역삼동 123-45',
        confirmedRoadNameAddress: null,
      );
      expect(show, isTrue);
    });

    test(
      '"기존 입력 유지"를 눌러 원본 주소가 확정되면, 같은 주소로 다시 저장해도 '
      '더 이상 뜨지 않는다 — 테스터 A 제보 재현·수정 확인',
      () {
        const rawAddress = '서울시 강남구 역삼동 123-45';
        const roadNameAddress = '서울특별시 강남구 테헤란로 123';

        // 1차 저장 시도: 아직 결정된 바 없으니 팝업이 뜬다.
        expect(
          shouldShowRoadNameConversionDialog(
            roadNameAddress: roadNameAddress,
            rawAddress: rawAddress,
            confirmedRoadNameAddress: null,
          ),
          isTrue,
        );

        // "기존 입력 유지" 클릭 → 원본 주소를 확정 값으로 기록한다(이번 수정).
        const confirmedAfterKeep = rawAddress;

        // 주소를 손대지 않고 다시 저장을 눌러도 같은 팝업이 또 뜨면 안 된다.
        expect(
          shouldShowRoadNameConversionDialog(
            roadNameAddress: roadNameAddress,
            rawAddress: rawAddress,
            confirmedRoadNameAddress: confirmedAfterKeep,
          ),
          isFalse,
          reason: '고치기 전에는 이 케이스에서 계속 true가 나와 팝업이 무한히 다시 떴다',
        );
      },
    );

    test('"네, 도로명으로 변경"을 누른 뒤 그대로 다시 저장하면 뜨지 않는다(회귀 금지)', () {
      const rawAddressAfterConvert = '서울특별시 강남구 테헤란로 123';
      const roadNameAddress = '서울특별시 강남구 테헤란로 123';

      // "네"를 누르면 주소 입력칸 자체가 도로명 주소로 바뀌고,
      // _confirmedRoadNameAddress도 그 도로명 주소로 갱신된다.
      const confirmedAfterConvert = roadNameAddress;

      expect(
        shouldShowRoadNameConversionDialog(
          roadNameAddress: roadNameAddress,
          rawAddress: rawAddressAfterConvert,
          confirmedRoadNameAddress: confirmedAfterConvert,
        ),
        isFalse,
      );
    });

    test('"기존 입력 유지" 이후 사용자가 주소를 실제로 편집하면 새 주소에는 다시 제안한다', () {
      const originalAddress = '서울시 강남구 역삼동 123-45';
      const confirmedAfterKeep = originalAddress;
      const editedAddress = '서울시 강남구 역삼동 999-1'; // 사용자가 직접 고침
      const newRoadNameAddress = '서울특별시 강남구 테헤란로 456';

      expect(
        shouldShowRoadNameConversionDialog(
          roadNameAddress: newRoadNameAddress,
          rawAddress: editedAddress,
          confirmedRoadNameAddress: confirmedAfterKeep,
        ),
        isTrue,
        reason: '영구 무시가 아니라 그 주소 하나에 대한 결정이어야 한다',
      );
    });

    test('도로명 주소를 찾지 못했으면(null) 애초에 뜨지 않는다', () {
      final show = shouldShowRoadNameConversionDialog(
        roadNameAddress: null,
        rawAddress: '서울시 강남구 역삼동 123-45',
        confirmedRoadNameAddress: null,
      );
      expect(show, isFalse);
    });

    test('도로명 주소가 원본과 이미 같으면 뜨지 않는다', () {
      const address = '서울특별시 강남구 테헤란로 123';
      final show = shouldShowRoadNameConversionDialog(
        roadNameAddress: address,
        rawAddress: address,
        confirmedRoadNameAddress: null,
      );
      expect(show, isFalse);
    });
  });
}
