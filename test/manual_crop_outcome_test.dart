// 갤러리 자르기(398)에서 ManualCropView가 돌려준 값을 어떻게 해석하는지
// (galleryCropOutcomeFor) 검증한다.
//
// 왜 따로 재나: 자르기 화면은 세 가지 다른 방식으로 닫힐 수 있다 — [이대로
// 자르기](ManualCropResult), [자르기 없이 사용](ManualCropSkipped), 뒤로
// 가기(null). 부르는 쪽(file_picker_modal_view.dart)이 이 셋을 구분하지
// 못하면 "취소"인데 원본으로 계속 진행하거나, 반대로 "자르기 없이 사용"을
// 취소로 오인해 처리를 통째로 중단하는 결함이 난다 — Navigator·위젯 없이
// 이 갈래만 순수하게 검사한다.
import 'dart:ui';

import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/manual_crop_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('galleryCropOutcomeFor', () {
    test('네 점을 가진 ManualCropResult면 cropped', () {
      const result = ManualCropResult(
        imagePath: '/tmp/card.jpg',
        corners: [
          Offset(0.1, 0.1),
          Offset(0.9, 0.1),
          Offset(0.9, 0.9),
          Offset(0.1, 0.9),
        ],
        imageSize: Size(1000, 600),
      );
      expect(galleryCropOutcomeFor(result), GalleryCropOutcome.cropped);
    });

    test('⚠️ 귀퉁이가 4개가 아니면 cropped로 보지 않는다(방어적)', () {
      const malformed = ManualCropResult(
        imagePath: '/tmp/card.jpg',
        corners: [Offset(0.1, 0.1), Offset(0.9, 0.1)],
        imageSize: Size(1000, 600),
      );
      expect(
        galleryCropOutcomeFor(malformed),
        GalleryCropOutcome.cancelled,
      );
    });

    test('ManualCropSkipped면 useOriginal — 취소가 아니다', () {
      expect(
        galleryCropOutcomeFor(const ManualCropSkipped()),
        GalleryCropOutcome.useOriginal,
      );
    });

    test('null(뒤로 가기)이면 cancelled', () {
      expect(galleryCropOutcomeFor(null), GalleryCropOutcome.cancelled);
    });

    test('알 수 없는 타입이 와도 안전하게 cancelled로 본다', () {
      expect(galleryCropOutcomeFor(Object()), GalleryCropOutcome.cancelled);
    });
  });
}
