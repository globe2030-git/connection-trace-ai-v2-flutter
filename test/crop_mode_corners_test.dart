// 크롭 UX 공존안(P2-③)의 [자동 인식]/[직접 조정] 시작 귀퉁이 계산을
// 검증한다.
//
// 왜 중요한가: 세그먼트 전환·[다시 찾기]·[회전]이 전부 이 함수 하나로
// 귀퉁이를 리셋한다. 셋 중 하나가 다른 상수를 참조하기 시작하면, 회전
// 후에만 시작 위치가 어긋나는 식으로 **실기기에서만 드러나는 결함**이
// 된다(이 저장소가 추가 273에서 겪은 것과 같은 종류).
import 'package:connection_trace_ai_flutter/core/utils/crop_mode_corners.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cropStartCornersFor', () {
    test('자동 인식은 사진 가장자리에 거의 붙는다(이미 잘린 사진을 다듬는 자리)', () {
      final corners = cropStartCornersFor(CropAdjustMode.auto);
      expect(corners, kAutoModeStartCorners);
      for (final c in corners) {
        expect(c.dx, anyOf(inInclusiveRange(0.0, 0.05), inInclusiveRange(0.95, 1.0)));
        expect(c.dy, anyOf(inInclusiveRange(0.0, 0.05), inInclusiveRange(0.95, 1.0)));
      }
    });

    test('직접 조정은 더 넓게 시작한다', () {
      final corners = cropStartCornersFor(CropAdjustMode.manual);
      expect(corners, kManualModeStartCorners);
    });

    test('⚠️ 두 모드의 시작 좌표는 서로 다르다 — 섞이면 안 된다', () {
      expect(
        cropStartCornersFor(CropAdjustMode.auto),
        isNot(cropStartCornersFor(CropAdjustMode.manual)),
      );
    });

    test('📌 네 점 모두 0~1 정규 좌표 안에 있다', () {
      for (final mode in CropAdjustMode.values) {
        for (final c in cropStartCornersFor(mode)) {
          expect(c.dx, inInclusiveRange(0.0, 1.0));
          expect(c.dy, inInclusiveRange(0.0, 1.0));
        }
      }
    });
  });
}
