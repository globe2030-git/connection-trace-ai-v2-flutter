import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/card_rect_detector.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_photo_downscale.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_quad_geometry.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_quad_warp.dart';

/// 검출 결과를 **고르고 다듬는 규칙** 테스트.
///
/// 검출 자체는 네이티브(iOS Vision)가 하지만 **어느 후보가 명함인지 고르는
/// 것은 Dart가 한다.** 그 이유가 바로 이 파일이다 — 네이티브 코드는
/// `flutter test`로 못 돌린다.

/// 픽셀 좌표 네 점을 평평한 정규화 배열로 만든다(네이티브가 보내는 모양).
List<double> flatFromPixels(List<Offset> pixels, Size size) => [
  for (final p in pixels) ...[p.dx / size.width, p.dy / size.height],
];

/// 픽셀 좌표 네 점을 정규화해 [CardQuad]로 만든다.
CardQuad quadFromPixels(List<Offset> pixels, Size size) => sortCornersClockwise(
  pixels.map((p) => Offset(p.dx / size.width, p.dy / size.height)).toList(),
);

List<double> rectFlat({
  required double left,
  required double top,
  required double width,
  required double height,
  required Size size,
}) => flatFromPixels([
  Offset(left, top),
  Offset(left + width, top),
  Offset(left + width, top + height),
  Offset(left, top + height),
], size);

void main() {
  const buffer = Size(1920, 1080);

  group('후보 여러 개 나누기', () {
    test('두 개가 이어 붙어 오면 둘로 나눈다', () {
      final flat = [
        ...rectFlat(left: 100, top: 100, width: 800, height: 500, size: buffer),
        ...rectFlat(left: 900, top: 300, width: 640, height: 400, size: buffer),
      ];
      expect(cardQuadsFromFlat(flat).length, 2);
    });

    test('8로 나누어떨어지지 않으면 통째로 버린다', () {
      // 반쯤 읽으면 좌표가 밀려 엉뚱한 사각형이 만들어진다.
      expect(cardQuadsFromFlat([0.1, 0.2, 0.3, 0.4, 0.5]), isEmpty);
      expect(cardQuadsFromFlat(List.filled(12, 0.5)), isEmpty);
    });

    test('빈 배열·null은 빈 목록', () {
      expect(cardQuadsFromFlat(null), isEmpty);
      expect(cardQuadsFromFlat(const []), isEmpty);
    });

    test('한 후보가 망가져도 나머지는 살린다', () {
      final good = rectFlat(
        left: 100,
        top: 100,
        width: 800,
        height: 500,
        size: buffer,
      );
      final broken = List<double>.filled(8, double.nan);
      expect(cardQuadsFromFlat([...broken, ...good]).length, 1);
    });
  });

  group('어느 후보가 명함인가', () {
    test('명함 비율인 것만 고른다 — 큰 사각형이라도 비율이 틀리면 버린다', () {
      // 실제 상황: 책상 모서리(길쭉한 사각형)와 명함이 함께 잡힌다.
      //
      // ⚠️ 예전에는 여기에 1880×1040(비율 1.81)을 썼는데, **그건 표준 명함
      // 비율과 같다.** 가로세로비 범위를 실측에 맞춰 넓히면서 이 가짜
      // "책상"이 명함으로 판정되게 됐다 — 표본을 실제로 명함이 아닌
      // 모양으로 바꾼다.
      final desk = rectFlat(
        left: 20,
        top: 150,
        width: 1880,
        height: 620,
        size: buffer,
      );
      final card = rectFlat(
        left: 500,
        top: 300,
        width: 800,
        height: 500,
        size: buffer,
      );
      final quads = cardQuadsFromFlat([...desk, ...card]);
      final best = pickBestCardQuad(quads, buffer);

      expect(best, isNotNull);
      expect(cardQuadAspectRatio(best!, buffer), closeTo(1.6, 1e-6));
    });

    test('명함이 여럿이면 큰 쪽(사용자가 든 것)을 고른다', () {
      final far = rectFlat(
        left: 60,
        top: 60,
        width: 480,
        height: 300,
        size: buffer,
      );
      final near = rectFlat(
        left: 700,
        top: 300,
        width: 960,
        height: 600,
        size: buffer,
      );
      final best = pickBestCardQuad(
        cardQuadsFromFlat([...far, ...near]),
        buffer,
      );
      expect(best, isNotNull);
      expect(
        cardQuadAreaFraction(best!),
        closeTo(960 * 600 / (1920 * 1080), 1e-9),
      );
    });

    test('통과한 것이 없으면 억지로 고르지 않는다', () {
      // 명함이 아닌 것을 찍는 것보다 안 찍히는 쪽이 낫다 — 셔터는
      // 언제든 직접 누를 수 있다.
      final monitor = rectFlat(
        left: 100,
        top: 100,
        width: 1000,
        height: 900,
        size: buffer,
      );
      expect(pickBestCardQuad(cardQuadsFromFlat(monitor), buffer), isNull);
    });
  });

  group('네이티브 응답 → 검출 결과', () {
    test('세로로 든 폰(센서 90°)에서 좌표가 화면 방향으로 돌아온다', () {
      final flat = rectFlat(
        left: 500,
        top: 300,
        width: 800,
        height: 500,
        size: buffer,
      );
      final detection = detectionFromFlat(
        flat,
        bufferSize: buffer,
        quarterTurns: 1,
      );

      expect(detection, isNotNull);
      expect(detection!.isCardLike, isTrue);
      // 90° 돌리면 표시 기준 크기는 가로세로가 뒤바뀐다.
      expect(detection.displaySize, const Size(1080, 1920));
    });

    test('회전이 0이면 크기가 그대로다', () {
      final detection = detectionFromFlat(
        rectFlat(left: 500, top: 300, width: 800, height: 500, size: buffer),
        bufferSize: buffer,
        quarterTurns: 0,
      );
      expect(detection!.displaySize, buffer);
    });

    test('⚠️ 떨어진 이유를 남긴다 — 왜 안 잡히는지 추측하지 않기 위해', () {
      // 명함 두 장을 한 덩어리로 잡은 경우(아이폰 A안에서 실제로 났던 문제).
      final detection = detectionFromFlat(
        rectFlat(left: 60, top: 300, width: 1800, height: 560, size: buffer),
        bufferSize: buffer,
        quarterTurns: 0,
      );

      expect(detection, isNotNull);
      expect(detection!.isCardLike, isFalse);
      expect(detection.verdict, CardShapeVerdict.aspectOutOfRange);
    });

    test('후보가 하나도 없으면 null', () {
      expect(
        detectionFromFlat(const [], bufferSize: buffer, quarterTurns: 1),
        isNull,
      );
      expect(
        detectionFromFlat(null, bufferSize: buffer, quarterTurns: 1),
        isNull,
      );
    });

    test('떨어진 후보 중에서는 가장 큰 것을 남긴다', () {
      final small = rectFlat(
        left: 0,
        top: 0,
        width: 300,
        height: 280,
        size: buffer,
      );
      // 둘 다 명함이 아니다 — 작은 것은 너무 작고, 큰 것은 정사각형에 가깝다.
      final large = rectFlat(
        left: 400,
        top: 100,
        width: 1000,
        height: 900,
        size: buffer,
      );
      final detection = detectionFromFlat(
        [...small, ...large],
        bufferSize: buffer,
        quarterTurns: 0,
      );
      expect(detection!.isCardLike, isFalse);
      expect(
        cardQuadAreaFraction(detection.quad),
        closeTo(1000 * 900 / (1920 * 1080), 1e-9),
      );
    });
  });

  group('⚠️ 실측으로 고친 것 — 프레임 모양까지 봐야 한다 (2026-08-16)', () {
    test('아이폰이 준 세로 프레임(3024×4032)은 돌리지 않는다', () {
      // 센서 방향만 보고 90° 돌렸다가 테두리가 옆으로 누울 뻔했다.
      expect(
        quarterTurnsForFrame(
          sensorOrientation: 90,
          frameWidth: 3024,
          frameHeight: 4032,
        ),
        0,
      );
    });

    test('가로로 누워 오는 프레임은 센서 방향대로 돌린다', () {
      expect(
        quarterTurnsForFrame(
          sensorOrientation: 90,
          frameWidth: 1920,
          frameHeight: 1080,
        ),
        1,
      );
      expect(
        quarterTurnsForFrame(
          sensorOrientation: 270,
          frameWidth: 1920,
          frameHeight: 1080,
        ),
        3,
      );
    });

    test('정사각형이면 가로로 보고 센서 방향을 따른다', () {
      expect(
        quarterTurnsForFrame(
          sensorOrientation: 90,
          frameWidth: 1000,
          frameHeight: 1000,
        ),
        1,
      );
    });

    test('⚠️ 가이드에 꽉 찬 명함이 tooSmall로 떨어지면 안 된다', () {
      // 실측(아이폰 캡처 1206×2622): 가이드 상자가 화면의 약 10.9%,
      // 프레임(3024×4032) 기준으로 환산하면 약 6.7%였다. 처음 잡았던
      // 최소 넓이 15%는 **계산이었고 실물이 그 절반 이하**였다 —
      // 실기기에서 명함이 전부 떨어졌다.
      const frame = Size(3024, 4032);
      // 프레임의 6.7%를 차지하는 명함 비율(1.6)의 사각형.
      const w = 1000.0;
      const h = 625.0; // 1000 × 625 = 625,000 = 3024×4032의 5.1%
      final quad = quadFromPixels([
        const Offset(900, 1600),
        const Offset(900 + w, 1600),
        const Offset(900 + w, 1600 + h),
        const Offset(900, 1600 + h),
      ], frame);

      expect(cardQuadAreaFraction(quad), lessThan(0.07));
      expect(judgeCardShape(quad, frame), CardShapeVerdict.ok);
    });

    test('그래도 배경의 자잘한 사각형은 여전히 떨어진다', () {
      const frame = Size(3024, 4032);
      final tiny = quadFromPixels(const [
        Offset(100, 100),
        Offset(420, 100),
        Offset(420, 300),
        Offset(100, 300),
      ], frame);
      expect(judgeCardShape(tiny, frame), CardShapeVerdict.tooSmall);
    });
  });

  group('센서 방향 → 회전 횟수', () {
    test('흔한 후면 카메라(90°)는 한 번 돈다', () {
      expect(quarterTurnsForSensor(90), 1);
    });

    test('0·180·270도 맞다', () {
      expect(quarterTurnsForSensor(0), 0);
      expect(quarterTurnsForSensor(180), 2);
      expect(quarterTurnsForSensor(270), 3);
    });

    test('범위를 벗어난 값도 접힌다', () {
      expect(quarterTurnsForSensor(450), 1);
      expect(quarterTurnsForSensor(-90), 3);
    });
  });

  group('테두리 유지 — 깜빡임 막기', () {
    final detection = detectionFromFlat(
      rectFlat(left: 500, top: 300, width: 800, height: 500, size: buffer),
      bufferSize: buffer,
      quarterTurns: 0,
    )!;
    final start = DateTime(2026, 8, 16, 22);

    test('검출이 한두 프레임 비어도 테두리가 남는다', () {
      final hold = CardRectHold(
        holdDuration: const Duration(milliseconds: 400),
      );
      hold.update(detection, start);
      hold.update(null, start.add(const Duration(milliseconds: 125)));
      expect(
        hold.visibleAt(start.add(const Duration(milliseconds: 250))),
        isNotNull,
      );
    });

    test('유지 시간이 지나면 놓는다', () {
      final hold = CardRectHold(
        holdDuration: const Duration(milliseconds: 400),
      );
      hold.update(detection, start);
      expect(
        hold.visibleAt(start.add(const Duration(milliseconds: 401))),
        isNull,
      );
    });

    test('아무것도 안 들어왔으면 비어 있다', () {
      final hold = CardRectHold();
      expect(hold.visibleAt(start), isNull);
    });

    test('지우면 즉시 비워진다 — 화면을 닫거나 다시 찍을 때', () {
      final hold = CardRectHold();
      hold.update(detection, start);
      hold.clear();
      expect(hold.visibleAt(start), isNull);
    });
  });

  group('자를 좌표 다듬기', () {
    const corners = [
      Offset(100, 100),
      Offset(900, 100),
      Offset(900, 600),
      Offset(100, 600),
    ];

    test('⚠️ 가장자리 글자가 깎이지 않게 바깥으로 조금 넓힌다', () {
      // 크롭 여유를 없앴다가 "양쪽 끝 글씨가 30~40% 잘린다"는 제보를
      // 받은 전례가 있다(2026-08-14).
      final expanded = expandCorners(corners, margin: 0.04);
      final width = expanded[1].dx - expanded[0].dx;
      expect(width, greaterThan(800));
      expect(width, closeTo(800 * 1.04, 1e-6));
    });

    test('넓혀도 가운데는 그대로다', () {
      final expanded = expandCorners(corners);
      final cx =
          expanded.map((c) => c.dx).reduce((a, b) => a + b) / expanded.length;
      expect(cx, closeTo(500, 1e-6));
    });

    test('이미지 밖으로 나간 좌표는 안으로 민다 — 검은 띠 방지', () {
      final clamped = clampCornersToImage(const [
        Offset(-40, -30),
        Offset(2000, -30),
        Offset(2000, 1200),
        Offset(-40, 1200),
      ], const Size(1920, 1080));

      expect(clamped[0], const Offset(0, 0));
      expect(clamped[2], const Offset(1919, 1079));
    });

    test('평평한 배열로 펴고 다시 읽어도 같다', () {
      final flat = cornersToFlat(corners);
      expect(flat.length, 8);
      expect(flat[0], 100);
      expect(flat[7], 600);
    });
  });

  group('⚠️ 촬영 거리가 해상도를 정한다 — 실기기 실측 (2026-08-16)', () {
    // 아이폰 실측 2건. **기존 경로에는 없던 성질**이다 — 가이드 상자를
    // 고정 크기로 자르던 때는 거리와 무관하게 2,000px대가 나왔다.
    const nearLongEdge = 1786; // 가까이 — 1786×1005
    const farLongEdge = 993; // 멀리  — 993×559

    test('가까이 찍으면 축소 임계를 넘는다', () {
      expect(needsDownscale(1786, 1005), isTrue);
      expect(nearLongEdge, greaterThan(kCardPhotoMaxLongSide));
    });

    test('⚠️ 멀리 찍으면 임계 아래로 떨어진다 — 축소를 건너뛴다', () {
      expect(needsDownscale(993, 559), isFalse);
      expect(farLongEdge, lessThan(kCardPhotoMaxLongSide));
    });

    test('멀리 찍은 것은 문서 스캔 표준(300dpi)에 못 미친다', () {
      // 명함 긴 변 90mm = 3.543인치.
      const cardLongSideInches = 90 / 25.4;
      expect(nearLongEdge / cardLongSideInches, greaterThan(300));
      expect(farLongEdge / cardLongSideInches, lessThan(300));
    });

    test('두 값 모두 명함 비율(1.8 근처)이다 — 명함만 잘랐다는 뜻', () {
      expect(1786 / 1005, closeTo(1.78, 0.02));
      expect(993 / 559, closeTo(1.78, 0.02));
    });
  });

  group('결과물 크기와 축소 임계', () {
    test('⚠️ 실측 인계값 — A안 크롭은 둘 다 1,600을 넘었다', () {
      // 2026-08-16 실기기 측정(안드로이드 A안): 2039×1115, 3315×1820.
      // B′도 같은 촬영 거리라면 비슷한 크기가 나와야 한다. 여기서
      // 고정하는 것은 "검출 크기를 그대로 쓴다"는 규칙이다.
      final first = perspectiveOutputSize(const [
        Offset(0, 0),
        Offset(2039, 0),
        Offset(2039, 1115),
        Offset(0, 1115),
      ]);
      expect(first.width, 2039);
      expect(first.height, 1115);
      expect(first.width > 1600, isTrue);

      // 비율도 명함 규격(1.8)에 붙는다 — 명함 자체를 잘랐다는 뜻.
      expect(2039 / 1115, closeTo(1.83, 0.01));
    });

    test('세로로 선 결과물은 눕힌다는 규칙을 크기로 확인', () {
      // uprightCard는 이미지가 필요해 여기서는 크기 계산만 본다.
      final portrait = perspectiveOutputSize(const [
        Offset(0, 0),
        Offset(1115, 0),
        Offset(1115, 2039),
        Offset(0, 2039),
      ]);
      expect(portrait.height, greaterThan(portrait.width));
    });
  });
}
