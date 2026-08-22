/// 갤러리에서 고른 **정지 이미지**에 명함 테두리 검출을 돌린다(결함 399).
///
/// ## 왜 필요했나
///
/// 398이 갤러리 경로에 자르기 화면을 붙이면서 [자동 인식] 세그먼트와
/// "테두리를 자동으로 찾았어요" 배너를 그대로 노출했는데, **정작 검출은
/// 한 번도 돌지 않았다** — 시작 귀퉁이가 사진 거의 전체(`kAutoModeStartCorners`,
/// 2~98%)로 고정돼 있었을 뿐이다. 실측(2026-08-22 폴드)에서 명함이 사각형의
/// 69%·55%만 차지했는데도 "찾았다"고 말해, 그대로 자르면 배경이 절반 섞여
/// 들어갔다(51.2%). 이 파일은 **실제로 찾는다.**
///
/// ## 왜 촬영 경로와 같은 OpenCV 판정을 그대로 쓰나
///
/// [detectCardQuadsWithOpenCv](`card_rect_opencv.dart`)와 [pickBestCardQuad]·
/// [judgeCardShape](`card_quad_geometry.dart`)는 **정지 이미지 입력으로 이미
/// 검증된** 코드다(386 측정 — 카메라 실시간 스트림이 아니라 사진 파일을
/// 밝기 평면으로 바꿔 넣고 잰 것). 이 화면은 카메라 프레임이 아니라 이미
/// 저장된 사진 한 장을 다루므로, 새 판정 규칙을 만들지 않고 **그 코드를
/// 그대로 재사용한다** — 닫기 연산(끊긴 캐니 경계 잇기)·가장자리 접촉 후보
/// 제외·`isCardLike`(가로세로비·직각 오차·최소 넓이) 전부 카메라 경로와
/// 동일하다.
///
/// ⚠️ **아이폰 네이티브(`VNDetectRectanglesRequest`)는 쓰지 않는다.** 그건
/// 카메라 프레임을 매 순간 채널로 넘기는 라이브 스트림 전용 통로다
/// (`CardRectDetector`). 여기서는 이미 디코드된 정지 이미지 하나를 다루므로,
/// 플랫폼 채널을 새로 뚫을 필요 없이 `dartcv4`(OpenCV) 함수를 **두 플랫폼
/// 모두에서** 직접 부른다 — `dartcv4`는 애초에 Dart 레벨 FFI 바인딩이라
/// iOS·Android 어디서나 돌아간다(안드로이드 카메라 경로가 이걸 쓰는 이유는
/// "안드로이드에 대응하는 OS API가 없어서"였지, dartcv4 자체가 안드로이드
/// 전용이라서가 아니다).
///
/// ## 왜 [compute]로 돌려야 하나
///
/// JPEG 디코드 + 리사이즈 + OpenCV 검출은 화면 진입을 막으면 안 되는 무거운
/// 작업이다(브리프 요구사항 3). [detectGalleryCardCorners]는 **동기 함수**로
/// 두고, 부르는 쪽(`manual_crop_view.dart`)이 `compute()`로 별도 isolate에서
/// 돌린다 — `warpCardToFile`·`encodeCameraFrameToJpeg`와 같은 패턴이다.
///
/// ⚠️ **isolate 경계를 넘길 값은 평범한 것만 담는다.** `Offset`을 그대로
/// 돌려주지 않고 평평한 `List<double>`로 편다 — `card_quad_warp.dart`가
/// `visibleCornersFlat`을 쓰는 것과 같은 이유다.
library;

import 'dart:io';
import 'dart:ui' show Size;

import 'package:image/image.dart' as img;

import 'card_quad_geometry.dart';
import 'card_rect_opencv.dart';

/// 검출 전에 줄일 최장 변 상한(px).
///
/// 카메라 경로([downsampleLuma])와 같은 값을 쓴다 — 386 측정이 이 크기
/// 기준으로 "다운샘플 후 프레임당 ~5ms"를 쟀다.
const int kGalleryAutoDetectMaxDimension = 1024;

/// [detectGalleryCardCorners]에 넘길 인자.
class GalleryAutoDetectRequest {
  const GalleryAutoDetectRequest(this.imagePath);

  /// **똑바로 선** 사진 경로 — 부르는 쪽이 EXIF 방향을 이미 구워 넘긴다
  /// (`file_picker_modal_view.dart`의 `bakeExifOrientation` 다음 단계).
  final String imagePath;
}

/// [detectGalleryCardCorners]가 돌려주는 값.
///
/// ⚠️ **[success]가 거짓이면 [cornersFlat]을 보지 않는다.** "찾았지만
/// 애매하다"는 상태를 만들지 않는다 — 찾았거나(그리고 명함처럼 생겼거나)
/// 못 찾은 것 둘뿐이다. 애매한 애매함을 화면에 노출하면 "찾지 못했는데
/// 찾았다고 말하는" 경로가 생길 여지가 생긴다.
class GalleryAutoDetectResult {
  const GalleryAutoDetectResult({required this.success, this.cornersFlat});

  final bool success;

  /// 여덟 개(x0,y0,x1,y1,...) — **이미지 정규 좌표(0~1)**, 시계 방향.
  /// [success]가 참일 때만 채워진다.
  final List<double>? cornersFlat;
}

/// 갤러리 사진 한 장에서 명함 사각형을 찾는다.
///
/// [compute]로 별도 isolate에서 돌려야 한다 — 디코드·리사이즈·검출이 화면
/// 진입 직후 여러 장의 사진 파일을 훑는 무거운 작업이다.
///
/// ⚠️ 던지지 않는다. 실패(디코드 실패·후보 없음·판정 탈락)는 전부
/// `success: false`로 뭉뚱그린다 — 부르는 쪽은 "왜 실패했는지"가 아니라
/// "수동으로 맞춰 달라고 안내할지"만 결정하면 된다.
GalleryAutoDetectResult detectGalleryCardCorners(
  GalleryAutoDetectRequest request,
) {
  try {
    final bytes = File(request.imagePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width < 8 || decoded.height < 8) {
      return const GalleryAutoDetectResult(success: false);
    }

    final work = _downscaledForDetection(decoded);
    final gray = img.grayscale(work);
    // ChannelOrder.red — 그레이스케일이면 R=G=B라 한 채널만 뽑으면 그대로
    // 밝기 평면이다. 행 패딩 없이 폭×높이로 나온다(package:image 내부
    // 저장이 항상 조밀하다).
    final luma = gray.getBytes(order: img.ChannelOrder.red);

    final opencv = detectCardQuadsWithOpenCv(
      luma,
      width: work.width,
      height: work.height,
    );
    if (!opencv.imageOk || opencv.quads.isEmpty) {
      return const GalleryAutoDetectResult(success: false);
    }

    final candidates = cardQuadsFromFlat(opencv.quads);
    if (candidates.isEmpty) {
      return const GalleryAutoDetectResult(success: false);
    }

    final best = pickBestCardQuad(
      candidates,
      Size(work.width.toDouble(), work.height.toDouble()),
    );
    if (best == null) {
      // 386·#415와 같은 태도 — 판정을 통과 못 한 후보를 억지로 쓰지 않는다.
      // 명함이 아닌 것을 "찾았다"고 말하는 것보다 못 찾았다고 하는 편이 낫다.
      return const GalleryAutoDetectResult(success: false);
    }

    final flat = <double>[];
    for (final corner in best.corners) {
      flat
        ..add(corner.dx)
        ..add(corner.dy);
    }
    return GalleryAutoDetectResult(success: true, cornersFlat: flat);
  } catch (_) {
    return const GalleryAutoDetectResult(success: false);
  }
}

/// 최장 변이 [kGalleryAutoDetectMaxDimension]을 넘으면 비율을 유지한 채
/// 줄인다. 결과 좌표는 0~1 정규화라 검출 해상도와 무관하게 그대로 통한다.
img.Image _downscaledForDetection(img.Image decoded) {
  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  if (longest <= kGalleryAutoDetectMaxDimension) return decoded;

  final scale = kGalleryAutoDetectMaxDimension / longest;
  final width = (decoded.width * scale).round().clamp(1, decoded.width);
  final height = (decoded.height * scale).round().clamp(1, decoded.height);
  return img.copyResize(
    decoded,
    width: width,
    height: height,
    interpolation: img.Interpolation.average,
  );
}
