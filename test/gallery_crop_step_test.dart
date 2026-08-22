// 갤러리 자르기(398)의 단계 라벨 계산("앞면 자르기 1/2" 등)을 검증한다.
//
// 왜 따로 재나: P2-②(2장 선택)와 결합되면서 앞·뒷면을 순서대로 자르게
// 됐다. 인덱스 하나가 밀리면 "뒷면"이라고 써야 할 자리에 "앞면"이 뜨는데,
// 화면만 봐서는 늘 맞는 것처럼 보이기 쉽다(사진 두 장을 자를 때만 갈리는
// 조건이라 1장 경로 테스트로는 못 잡는다).
import 'package:connection_trace_ai_flutter/core/utils/gallery_crop_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('galleryCropStepLabel', () {
    test('1장만 골랐으면 단계를 표시하지 않는다(회귀 0)', () {
      expect(galleryCropStepLabel(index: 0, totalCount: 1), isNull);
    });

    test('0장이면(방어적으로) 단계를 표시하지 않는다', () {
      expect(galleryCropStepLabel(index: 0, totalCount: 0), isNull);
    });

    test('2장이면 앞면이 1/2로 나온다', () {
      expect(
        galleryCropStepLabel(index: 0, totalCount: 2),
        '앞면 자르기 1/2',
      );
    });

    test('2장이면 뒷면이 2/2로 나온다', () {
      expect(
        galleryCropStepLabel(index: 1, totalCount: 2),
        '뒷면 자르기 2/2',
      );
    });
  });
}
