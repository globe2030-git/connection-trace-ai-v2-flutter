// 갤러리 정지 이미지에 실제 테두리 검출을 돌리는 [detectGalleryCardCorners]를
// 검증한다(결함 399).
//
// 왜 중요한가: 398이 [자동 인식] 세그먼트·배너를 열어 뒀는데 실제로는 검출이
// 한 번도 돌지 않았다 — 시작 상자가 사진 거의 전체(2~98%)로 고정돼 있었을
// 뿐이다(실측: 명함이 상자의 69%·55%만 차지, 그대로 자르면 배경 51.2%가
// 섞여 들어감). 이 파일은 "정말 찾는지"·"못 찾으면 정직하게 실패로
// 보고하는지"를 파일 IO까지 포함해 검증한다 — 카메라 경로가 이미 검증한
// `detectCardQuadsWithOpenCv` 자체(닫기 연산·가장자리 제외·isCardLike)는
// 다시 재지 않는다(`card_rect_close_gaps_test.dart`가 이미 잰다).
import 'dart:io';
import 'dart:math';

import 'package:connection_trace_ai_flutter/core/utils/gallery_auto_detect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// `card_rect_close_gaps_test.dart`의 `texturedScene`과 같은 자리·같은
/// 숫자를 쓴다 — 그 값이 "닫기 연산이 있어야만 잡히는" 패턴임을 이미
/// 검증했으므로, 여기서는 같은 장면을 **PNG 파일로 왕복**시켜도 그 검출이
/// 살아남는지만 새로 확인한다.
img.Image texturedCardScene({
  required int width,
  required int height,
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final rand = Random(20260822);
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inCard = x >= left && x < right && y >= top && y < bottom;
      final base = inCard ? 185 : 112;
      final noise = inCard ? rand.nextInt(11) - 5 : rand.nextInt(121) - 60;
      final v = (base + noise).clamp(0, 255);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  group('detectGalleryCardCorners', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gallery_auto_detect_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('무늬 있는 배경 위 명함을 실제로 찾는다 — PNG 파일 왕복 포함', () {
      const w = 1000, h = 750;
      const left = 165, top = 156, right = 866, bottom = 520;
      final scene = texturedCardScene(
        width: w,
        height: h,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      );
      final path = '${tempDir.path}/card.png';
      File(path).writeAsBytesSync(img.encodePng(scene));

      final result = detectGalleryCardCorners(GalleryAutoDetectRequest(path));

      expect(result.success, isTrue);
      final flat = result.cornersFlat;
      expect(flat, isNotNull);
      expect(flat!.length, 8);

      final xs = <double>[];
      final ys = <double>[];
      for (var i = 0; i < 8; i += 2) {
        xs.add(flat[i] * w);
        ys.add(flat[i + 1] * h);
      }
      expect(xs.reduce(min), closeTo(left, 40));
      expect(xs.reduce(max), closeTo(right, 40));
      expect(ys.reduce(min), closeTo(top, 40));
      expect(ys.reduce(max), closeTo(bottom, 40));

      // ⚠️ 이게 결함 399의 핵심 회귀 방지선이다 — 예전에는 검출이 안 돌아
      // 상자가 사진의 2~98%(거의 전체)로 고정돼 있었다. 진짜 검출이라면
      // 찾은 상자가 사진 전체를 덮지 않는다.
      final areaFraction =
          ((xs.reduce(max) - xs.reduce(min)) *
              (ys.reduce(max) - ys.reduce(min))) /
          (w * h);
      expect(areaFraction, lessThan(0.9));
    });

    test('명함이 없는 균일한 사진은 정직하게 실패로 보고한다', () {
      final blank = img.Image(width: 800, height: 600);
      for (var y = 0; y < blank.height; y++) {
        for (var x = 0; x < blank.width; x++) {
          blank.setPixelRgb(x, y, 128, 128, 128);
        }
      }
      final path = '${tempDir.path}/blank.png';
      File(path).writeAsBytesSync(img.encodePng(blank));

      final result = detectGalleryCardCorners(GalleryAutoDetectRequest(path));

      expect(result.success, isFalse);
      expect(result.cornersFlat, isNull);
    });

    test('이미지가 아닌 파일(디코드 실패)도 던지지 않고 실패로 보고한다', () {
      final path = '${tempDir.path}/not_an_image.png';
      File(path).writeAsBytesSync([1, 2, 3, 4, 5]);

      final result = detectGalleryCardCorners(GalleryAutoDetectRequest(path));

      expect(result.success, isFalse);
      expect(result.cornersFlat, isNull);
    });

    test('존재하지 않는 경로도 던지지 않고 실패로 보고한다', () {
      final result = detectGalleryCardCorners(
        GalleryAutoDetectRequest('${tempDir.path}/does_not_exist.png'),
      );

      expect(result.success, isFalse);
      expect(result.cornersFlat, isNull);
    });

    test('큰 사진은 상한(kGalleryAutoDetectMaxDimension) 아래로 줄여도 정규 좌표는 그대로 통한다', () {
      // 원본 배율의 2배 크기(2000×1500)로 만들어도 정규화 좌표는 같은
      // 자리를 가리켜야 한다 — 다운샘플이 결과 좌표계를 바꾸면 안 된다
      // (`downsampleLuma`가 카메라 경로에서 지키는 것과 같은 계약).
      const scale = 2;
      const w = 1000 * scale, h = 750 * scale;
      const left = 165 * scale, top = 156 * scale;
      const right = 866 * scale, bottom = 520 * scale;
      final scene = texturedCardScene(
        width: w,
        height: h,
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      );
      final path = '${tempDir.path}/big_card.png';
      File(path).writeAsBytesSync(img.encodePng(scene));

      final result = detectGalleryCardCorners(GalleryAutoDetectRequest(path));

      expect(result.success, isTrue);
      final flat = result.cornersFlat!;
      final xs = [for (var i = 0; i < 8; i += 2) flat[i] * w];
      final ys = [for (var i = 1; i < 8; i += 2) flat[i] * h];
      // 다운샘플 오차가 커지므로 여유를 두 배로 준다.
      expect(xs.reduce(min), closeTo(left, 80));
      expect(xs.reduce(max), closeTo(right, 80));
      expect(ys.reduce(min), closeTo(top, 80));
      expect(ys.reduce(max), closeTo(bottom, 80));
    });
  });
}
