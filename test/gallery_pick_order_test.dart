// 갤러리 2장 선택의 "순서 바꾸기"(P2-②) 순수 로직을 검증한다.
//
// 왜 따로 재나: `image_picker`가 돌려주는 순서가 "탭한 순서"라는 보장이
// 없어(ocr_scanner_service.dart의 pickUpToTwoImagesFromGallery 문서 참고),
// 화면은 반드시 "순서 바꾸기" 버튼으로 사용자가 바로잡을 수 있어야 한다.
// 그 버튼이 실제로 하는 일이 이 함수 하나다.
import 'package:connection_trace_ai_flutter/core/utils/gallery_pick_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('swapFrontBackOrder', () {
    test('2장이면 앞뒤를 맞바꾼다', () {
      expect(swapFrontBackOrder(['front', 'back']), ['back', 'front']);
    });

    test('⚠️ 1장뿐이면 손대지 않는다 — 앞/뒷면 개념이 없다', () {
      expect(swapFrontBackOrder(['only']), ['only']);
    });

    test('0장이면 그대로 빈 목록이다', () {
      expect(swapFrontBackOrder(<String>[]), <String>[]);
    });

    test('📌 두 번 누르면 제자리로 돌아온다', () {
      final once = swapFrontBackOrder(['A', 'B']);
      final twice = swapFrontBackOrder(once);
      expect(twice, ['A', 'B']);
    });

    test('제네릭이라 이미지 바이트 목록에도 같은 규칙을 쓸 수 있다', () {
      expect(swapFrontBackOrder([1, 2]), [2, 1]);
    });
  });
}
