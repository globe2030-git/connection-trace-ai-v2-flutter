// 무음 촬영(프레임 캡처) 경로의 YUV→RGB 변환·회전·인코딩을 검증한다.
//
// ⚠️ 이 테스트는 "무음인지"는 검증하지 못한다 — 그건 실기기에서 들어야 안다.
// 여기서 검증하는 것은 **픽셀 계산이 맞는가**뿐이다(합성 장면).
import 'dart:io';
import 'dart:typed_data';

import 'package:connection_trace_ai_flutter/core/utils/camera_frame_jpeg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 안드로이드 스타일(3평면: Y/U/V, 각 픽셀스트라이드 1)의 균일한 색 프레임을
/// 만든다. width/height는 짝수여야 한다(4:2:0 서브샘플링).
List<CameraFramePlaneData> _triPlanar({
  required int width,
  required int height,
  required int y,
  required int u,
  required int v,
}) {
  final yPlane = Uint8List(width * height)..fillRange(0, width * height, y);
  final uvW = width ~/ 2;
  final uvH = height ~/ 2;
  final uPlane = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, u);
  final vPlane = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, v);
  return [
    CameraFramePlaneData(bytes: yPlane, bytesPerRow: width, bytesPerPixel: 1),
    CameraFramePlaneData(bytes: uPlane, bytesPerRow: uvW, bytesPerPixel: 1),
    CameraFramePlaneData(bytes: vPlane, bytesPerRow: uvW, bytesPerPixel: 1),
  ];
}

/// 아이폰 스타일(2평면: Y + interleaved CbCr, NV12)의 균일한 색 프레임을
/// 만든다.
List<CameraFramePlaneData> _biPlanar({
  required int width,
  required int height,
  required int y,
  required int u,
  required int v,
}) {
  final yPlane = Uint8List(width * height)..fillRange(0, width * height, y);
  final uvW = width ~/ 2;
  final uvH = height ~/ 2;
  final uvPlane = Uint8List(uvW * uvH * 2);
  for (var i = 0; i < uvW * uvH; i++) {
    uvPlane[i * 2] = u;
    uvPlane[i * 2 + 1] = v;
  }
  return [
    CameraFramePlaneData(bytes: yPlane, bytesPerRow: width, bytesPerPixel: 1),
    CameraFramePlaneData(
      bytes: uvPlane,
      bytesPerRow: uvW * 2,
      bytesPerPixel: 2,
    ),
  ];
}

void main() {
  group('decodeCameraFrame — 안드로이드 3평면', () {
    test('흰색(Y=235,U=128,V=128)에 가까운 장면은 RGB도 밝다', () {
      final planes = _triPlanar(width: 4, height: 4, y: 235, u: 128, v: 128);
      final image = decodeCameraFrame(width: 4, height: 4, planes: planes);
      expect(image.width, 4);
      expect(image.height, 4);
      final pixel = image.getPixel(0, 0);
      expect(pixel.r, greaterThan(220));
      expect(pixel.g, greaterThan(220));
      expect(pixel.b, greaterThan(220));
    });

    test('검은색(Y=16)에 가까운 장면은 RGB도 어둡다', () {
      final planes = _triPlanar(width: 4, height: 4, y: 16, u: 128, v: 128);
      final image = decodeCameraFrame(width: 4, height: 4, planes: planes);
      final pixel = image.getPixel(2, 2);
      expect(pixel.r, lessThan(40));
      expect(pixel.g, lessThan(40));
      expect(pixel.b, lessThan(40));
    });

    test('U/V가 128(무채색)이면 R·G·B가 서로 같다 — 색이 섞이지 않는다', () {
      final planes = _triPlanar(width: 4, height: 4, y: 150, u: 128, v: 128);
      final image = decodeCameraFrame(width: 4, height: 4, planes: planes);
      final pixel = image.getPixel(1, 1);
      expect(pixel.r, pixel.g);
      expect(pixel.g, pixel.b);
    });

    test('V가 커지면(빨강 방향) R이 G·B보다 커진다', () {
      final planes = _triPlanar(width: 4, height: 4, y: 150, u: 128, v: 200);
      final image = decodeCameraFrame(width: 4, height: 4, planes: planes);
      final pixel = image.getPixel(1, 1);
      expect(pixel.r, greaterThan(pixel.g));
      expect(pixel.r, greaterThan(pixel.b));
    });
  });

  group('decodeCameraFrame — 아이폰 2평면(NV12)', () {
    test('삼평면과 같은 Y/U/V 값이면 같은 색이 나온다', () {
      final tri = decodeCameraFrame(
        width: 4,
        height: 4,
        planes: _triPlanar(width: 4, height: 4, y: 180, u: 100, v: 160),
      );
      final bi = decodeCameraFrame(
        width: 4,
        height: 4,
        planes: _biPlanar(width: 4, height: 4, y: 180, u: 100, v: 160),
      );
      final triPixel = tri.getPixel(0, 0);
      final biPixel = bi.getPixel(0, 0);
      expect(biPixel.r, triPixel.r);
      expect(biPixel.g, triPixel.g);
      expect(biPixel.b, triPixel.b);
    });
  });

  test('평면이 2·3장이 아니면 지원하지 않는다고 알린다', () {
    expect(
      () => decodeCameraFrame(
        width: 4,
        height: 4,
        planes: [
          CameraFramePlaneData(
            bytes: Uint8List(16),
            bytesPerRow: 4,
            bytesPerPixel: 1,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  group('encodeCameraFrameToJpeg', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('camera_frame_jpeg_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('회전 없음(0) — 가로세로가 그대로 유지된다', () {
      final outputPath = '${tempDir.path}/frame_no_rotate.jpg';
      final result = encodeCameraFrameToJpeg(
        CameraFrameEncodeRequest(
          width: 8,
          height: 4,
          planes: _triPlanar(width: 8, height: 4, y: 200, u: 128, v: 128),
          quarterTurns: 0,
          outputPath: outputPath,
        ),
      );
      expect(result, isNotNull);
      expect(result!.width, 8);
      expect(result.height, 4);
      expect(File(outputPath).existsSync(), isTrue);

      final decoded = img.decodeJpg(File(outputPath).readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, 8);
      expect(decoded.height, 4);
    });

    test('90도 회전 — 가로세로가 뒤바뀐다(안드로이드 센서 보정 경로)', () {
      final outputPath = '${tempDir.path}/frame_rotate_90.jpg';
      final result = encodeCameraFrameToJpeg(
        CameraFrameEncodeRequest(
          width: 8,
          height: 4,
          planes: _triPlanar(width: 8, height: 4, y: 200, u: 128, v: 128),
          quarterTurns: 1,
          outputPath: outputPath,
        ),
      );
      expect(result, isNotNull);
      expect(result!.width, 4);
      expect(result.height, 8);
    });

    test('출력 경로에 못 쓰면 null을 돌려준다 — 폴백 신호', () {
      final result = encodeCameraFrameToJpeg(
        CameraFrameEncodeRequest(
          width: 4,
          height: 4,
          planes: _triPlanar(width: 4, height: 4, y: 200, u: 128, v: 128),
          quarterTurns: 0,
          outputPath: '${tempDir.path}/존재하지않는하위폴더/out.jpg',
        ),
      );
      expect(result, isNull);
    });
  });
}
