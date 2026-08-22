import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:image/image.dart' as img;

import 'card_quad_geometry.dart';

/// 검출한 사각형대로 **잘라서 펴는**(원근 보정) 처리 — B′ 2단계.
///
/// ## 기존 크롭과 무엇이 다른가
///
/// 지금까지는 화면 한가운데 **고정된 가이드 상자**를 그대로 잘랐다
/// (`_cropToGuideFrame`). 명함이 조금이라도 기울면 **기운 채로 잘렸고**,
/// 가이드보다 작게 들어오면 배경이 함께 담겼다.
///
/// 여기서는 검출된 네 귀퉁이를 직사각형으로 **펴서** 잘라낸다. 비스듬히
/// 찍어도 정면에서 찍은 것처럼 나온다.
///
/// ## ⚠️ 실패하면 반드시 기존 크롭으로 되돌아가야 한다
///
/// 이 파일의 모든 함수는 **실패를 null로 알린다.** 부르는 쪽은 null을 받으면
/// `_cropToGuideFrame`을 그대로 부른다 — **최악의 경우가 지금과 같도록**
/// 만드는 것이 이 작업의 안전선이다. 오늘 기성 스캐너(A안)가 아이폰에서
/// 아쉬웠던 것도 되돌릴 길이 있어서 감당할 수 있었다.
///
/// ## ⚠️ 축소 임계(긴 변 1,600px)와 만나는 자리
///
/// 잘라낸 결과가 1,600px을 안 넘으면 `contact_image_service`가 축소를
/// 건너뛴다. 그러면 저장본이 커져 **무료 200장 한도의 근거가 흔들린다.**
/// 그래서 [warpCardToFile]은 결과 크기를 **검출된 사각형의 실제 픽셀 크기
/// 그대로** 쓴다 — 임의로 늘리거나 줄이지 않는다.
///
/// 실제로 몇 px이 나오는지는 **실기기에서 재야 안다.** A안은 2,039~3,315px로
/// 넉넉히 넘었지만(추가 269), B′는 우리가 자르므로 값이 달라진다.

/// [warpCardToFile]에 넘길 인자 묶음.
///
/// 별도 isolate로 넘어가므로 **평범한 값만** 담는다(파일 손잡이·클로저 금지).
class CardWarpRequest {
  const CardWarpRequest({
    required this.sourcePath,
    required this.visibleCornersFlat,
    required this.screenWidth,
    required this.screenHeight,
    required this.outputPath,
    this.margin = 0.04,
    this.jpegQuality = 100,
    this.autoUpright = true,
    this.cornersAreImageRelative = false,
  });

  /// 촬영 원본 파일 경로.
  final String sourcePath;

  /// **가시 좌표**(0~1)의 네 귀퉁이(x0,y0,x1,y1,... 시계 방향).
  ///
  /// ⚠️ 촬영본 픽셀이 아니라 **화면에 보이는 영역 기준 비율**을 받는다.
  /// 프리뷰 해상도와 촬영본 해상도가 다르기 때문이다 — 픽셀로 미리 바꿔
  /// 넘기려면 촬영본을 한 번 더 디코드해야 하는데, 그건 이 함수가 어차피
  /// 하는 일이다.
  ///
  /// ⚠️ [cornersAreImageRelative]가 참이면 이 설명은 적용되지 않는다 —
  /// 그 필드 문서를 본다.
  final List<double> visibleCornersFlat;

  /// 프리뷰가 그려진 화면 크기(논리 픽셀).
  ///
  /// ⚠️ [cornersAreImageRelative]가 참이면 **이 값은 읽지 않는다.**
  final double screenWidth;
  final double screenHeight;

  /// 검출된 테두리 바깥으로 줄 여백(비율).
  final double margin;

  /// 결과를 쓸 경로.
  ///
  /// ⚠️ 파일명은 **`card_scan_` 접두사**를 지켜야 한다. 기존 임시파일
  /// 쓸어담기(`scan_temp_cleanup.dart`)가 그 접두사를 보고 지운다 —
  /// 새 이름을 쓰면 정리 규칙에 구멍이 생기고, 그 구멍에는 **제3자의
  /// 명함 사진이 평문으로** 남는다(추가 247·249·253).
  final String outputPath;

  /// 원본과 같은 100을 기본으로 둔다. 축소·재압축은 뒷단
  /// (`contact_image_service`)이 맡고 있으므로 **여기서 또 깎으면 두 번
  /// 압축된다.**
  final int jpegQuality;

  /// 결과가 세로로 길면 [uprightCard]로 강제로 눕힐지.
  ///
  /// 기본값 **참**은 자동 촬영 경로(가이드 크롭·검출 크롭)를 위한 것이다 —
  /// 그 경로는 "결과물은 항상 눕혀 있어야 한다"는 촬영 규칙을 전제로 한다.
  ///
  /// ⚠️ **손으로 자르는 경로(`ManualCropView`)는 반드시 거짓으로 넘겨야
  /// 한다**(추가 397). 그 화면은 사용자가 [회전] 버튼과 귀퉁이로 **원하는
  /// 방향을 이미 확정한 뒤** 여기로 넘어온다 — 그 결과를 여기서 "세로면
  /// 무조건 눕힌다"로 다시 뒤집으면, 사용자가 방금 고른 방향을 **소리
  /// 없이 취소하는 꼴**이 된다. 화면에는 사용자가 고른 대로 보이는데
  /// 저장물만 다시 돌아가 있으면 그 차이를 화면에서는 절대 알아챌 수
  /// 없다 — 이 결함이 크롭 화면만 봐서는 안 잡히는 이유 중 하나였다.
  final bool autoUpright;

  /// **참**이면 [visibleCornersFlat]을 화면 매핑 없이 **이미지 자체의
  /// 정규 좌표(0~1)로 바로** 쓴다 — [screenWidth]/[screenHeight]는
  /// 무시한다.
  ///
  /// ⚠️ 왜 필요한가(추가 397 조사): 손으로 자르기(`ManualCropView`)는
  /// "화면 크기 = 사진 크기"를 넘겨 화면 매핑([visibleImageRect])을
  /// 항등식으로 만드는 우회를 썼다. 그 우회는 **부르는 쪽이 잰 사진
  /// 크기(Flutter 디코더, `Image.file`)와 이 함수가 자기 소스를 다시
  /// 재는 크기(image 패키지 디코더, `img.decodeImage` + `bakeOrientation`)가
  /// 정확히 같다**는 전제 위에 있다. 두 디코더가 같은 파일을 (원인이
  /// 무엇이든) 다르게 읽으면, 항등식이 깨지면서 화면 매핑 계산이 "보이는
  /// 영역"을 실제 이미지와 다르게 잘라 **가장자리에 여백이 대칭으로
  /// 남거나 카드 일부가 잘리는** 결함이 생긴다 — 회전 버튼을 쓴 뒤에만
  /// 재현된 결함(추가 397)과 같은 모양이다.
  ///
  /// 손으로 자르기는 애초에 "화면에 보이는 것 = 이미지 전체"이므로 이
  /// 화면 매핑 자체가 불필요하다 — 정규 좌표를 이미지 크기에 바로 곱하면
  /// 된다. 그래서 **두 디코더가 합의해야 하는 자리를 아예 없앤다.**
  final bool cornersAreImageRelative;
}

/// 원근 보정 결과.
class CardWarpResult {
  const CardWarpResult({
    required this.path,
    required this.width,
    required this.height,
    required this.elapsedMs,
  });

  final String path;
  final int width;
  final int height;

  /// 원근 보정에 걸린 시간(ms).
  ///
  /// ⚠️ **재지 않으면 느린지 모른다.** 실기기에서 촬영 뒤 *"다듬는 중…"*이
  /// 6초 넘게 걸린 것을 화면 녹화로 발견했다 — 그때까지 아무도 몰랐다.
  final int elapsedMs;

  /// 긴 변(px). ⚠️ 축소 임계(1,600)와 견주는 값이다.
  int get longEdge => width > height ? width : height;
}

/// 네 귀퉁이대로 잘라 펴서 파일로 쓴다.
///
/// ⚠️ **무거운 작업이다.** 결과가 2,000×1,250이면 픽셀이 250만 개이고 각
/// 픽셀마다 원본에서 네 점을 읽어 섞는다. **반드시 `compute()` 같은 별도
/// isolate에서 부를 것** — 이 화면은 촬영 직후 확인 화면으로 넘어가므로
/// 본 스레드에서 돌리면 그 전환이 멈춘 것처럼 보인다.
///
/// 실패하면 null. 부르는 쪽은 기존 크롭으로 되돌아간다.
CardWarpResult? warpCardToFile(CardWarpRequest request) {
  final startedAt = DateTime.now();
  try {
    final bytes = File(request.sourcePath).readAsBytesSync();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // 촬영본에는 방향 정보(EXIF)가 붙어 있다. 먼저 실제 방향으로 구워
    // 놓지 않으면 좌표가 어긋난다 — 기존 크롭도 같은 순서로 한다.
    decoded = img.bakeOrientation(decoded);

    final imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
    final screenSize = Size(request.screenWidth, request.screenHeight);

    // 가시 좌표(화면에 보이는 영역 기준) → 촬영본 픽셀.
    final visibleQuad = cardQuadFromFlat(request.visibleCornersFlat);
    if (visibleQuad == null) return null;
    // ⚠️ [cornersAreImageRelative] 문서 참고 — 참이면 화면 매핑을 아예
    // 거치지 않는다. 두 디코더(Flutter/`image` 패키지)가 같은 파일의
    // 크기에 합의해야 하는 자리를 없애는 것이 핵심이다(추가 397).
    final rawPixelCorners = request.cornersAreImageRelative
        ? visibleQuad.toPixels(imageSize)
        : visibleQuadToImagePixels(visibleQuad, imageSize, screenSize);
    final corners = clampCornersToImage(
      expandCorners(rawPixelCorners, margin: request.margin),
      imageSize,
    );

    final outputSize = perspectiveOutputSize(corners);
    final outWidth = outputSize.width.round();
    final outHeight = outputSize.height.round();
    if (outWidth < 2 || outHeight < 2) return null;

    final destination = <Offset>[
      Offset.zero,
      Offset(outWidth - 1, 0),
      Offset(outWidth - 1, outHeight - 1),
      Offset(0, outHeight - 1),
    ];
    final matrix = perspectiveTransform(corners, destination);
    if (matrix == null) return null;

    // ⚠️ **픽셀은 바이트 배열로 직접 다룬다** (2026-08-16 실측으로 바꿈).
    //
    // 처음에는 `getPixel()`/`setPixelRgb()`를 썼는데, 실기기에서 촬영 뒤
    // *"사진을 다듬는 중…"*이 **6초 넘게** 걸렸다(화면 녹화로 확인). 결과가
    // 1786×1005면 픽셀이 180만 개이고, 이중선형 보간이라 **원본에서 네 번씩
    // 읽는다** — `getPixel()`은 호출마다 객체를 만들어 돌려주므로 그 720만
    // 번이 그대로 비용이 된다.
    //
    // 바이트 배열을 한 번 꺼내 인덱스로 읽으면 그 객체 생성이 통째로 사라진다.
    final srcWidth = decoded.width;
    final maxX = srcWidth - 1;
    final maxY = decoded.height - 1;
    final src = decoded.getBytes(order: img.ChannelOrder.rgb);
    final out = Uint8List(outWidth * outHeight * 3);

    for (var y = 0; y < outHeight; y++) {
      var outIndex = y * outWidth * 3;
      for (var x = 0; x < outWidth; x++, outIndex += 3) {
        // 목적지 → 원본 방향으로 물어야 결과에 구멍이 안 생긴다.
        final denominator = matrix[6] * x + matrix[7] * y + matrix[8];
        if (denominator == 0) continue;
        final sourceX =
            (matrix[0] * x + matrix[1] * y + matrix[2]) / denominator;
        final sourceY =
            (matrix[3] * x + matrix[4] * y + matrix[5]) / denominator;
        if (sourceX < 0 || sourceY < 0 || sourceX > maxX || sourceY > maxY) {
          continue;
        }

        // 이중선형 보간 — 가장 가까운 픽셀만 집으면 글자 획에 계단이 생겨
        // OCR 인식률이 떨어진다.
        final x0 = sourceX.toInt();
        final y0 = sourceY.toInt();
        final x1 = x0 >= maxX ? maxX : x0 + 1;
        final y1 = y0 >= maxY ? maxY : y0 + 1;
        final fx = sourceX - x0;
        final fy = sourceY - y0;

        final i00 = (y0 * srcWidth + x0) * 3;
        final i10 = (y0 * srcWidth + x1) * 3;
        final i01 = (y1 * srcWidth + x0) * 3;
        final i11 = (y1 * srcWidth + x1) * 3;

        for (var c = 0; c < 3; c++) {
          final top = src[i00 + c] + (src[i10 + c] - src[i00 + c]) * fx;
          final bottom = src[i01 + c] + (src[i11 + c] - src[i01 + c]) * fx;
          out[outIndex + c] = (top + (bottom - top) * fy).round();
        }
      }
    }

    final warped = img.Image.fromBytes(
      width: outWidth,
      height: outHeight,
      bytes: out.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );

    // ⚠️ [autoUpright] 문서 참고 — 손으로 자르기는 거짓으로 넘어온다.
    final upright = request.autoUpright ? uprightCard(warped) : warped;
    final jpg = img.encodeJpg(upright, quality: request.jpegQuality);
    File(request.outputPath).writeAsBytesSync(jpg);
    return CardWarpResult(
      path: request.outputPath,
      width: upright.width,
      height: upright.height,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  } catch (_) {
    return null;
  }
}

/// 세로로 선 결과물을 가로로 눕힌다.
///
/// ⚠️ 기존 크롭은 **항상 반시계 90°로 고정 회전**했다. 가이드 상자가 세로로
/// 길고, 사용자가 명함을 시계 방향으로 돌려 넣도록 안내했기 때문이다.
///
/// 검출로 바뀌면 그 전제가 깨진다 — **명함이 화면에서 어느 방향이든 잡히기**
/// 때문이다. 그래서 고정 각도 대신 **결과물이 세로로 길면 눕힌다.**
///
/// ⚠️ 이것으로 **위아래가 뒤집힌 경우(180°)까지 바로잡지는 못한다.** 글자를
/// 읽어야 알 수 있는 일이고, 그건 이 단계에서 할 일이 아니다. 사용자가
/// 확인 화면에서 [↻ 회전] 버튼으로 돌릴 수 있다(F-03) — **그 버튼이 여기서
/// 값을 한다.**
img.Image uprightCard(img.Image image) {
  if (image.height <= image.width) return image;
  return img.copyRotate(image, angle: -90);
}

/// 촬영본 픽셀 좌표를 [CardWarpRequest]에 넣을 평평한 배열로 편다.
List<double> cornersToFlat(List<Offset> corners) => [
  for (final corner in corners) ...[corner.dx, corner.dy],
];

/// 검출된 사각형(가시 좌표)을 촬영본 픽셀 좌표로 옮긴 뒤, 명함 바깥으로
/// **약간의 여백**을 준다.
///
/// ⚠️ 왜 여백을 주나: 검출된 테두리를 딱 맞게 자르면 **가장자리 글자가
/// 깎인다.** 이 프로젝트는 정확히 그 결함을 이미 한 번 겪었다 — 크롭 여유를
/// 1.5에서 1.0으로 줄였다가 *"양쪽 끝 글씨가 30~40% 잘린다"*는 제보를
/// 받았다(2026-08-14).
///
/// **잘린 글자는 되찾을 수 없고, 섞인 배경은 파서가 걸러낸다.** 어느 쪽으로
/// 틀릴지 골라야 한다면 넓게 자르는 쪽이다.
///
/// 다만 기존 고정 크롭의 1.2(=20%)보다는 **훨씬 작게** 잡는다. 검출은
/// 명함 테두리를 실제로 짚으므로 큰 여유가 필요 없다 — 검출 오차만 덮으면
/// 된다. ⚠️ **이 4%는 계산이 아니라 어림이다. 실기기에서 네 귀퉁이가
/// 온전한지 확인하고 조여야 한다.**
List<Offset> expandCorners(List<Offset> corners, {double margin = 0.04}) {
  final cx = corners.map((c) => c.dx).reduce((a, b) => a + b) / corners.length;
  final cy = corners.map((c) => c.dy).reduce((a, b) => a + b) / corners.length;
  final scale = 1 + margin;
  return corners
      .map((c) => Offset(cx + (c.dx - cx) * scale, cy + (c.dy - cy) * scale))
      .toList();
}

/// 여백을 준 좌표가 이미지 밖으로 나가지 않게 민다.
///
/// 밖으로 나간 채로 자르면 그 부분이 **검은 띠**로 남는다.
List<Offset> clampCornersToImage(List<Offset> corners, Size imageSize) =>
    corners
        .map(
          (c) => Offset(
            c.dx.clamp(0.0, imageSize.width - 1),
            c.dy.clamp(0.0, imageSize.height - 1),
          ),
        )
        .toList();
