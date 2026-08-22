// 크롭 UX 공존안(P2-③)의 [자동 인식]/[직접 조정] 시작 귀퉁이 계산을
// 검증한다.
//
// 왜 중요한가: 세그먼트 전환·[다시 찾기]가 이 함수 하나로 귀퉁이를
// 리셋한다. 두 자리가 다른 상수를 참조하기 시작하면, 회전 후에만 시작
// 위치가 어긋나는 식으로 **실기기에서만 드러나는 결함**이 된다(이 저장소가
// 추가 273에서 겪은 것과 같은 종류).
import 'dart:ui';

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

  // 결함 399 — 정지 이미지 검출 결과를 얹은 버전.
  group('cropStartCornersForDetection', () {
    const detected = [
      Offset(0.12, 0.20),
      Offset(0.80, 0.18),
      Offset(0.82, 0.75),
      Offset(0.10, 0.77),
    ];

    test('자동 인식 + 실제로 찾음 → 찾은 자리 그대로', () {
      final corners = cropStartCornersForDetection(
        mode: CropAdjustMode.auto,
        autoDetectEnabled: true,
        detectedCorners: detected,
      );
      expect(corners, detected);
    });

    test('자동 인식 + 아직 못 찾음(검출 실패·진행 중) → 고정 상자(2~98%)가 아니라 직접 조정 자리', () {
      final corners = cropStartCornersForDetection(
        mode: CropAdjustMode.auto,
        autoDetectEnabled: true,
        detectedCorners: null,
      );
      expect(
        corners,
        kManualModeStartCorners,
        reason:
            '"이미 잘려 있어 살짝만 다듬으면 된다"는 kAutoModeStartCorners의 전제가 '
            '갤러리 원본에는 성립하지 않는다 — 못 찾았다는 배너와 상자가 어긋나면 안 된다.',
      );
      expect(corners, isNot(kAutoModeStartCorners));
    });

    test('직접 조정은 검출 여부와 무관하게 기존과 같다', () {
      for (final detectedCorners in [null, detected]) {
        expect(
          cropStartCornersForDetection(
            mode: CropAdjustMode.manual,
            autoDetectEnabled: true,
            detectedCorners: detectedCorners,
          ),
          kManualModeStartCorners,
        );
      }
    });

    test('⚠️ 회귀 방지: autoDetectEnabled가 꺼지면(촬영 경로) cropStartCornersFor와 완전히 같다', () {
      for (final mode in CropAdjustMode.values) {
        for (final detectedCorners in [null, detected]) {
          expect(
            cropStartCornersForDetection(
              mode: mode,
              autoDetectEnabled: false,
              detectedCorners: detectedCorners,
            ),
            cropStartCornersFor(mode),
          );
        }
      }
    });
  });

  // [회전] 지연 개선 — 재검출 대신 좌표 변환(rotateCornersCw90)으로 대신한다.
  // ⚠️ 이 화면은 회전×자르기 좌표계를 섞어 두 번 데인 전례가 있다(추가
  // 273·397) — 그래서 변환을 순수 함수 + 테스트로 고정한다.
  group('rotateCornersCw90', () {
    const quad = [
      Offset(0.12, 0.20),
      Offset(0.80, 0.18),
      Offset(0.82, 0.75),
      Offset(0.10, 0.77),
    ];

    test('90도 네 번 = 항등(원래 좌표·원래 이미지 크기로 돌아온다)', () {
      const originalSize = Size(4032, 3024); // 폴드 실측과 같은 가로세로비
      var corners = quad;
      var imageSize = originalSize;
      for (var i = 0; i < 4; i++) {
        corners = rotateCornersCw90(corners, imageSize);
        // 실제 화면(ManualCropView)도 회전마다 (W,H)→(H,W)로 이미지 크기가
        // 뒤바뀐 채로 다음 회전을 맞는다 — 여기서도 그 순서를 그대로 밟는다.
        imageSize = Size(imageSize.height, imageSize.width);
      }
      expect(imageSize, originalSize, reason: '네 번 돌면 이미지 크기도 원래대로 와야 한다');
      for (var i = 0; i < quad.length; i++) {
        expect(corners[i].dx, closeTo(quad[i].dx, 1e-9));
        expect(corners[i].dy, closeTo(quad[i].dy, 1e-9));
      }
    });

    test('좌상단(TL)이 회전 뒤 새 이미지의 우상단(TR) 자리로 옮겨간다 — 순서(TL·TR·BR·BL) 보존', () {
      const square = [
        Offset(0.0, 0.0), // TL
        Offset(1.0, 0.0), // TR
        Offset(1.0, 1.0), // BR
        Offset(0.0, 1.0), // BL
      ];
      final rotated = rotateCornersCw90(square, const Size(100, 100));
      // 이미지 전체가 시계로 90도 돌면, 예전 TL은 새 이미지의 TR로,
      // TR은 BR로, BR은 BL로, BL은 TL로 — 배열 순서(=같은 물리적 귀퉁이를
      // 가리키는 인덱스)는 그대로 유지된 채 값만 옮겨가야 한다. 인덱스가
      // 뒤섞이면 [회전] 뒤에 엉뚱한 손잡이가 반대편 귀퉁이를 조종하게 된다.
      expect(rotated[0], const Offset(1.0, 0.0)); // 옛 TL → 새 TR
      expect(rotated[1], const Offset(1.0, 1.0)); // 옛 TR → 새 BR
      expect(rotated[2], const Offset(0.0, 1.0)); // 옛 BR → 새 BL
      expect(rotated[3], const Offset(0.0, 0.0)); // 옛 BL → 새 TL
    });

    test('이미지 크기 (W,H)→(H,W) 스왑을 전제로 계산한다 — 실제 W·H 값과는 무관하다', () {
      // 정규 좌표(0~1) 변환이라 W·H가 서로 지워진다(함수 문서 참고). 그래도
      // 세로·가로가 전혀 다른 두 크기를 넣어 같은 결과가 나오는지 고정해
      // 둔다 — 우연이 아니라 이 함수의 계약이라는 뜻이다.
      final withPortraitSize = rotateCornersCw90(quad, const Size(3024, 4032));
      final withLandscapeSize = rotateCornersCw90(quad, const Size(1000, 500));
      expect(withPortraitSize, withLandscapeSize);
    });

    test('실제 검출 좌표 예제로 왕복(2회 회전+역방향 크기로 다시 2회)해도 원래 좌표', () {
      // cropStartCornersForDetection 테스트의 `detected`와 같은 값 — 실제
      // detectGalleryCardCorners가 돌려주는 모양(가로로 약간 기운 사각형)을
      // 흉내낸 예제다.
      const detectedExample = [
        Offset(0.12, 0.20),
        Offset(0.80, 0.18),
        Offset(0.82, 0.75),
        Offset(0.10, 0.77),
      ];
      final once = rotateCornersCw90(detectedExample, const Size(4032, 3024));
      final twice = rotateCornersCw90(once, const Size(3024, 4032));
      final thrice = rotateCornersCw90(twice, const Size(4032, 3024));
      final fourth = rotateCornersCw90(thrice, const Size(3024, 4032));
      for (var i = 0; i < detectedExample.length; i++) {
        expect(fourth[i].dx, closeTo(detectedExample[i].dx, 1e-9));
        expect(fourth[i].dy, closeTo(detectedExample[i].dy, 1e-9));
      }
    });

    test('⚠️ 회전 전 이미지 크기가 0 이하면 assert로 즉시 드러난다', () {
      expect(
        () => rotateCornersCw90(quad, Size.zero),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
