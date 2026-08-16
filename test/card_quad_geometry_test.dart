import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/card_quad_geometry.dart';

/// 명함 자동 테두리 검출(B′)의 **기하 계산** 테스트.
///
/// 검출 자체(iOS Vision · Android OpenCV)는 실기기에서만 확인할 수 있지만,
/// **검출 결과를 화면·사진에 옮기는 계산은 여기서 잡을 수 있다.** 이쪽이
/// 틀리면 테두리가 엉뚱한 곳에 그려지거나 크롭이 대각선으로 뒤집히는데,
/// 둘 다 실기기까지 가야 보이는 종류의 결함이다.

/// 픽셀 좌표를 정규화 좌표로 바꿔 [CardQuad]를 만드는 도우미.
CardQuad quadFromPixels(List<Offset> pixels, Size size) => sortCornersClockwise(
  pixels.map((p) => Offset(p.dx / size.width, p.dy / size.height)).toList(),
);

void main() {
  group('귀퉁이 정렬', () {
    test('순서가 뒤섞여 들어와도 시계 방향으로 세운다', () {
      final quad = sortCornersClockwise(const [
        Offset(0.8, 0.7), // 오른쪽 아래
        Offset(0.2, 0.2), // 왼쪽 위
        Offset(0.2, 0.7), // 왼쪽 아래
        Offset(0.8, 0.2), // 오른쪽 위
      ]);

      expect(quad.topLeft, const Offset(0.2, 0.2));
      expect(quad.topRight, const Offset(0.8, 0.2));
      expect(quad.bottomRight, const Offset(0.8, 0.7));
      expect(quad.bottomLeft, const Offset(0.2, 0.7));
    });

    test('45°에 가깝게 기울어도 뒤바뀌지 않는다', () {
      // x+y가 가장 작은 점을 왼쪽 위로 잡는 흔한 방법이 깨지는 배치.
      // 마름모꼴로 세워도 시계 방향 순서 자체는 유지돼야 한다.
      final quad = sortCornersClockwise(const [
        Offset(0.5, 0.1),
        Offset(0.9, 0.5),
        Offset(0.5, 0.9),
        Offset(0.1, 0.5),
      ]);

      // 시계 방향으로 돌면서 이웃한 두 점이 서로 마주보는 꼭짓점이 아니어야 한다.
      final corners = quad.corners;
      for (var i = 0; i < 4; i++) {
        final a = corners[i];
        final b = corners[(i + 1) % 4];
        // 마주보는 꼭짓점끼리는 거리가 0.8, 이웃은 약 0.566이다.
        expect((a - b).distance, lessThan(0.7));
      }
    });

    test('평평한 배열을 그대로 받아 정렬한다', () {
      final quad = cardQuadFromFlat([0.8, 0.7, 0.2, 0.2, 0.2, 0.7, 0.8, 0.2]);
      expect(quad, isNotNull);
      expect(quad!.topLeft, const Offset(0.2, 0.2));
    });

    test('길이가 8이 아니거나 NaN이 섞이면 버린다', () {
      expect(cardQuadFromFlat(null), isNull);
      expect(cardQuadFromFlat([0.1, 0.2, 0.3]), isNull);
      expect(
        cardQuadFromFlat([double.nan, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]),
        isNull,
      );
    });
  });

  group('버퍼 → 표시 회전', () {
    final quad = sortCornersClockwise(const [
      Offset(0.1, 0.2),
      Offset(0.6, 0.2),
      Offset(0.6, 0.5),
      Offset(0.1, 0.5),
    ]);

    test('0회전은 그대로', () {
      expect(rotateQuadClockwise(quad, 0), quad);
    });

    test('네 번 돌리면 제자리로 온다', () {
      var rotated = quad;
      for (var i = 0; i < 4; i++) {
        rotated = rotateQuadClockwise(rotated, 1);
      }
      for (var i = 0; i < 4; i++) {
        expect(rotated.corners[i].dx, closeTo(quad.corners[i].dx, 1e-9));
        expect(rotated.corners[i].dy, closeTo(quad.corners[i].dy, 1e-9));
      }
    });

    test('시계 방향 90°에서 왼쪽 위가 오른쪽 위로 간다', () {
      // 버퍼의 (0.1, 0.2)는 90° 돌리면 (1-0.2, 0.1) = (0.8, 0.1)이 된다.
      final rotated = rotateQuadClockwise(quad, 1);
      expect(rotated.topRight.dx, closeTo(0.8, 1e-9));
      expect(rotated.topRight.dy, closeTo(0.1, 1e-9));
    });

    test('음수·4 이상도 같은 결과로 접힌다', () {
      expect(rotateQuadClockwise(quad, 5), rotateQuadClockwise(quad, 1));
      expect(rotateQuadClockwise(quad, -1), rotateQuadClockwise(quad, 3));
    });
  });

  group('cover 방식으로 보이는 영역', () {
    test('이미지가 화면보다 가로로 길면 좌우가 잘린다', () {
      // 4:3 이미지를 9:16 화면에 cover로 채우면 좌우가 크게 잘린다.
      final visible = visibleImageRect(
        const Size(4000, 3000),
        const Size(900, 1600),
      );
      expect(visible.height, 3000);
      expect(visible.width, closeTo(3000 * 900 / 1600, 1e-6));
      expect(visible.left, closeTo((4000 - visible.width) / 2, 1e-6));
      expect(visible.top, 0);
    });

    test('이미지가 화면보다 세로로 길면 위아래가 잘린다', () {
      final visible = visibleImageRect(
        const Size(1000, 3000),
        const Size(1000, 1000),
      );
      expect(visible.width, 1000);
      expect(visible.height, 1000);
      expect(visible.top, 1000);
    });

    test('비율이 같으면 아무것도 안 잘린다', () {
      final visible = visibleImageRect(
        const Size(1080, 1920),
        const Size(540, 960),
      );
      expect(visible, const Rect.fromLTWH(0, 0, 1080, 1920));
    });
  });

  group('가시 좌표는 프리뷰와 촬영본을 잇는다', () {
    // 프리뷰 버퍼와 촬영본은 해상도가 다르지만 비율은 같다 — 실제 상황.
    const screen = Size(900, 1600);
    const previewSize = Size(1280, 720);
    const photoSize = Size(4032, 2268);

    test('같은 장면의 같은 위치는 해상도가 달라도 같은 가시 좌표가 된다', () {
      // 프리뷰 한가운데의 점.
      final displayQuad = sortCornersClockwise(const [
        Offset(0.4, 0.4),
        Offset(0.6, 0.4),
        Offset(0.6, 0.6),
        Offset(0.4, 0.6),
      ]);

      final fromPreview = displayQuadToVisibleQuad(
        displayQuad,
        previewSize,
        screen,
      );
      final fromPhoto = displayQuadToVisibleQuad(
        displayQuad,
        photoSize,
        screen,
      );

      for (var i = 0; i < 4; i++) {
        expect(
          fromPreview.corners[i].dx,
          closeTo(fromPhoto.corners[i].dx, 1e-9),
        );
        expect(
          fromPreview.corners[i].dy,
          closeTo(fromPhoto.corners[i].dy, 1e-9),
        );
      }
    });

    test('가시 좌표 → 촬영본 픽셀 → 다시 가시 좌표가 제자리로 온다', () {
      final visibleQuad = sortCornersClockwise(const [
        Offset(0.2, 0.3),
        Offset(0.8, 0.3),
        Offset(0.8, 0.7),
        Offset(0.2, 0.7),
      ]);

      final pixels = visibleQuadToImagePixels(visibleQuad, photoSize, screen);
      final visible = visibleImageRect(photoSize, screen);
      for (var i = 0; i < 4; i++) {
        final backX = (pixels[i].dx - visible.left) / visible.width;
        final backY = (pixels[i].dy - visible.top) / visible.height;
        expect(backX, closeTo(visibleQuad.corners[i].dx, 1e-9));
        expect(backY, closeTo(visibleQuad.corners[i].dy, 1e-9));
      }
    });

    test('화면 밖으로 걸친 점은 0~1을 벗어난 채로 남는다', () {
      // 잘라 버리면 "가장자리에 걸쳤다"를 부르는 쪽이 알 수 없다.
      final displayQuad = sortCornersClockwise(const [
        Offset(0.01, 0.4),
        Offset(0.2, 0.4),
        Offset(0.2, 0.6),
        Offset(0.01, 0.6),
      ]);
      final result = displayQuadToVisibleQuad(displayQuad, previewSize, screen);
      expect(result.topLeft.dx, lessThan(0));
    });
  });

  group('명함처럼 생겼는지 판정', () {
    const buffer = Size(1920, 1080);

    CardQuad cardAt({
      required double left,
      required double top,
      required double width,
      required double height,
    }) => quadFromPixels([
      Offset(left, top),
      Offset(left + width, top),
      Offset(left + width, top + height),
      Offset(left, top + height),
    ], buffer);

    test('⚠️ 표준 명함(90×50 = 1.80)이 통과해야 한다', () {
      // 스펙이 적어 둔 범위가 1.3~1.7이었는데 **표준 명함 1.8이 그 밖**이라
      // 실기기에서 명함이 전부 aspectOutOfRange로 떨어졌다.
      final quad = cardAt(left: 200, top: 200, width: 1440, height: 800);
      expect(cardQuadAspectRatio(quad, buffer), closeTo(1.8, 1e-6));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('⚠️ 앞 세션 실측값(1.828 · 1.821)이 통과해야 한다', () {
      // A안 크롭 2건의 실측 비율. 이 숫자는 인계로 이미 우리 손에 있었는데
      // 스펙 범위와 어긋난다는 것을 대조하지 않았다.
      for (final ratio in [1.828, 1.821]) {
        const height = 800.0;
        final quad = cardAt(
          left: 100,
          top: 150,
          width: height * ratio,
          height: height,
        );
        expect(cardQuadAspectRatio(quad, buffer), closeTo(ratio, 1e-6));
        expect(
          judgeCardShape(quad, buffer),
          CardShapeVerdict.ok,
          reason: '실측 비율 $ratio이 떨어지면 실기기에서 명함이 안 잡힌다',
        );
      }
    });

    test('신용카드 규격(1.586)도 통과한다', () {
      final quad = cardAt(left: 300, top: 200, width: 1269, height: 800);
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('명함 한 장(비율 1.6)은 통과한다', () {
      final quad = cardAt(left: 300, top: 150, width: 1200, height: 750);
      expect(cardQuadAspectRatio(quad, buffer), closeTo(1.6, 1e-6));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('⚠️ 명함 여러 장을 한 덩어리로 잡으면 떨어진다', () {
      // 아이폰 A안(VisionKit)에서 실제로 났던 문제. 나란히 놓인 두 장을
      // 하나의 큰 사각형으로 잡으면 가로세로비가 3 근처가 된다.
      final quad = cardAt(left: 60, top: 300, width: 1800, height: 560);
      expect(cardQuadAspectRatio(quad, buffer), greaterThan(3));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.aspectOutOfRange);
    });

    test('정사각형에 가까운 것(포스트잇·모니터)은 떨어진다', () {
      final quad = cardAt(left: 500, top: 100, width: 800, height: 760);
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.aspectOutOfRange);
    });

    test('너무 작으면 배경의 다른 물건으로 보고 떨어뜨린다', () {
      // ⚠️ 기준을 15% → 2%로 낮췄다(2026-08-16 실측 — 가이드에 꽉 찬 명함이
      // 프레임의 6.7%였다). 그래서 "작다"의 뜻도 그만큼 작아졌다.
      final quad = cardAt(left: 100, top: 100, width: 240, height: 150);
      expect(cardQuadAreaFraction(quad), lessThan(0.02));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.tooSmall);
    });

    test('⚠️ 예전 기준(15%)이면 떨어졌을 크기가 이제는 통과한다', () {
      // 실기기에서 명함이 전부 tooSmall로 떨어진 것이 이 자리다.
      final quad = cardAt(left: 400, top: 300, width: 480, height: 300);
      final area = cardQuadAreaFraction(quad);
      expect(area, lessThan(0.15));
      expect(area, greaterThan(0.02));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('사각형이 무너지면 떨어진다', () {
      // 한 귀퉁이만 크게 어긋난 사다리꼴 — 그림자나 무늬를 잡은 경우.
      final quad = quadFromPixels(const [
        Offset(300, 150),
        Offset(1500, 150),
        Offset(1100, 900),
        Offset(300, 900),
      ], buffer);
      expect(cardQuadMaxCornerDeviation(quad, buffer), greaterThan(25));
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.notRectangular);
    });

    test('비스듬히 찍어 살짝 기운 명함은 통과한다', () {
      // 실사용에서 명함을 완전히 정면으로 잡는 일은 드물다. 여기서
      // 떨어지면 "잘 안 잡힌다"는 제보가 된다.
      final quad = quadFromPixels(const [
        Offset(320, 190),
        Offset(1500, 150),
        Offset(1520, 900),
        Offset(340, 940),
      ], buffer);
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('세로로 세운 명함도 통과한다(긴 변 기준으로 재기 때문)', () {
      // 이 앱은 명함을 90° 돌려 세로 가이드에 넣게 안내한다.
      final quad = cardAt(left: 700, top: 60, width: 600, height: 960);
      expect(judgeCardShape(quad, buffer), CardShapeVerdict.ok);
    });

    test('넓이 비율은 정규화 좌표 그대로 계산된다', () {
      final quad = cardAt(left: 0, top: 0, width: 960, height: 540);
      expect(cardQuadAreaFraction(quad), closeTo(0.25, 1e-9));
    });
  });

  group('원근 보정 행렬', () {
    test('네 귀퉁이가 정확히 맞아떨어진다', () {
      final source = const [
        Offset(120, 80),
        Offset(900, 40),
        Offset(960, 620),
        Offset(80, 660),
      ];
      final destination = const [
        Offset(0, 0),
        Offset(800, 0),
        Offset(800, 500),
        Offset(0, 500),
      ];

      final matrix = perspectiveTransform(source, destination);
      expect(matrix, isNotNull);

      for (var i = 0; i < 4; i++) {
        final mapped = applyPerspective(matrix!, destination[i]);
        expect(mapped.dx, closeTo(source[i].dx, 1e-6));
        expect(mapped.dy, closeTo(source[i].dy, 1e-6));
      }
    });

    test('직사각형끼리면 단순 확대·이동이 된다', () {
      final matrix = perspectiveTransform(
        const [
          Offset(100, 200),
          Offset(300, 200),
          Offset(300, 400),
          Offset(100, 400),
        ],
        const [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
      );
      expect(matrix, isNotNull);
      final center = applyPerspective(matrix!, const Offset(50, 50));
      expect(center.dx, closeTo(200, 1e-6));
      expect(center.dy, closeTo(300, 1e-6));
    });

    test('네 점이 한 줄에 놓이면 null을 돌려준다', () {
      // 부르는 쪽이 기존 크롭으로 되돌아갈 수 있어야 한다.
      final matrix = perspectiveTransform(
        const [Offset(0, 0), Offset(100, 0), Offset(200, 0), Offset(300, 0)],
        const [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)],
      );
      expect(matrix, isNull);
    });
  });

  group('원근 보정 결과 크기', () {
    test('네 변 중 긴 쪽을 택해 잘리지 않게 한다', () {
      final size = perspectiveOutputSize(const [
        Offset(0, 0),
        Offset(1000, 20),
        Offset(1040, 640),
        Offset(10, 600),
      ]);
      // 위 변 ≈1000.2, 아래 변 ≈1030.8 → 긴 쪽
      expect(size.width, greaterThanOrEqualTo(1030));
      expect(size.height, greaterThanOrEqualTo(600));
    });

    test('⚠️ 축소 임계(1,600)와 만나는 자리 — 검출 크기를 그대로 쓴다', () {
      // 임의의 값으로 늘리거나 줄이지 않는다는 것을 고정한다. 여기서
      // 값을 손대면 저장본 크기가 바뀌어 무료 200장 한도 근거가 흔들린다.
      const width = 2400.0;
      const height = 1500.0;
      final size = perspectiveOutputSize(const [
        Offset(0, 0),
        Offset(width, 0),
        Offset(width, height),
        Offset(0, height),
      ]);
      expect(size.width, width);
      expect(size.height, height);
    });

    test('찌그러진 입력에도 최소 1px은 보장한다', () {
      final size = perspectiveOutputSize(const [
        Offset(10, 10),
        Offset(10, 10),
        Offset(10, 10),
        Offset(10, 10),
      ]);
      expect(size.width, greaterThanOrEqualTo(1));
      expect(size.height, greaterThanOrEqualTo(1));
    });
  });

  group('회전과 판정이 함께 돌아간다', () {
    test('세로로 든 폰에서 온 버퍼를 돌려도 명함으로 판정된다', () {
      // 카메라 버퍼는 가로로 눕혀서 온다(1920×1080). 폰은 세로다.
      const buffer = Size(1920, 1080);
      final bufferQuad = quadFromPixels(const [
        Offset(400, 200),
        Offset(1520, 200),
        Offset(1520, 900),
        Offset(400, 900),
      ], buffer);

      expect(judgeCardShape(bufferQuad, buffer), CardShapeVerdict.ok);

      // 90° 돌리면 표시 크기는 가로세로가 뒤바뀐다.
      final displayQuad = rotateQuadClockwise(bufferQuad, 1);
      const display = Size(1080, 1920);
      expect(judgeCardShape(displayQuad, display), CardShapeVerdict.ok);
      expect(
        cardQuadAspectRatio(displayQuad, display),
        closeTo(cardQuadAspectRatio(bufferQuad, buffer), 1e-6),
      );
    });

    test('회전해도 넓이 비율은 그대로다', () {
      final quad = sortCornersClockwise(const [
        Offset(0.2, 0.25),
        Offset(0.75, 0.25),
        Offset(0.75, 0.7),
        Offset(0.2, 0.7),
      ]);
      final area = cardQuadAreaFraction(quad);
      for (var turns = 1; turns < 4; turns++) {
        expect(
          cardQuadAreaFraction(rotateQuadClockwise(quad, turns)),
          closeTo(area, 1e-9),
        );
      }
    });
  });

  group('실제 각도 계산이 맞는지', () {
    test('직사각형의 각 어긋남은 0이다', () {
      const buffer = Size(1000, 1000);
      final quad = quadFromPixels(const [
        Offset(100, 100),
        Offset(900, 100),
        Offset(900, 600),
        Offset(100, 600),
      ], buffer);
      expect(cardQuadMaxCornerDeviation(quad, buffer), closeTo(0, 1e-6));
    });

    test('평행사변형은 기운 각도만큼 어긋난다', () {
      const buffer = Size(1000, 1000);
      const shift = 200.0;
      final quad = quadFromPixels(const [
        Offset(100 + shift, 100),
        Offset(900 + shift, 100),
        Offset(900, 600),
        Offset(100, 600),
      ], buffer);
      final expected = math.atan2(shift, 500) * 180 / math.pi;
      expect(cardQuadMaxCornerDeviation(quad, buffer), closeTo(expected, 0.5));
    });
  });
}
