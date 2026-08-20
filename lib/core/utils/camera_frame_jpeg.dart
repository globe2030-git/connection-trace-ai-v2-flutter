/// 카메라 **프리뷰 스트림**의 프레임 한 장을 JPEG 파일로 인코딩한다(무음 촬영,
/// 추가 — 테스터 B 요청).
///
/// ## 왜 `takePicture()`가 아니라 프레임 스트림을 쓰나
///
/// [CameraController.takePicture]는 "사진 촬영" 이벤트로 취급되어 iOS·
/// Android가 셔터음을 강제로 낸다. 이 화면은 자동 촬영 판정을 위해 이미
/// `startImageStream`으로 프리뷰 프레임을 받고 있으므로, 그 프레임 한 장을
/// 그대로 저장하면 "사진 촬영" API를 아예 거치지 않는다 — 시스템이 셔터음을
/// 붙일 이유 자체가 없는 경로다.
///
/// ⚠️ **그렇다고 항상 무음이 보장되는 것은 아니다.** 한국·일본처럼 셔터음이
/// 하드웨어·정책 단에서 강제되는 기기·지역에서는 OS·제조사가 이 경로에도
/// 소리를 붙일 수 있다 — 그건 이 코드가 막을 수 있는 일이 아니고, 막아서도
/// 안 된다. `AVAudioSession` 조작, 시스템 볼륨 강제 설정 같은 "셔터음을
/// 죽이는" 우회는 시도하지 않는다 — Apple Developer Forums에 "앱이 셔터음을
/// 비활성화해서 리젝됐다"는 사례가 있고, 국내 규제 위반 소지도 있다. 실제로
/// 소리가 나는지 안 나는지는 **기기·지역이 결정**하고, 이 코드는 정당한
/// 경로(사진 촬영 API를 안 쓰는 것)만 제공한다.
///
/// ⚠️ **실기기 확인 필요.** 이 변환·인코딩 로직은 자동 테스트로 픽셀 계산의
/// 정확성만 확인했다 — 실제로 무음인지, 화질이 기존 촬영과 견줄 만한지는
/// 실기기에서 듣고 봐야 안다(이 저장소는 "계산"과 "실측"을 구분해서 적는다).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// [encodeCameraFrameToJpeg]에 넘길 평면 하나.
///
/// ⚠️ 별도 isolate로 넘어가므로 **평범한 값만** 담는다. 그리고 이 바이트는
/// 카메라 콜백이 끝나기 **전에** 복사해 온 것이어야 한다 — 원본
/// `CameraImage.planes[i].bytes`는 콜백이 끝나면 네이티브가 재사용한다
/// (`CardRectDetector.detect`가 이미 같은 이유로 첫 await 전에 읽는다).
class CameraFramePlaneData {
  const CameraFramePlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;

  /// U/V(또는 CbCr) 평면의 픽셀 간 바이트 간격. Y 평면에는 쓰이지 않는다.
  final int bytesPerPixel;
}

/// [encodeCameraFrameToJpeg]에 넘길 인자 묶음.
class CameraFrameEncodeRequest {
  const CameraFrameEncodeRequest({
    required this.width,
    required this.height,
    required this.planes,
    required this.quarterTurns,
    required this.outputPath,
    this.jpegQuality = 100,
  });

  final int width;
  final int height;

  /// 2장(아이폰 바이플레인 NV12: Y + interleaved CbCr) 또는 3장(안드로이드
  /// YUV420: Y/U/V 각각 별도 평면).
  final List<CameraFramePlaneData> planes;

  /// **화면(사용자가 보는 방향) 기준**으로 세우는 데 필요한 90도 회전 횟수
  /// (시계 방향). `CardRectDetector`의 `quarterTurnsForFrame`로 구한 값을
  /// 그대로 넘긴다 — 이 화면의 원판 크롭(`_cropToGuideFrame`)이 기대하는
  /// "화면과 같은 방향" 전제를 그대로 맞추기 위함이다.
  final int quarterTurns;

  /// 결과를 쓸 경로. ⚠️ 임시파일 쓸어담기(`scan_temp_cleanup.dart`)가
  /// `card_scan_`·`card_silent_` 접두사를 보고 지운다 — 부르는 쪽이 그 규칙에
  /// 맞는 접두사를 쓸 것.
  final String outputPath;

  final int jpegQuality;
}

/// 인코딩 결과.
class CameraFrameEncodeResult {
  const CameraFrameEncodeResult({
    required this.path,
    required this.width,
    required this.height,
  });

  final String path;
  final int width;
  final int height;
}

/// [compute]로 별도 isolate에서 돌려야 한다 — 12MP급 프레임을 픽셀 단위로
/// 훑는 무거운 작업이라, 본 스레드에서 돌리면 촬영 직후 확인 화면 전환이
/// 멈춘 것처럼 보인다(`warpCardToFile`과 같은 이유).
///
/// 실패하면 null.
CameraFrameEncodeResult? encodeCameraFrameToJpeg(
  CameraFrameEncodeRequest request,
) {
  try {
    final decoded = decodeCameraFrame(
      width: request.width,
      height: request.height,
      planes: request.planes,
    );
    final rotated = request.quarterTurns == 0
        ? decoded
        : img.copyRotate(decoded, angle: request.quarterTurns * 90);
    final jpg = img.encodeJpg(rotated, quality: request.jpegQuality);
    File(request.outputPath).writeAsBytesSync(jpg);
    return CameraFrameEncodeResult(
      path: request.outputPath,
      width: rotated.width,
      height: rotated.height,
    );
  } catch (_) {
    return null;
  }
}

/// YUV 카메라 프레임을 RGB 이미지로 바꾼다.
///
/// 평면이 2장이면 아이폰의 바이플레인 NV12(Y + interleaved CbCr,
/// `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` — `camera_avfoundation`
/// 소스로 확인), 3장이면 안드로이드의 YUV420(Y/U/V 각각 별도 평면)으로 본다.
///
/// ⚠️ BT.601 풀레인지 근사식을 쓴다. 아이폰 쪽은 엄밀히는 비디오 레인지
/// (16~235)라 색이 살짝 달라질 수 있지만, 방송 표준 색 정확도가 목적이
/// 아니라 OCR 인식이 목적이라 이 근사로 충분하다고 판단했다(계산 — 실기기
/// 화질 확인 필요).
img.Image decodeCameraFrame({
  required int width,
  required int height,
  required List<CameraFramePlaneData> planes,
}) {
  if (planes.length == 2) {
    return _decodeBiPlanar(width: width, height: height, planes: planes);
  }
  if (planes.length == 3) {
    return _decodeTriPlanar(width: width, height: height, planes: planes);
  }
  throw ArgumentError('지원하지 않는 카메라 프레임 평면 수: ${planes.length}');
}

/// 안드로이드: Y/U/V가 각각 별도 평면.
img.Image _decodeTriPlanar({
  required int width,
  required int height,
  required List<CameraFramePlaneData> planes,
}) {
  final y = planes[0];
  final u = planes[1];
  final v = planes[2];
  final out = Uint8List(width * height * 3);

  for (var row = 0; row < height; row++) {
    final yRowStart = row * y.bytesPerRow;
    final uvRowStart = (row >> 1) * u.bytesPerRow;
    var outIndex = row * width * 3;
    for (var col = 0; col < width; col++, outIndex += 3) {
      final yValue = y.bytes[yRowStart + col];
      final uvCol = (col >> 1) * u.bytesPerPixel;
      final uValue = u.bytes[uvRowStart + uvCol];
      final vValue = v.bytes[uvRowStart + uvCol];
      _writeRgb(out, outIndex, yValue, uValue, vValue);
    }
  }

  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

/// 아이폰: Y 평면 + Cb/Cr이 한 평면에 번갈아 들어간 바이플레인(NV12).
img.Image _decodeBiPlanar({
  required int width,
  required int height,
  required List<CameraFramePlaneData> planes,
}) {
  final y = planes[0];
  final uv = planes[1];
  final out = Uint8List(width * height * 3);

  for (var row = 0; row < height; row++) {
    final yRowStart = row * y.bytesPerRow;
    final uvRowStart = (row >> 1) * uv.bytesPerRow;
    var outIndex = row * width * 3;
    for (var col = 0; col < width; col++, outIndex += 3) {
      final yValue = y.bytes[yRowStart + col];
      final uvIndex = uvRowStart + (col >> 1) * uv.bytesPerPixel;
      final uValue = uv.bytes[uvIndex];
      final vValue = uv.bytes[uvIndex + 1];
      _writeRgb(out, outIndex, yValue, uValue, vValue);
    }
  }

  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

void _writeRgb(Uint8List out, int index, int yValue, int uValue, int vValue) {
  final d = uValue - 128;
  final e = vValue - 128;
  out[index] = _byte(yValue + 1.402 * e);
  out[index + 1] = _byte(yValue - 0.344136 * d - 0.714136 * e);
  out[index + 2] = _byte(yValue + 1.772 * d);
}

int _byte(double value) => value.round().clamp(0, 255);
