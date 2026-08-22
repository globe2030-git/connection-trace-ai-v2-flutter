// 398(갤러리 경로에도 자르기 화면) — EXIF 방향을 자르기 화면에 넘기기
// 전에 굽는 [bakeExifOrientation]을 검증한다.
//
// 왜 중요한가: 갤러리 사진은 카메라 앱·다른 기기에서 찍혀 EXIF 방향
// 태그가 다양하다. `bakeImageRotation`(화면에서 돌린 각도용)은 각도가
// 0이면 **원본을 그대로** 돌려줘 방향 태그가 안 구워진다 — 그 상태로
// ManualCropView에 넘기면 화면이 보여주는 방향과 warpCardToFile이 자기
// 소스를 다시 읽을 때 굽는 방향이 달라질 수 있다(추가 397과 같은 종류의
// 어긋남). 이 테스트는 [bakeExifOrientation]이 **각도 입력 없이도 항상**
// 방향 태그를 물리적으로 반영하는지를 확인한다.
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/image_rotation_bake.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gallery_exif_bake_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// EXIF 방향 태그를 [orientation]으로 박은 사진을 만든다. 태그를 읽지
  /// 않고 그대로 디코드하면(=원본 픽셀) 항상 가로(1600x1000)로 보인다.
  Future<String> writePhotoWithOrientationTag(int orientation) async {
    final photo = img.Image(width: 1600, height: 1000);
    img.fill(photo, color: img.ColorRgb8(90, 100, 90));
    photo.exif.imageIfd.orientation = orientation;
    final path = '${dir.path}/photo_orient_$orientation.jpg';
    await File(path).writeAsBytes(img.encodeJpg(photo, quality: 100));
    return path;
  }

  group('bakeExifOrientation', () {
    test('회전 각도를 안 줘도(0도) 항상 새 파일을 만든다', () async {
      final path = await writePhotoWithOrientationTag(1); // 정상 방향.
      final baked = await bakeExifOrientation(XFile(path));
      // ⚠️ 여기가 bakeImageRotation(source, 0)과 갈리는 지점이다 — 그
      // 함수는 degrees==0이면 원본을 그대로 돌려주지만, 이 함수는 방향
      // 태그가 이미 "정상"이어도 다시 인코딩한다(문서 참고).
      expect(baked.path, isNot(path));
    });

    test(
      '⚠️ EXIF 방향 태그(90도 회전)가 있으면 물리적으로 굽는다 — '
      '가로 사진이 세로로 바뀐다',
      () async {
        final path = await writePhotoWithOrientationTag(6); // 90도 회전 필요.
        final baked = await bakeExifOrientation(XFile(path));
        final bakedDecoded = img.decodeImage(
          File(baked.path).readAsBytesSync(),
        )!;

        // 방향 태그를 반영하면 가로세로가 뒤바뀐다 — 회전이 실제로 픽셀에
        // 적용됐다는 뜻이다(1600x1000 원본 + 90도 태그 → 1000x1600).
        expect(bakedDecoded.width, 1000);
        expect(bakedDecoded.height, 1600);

        // 구운 결과에는 더 돌려야 할 방향 태그가 남지 않는다 — 남아 있으면
        // 이 파일을 다시 읽는 쪽(warpCardToFile 등)이 또 한 번 돌려 버린다.
        expect(bakedDecoded.exif.imageIfd.hasOrientation, isFalse);
      },
    );

    test(
      '📌 구운 파일을 warpCardToFile 쪽(img.bakeOrientation)이 다시 읽어도 '
      '더는 방향이 바뀌지 않는다 — 두 소비자가 같은 크기에 합의한다',
      () async {
        final path = await writePhotoWithOrientationTag(8); // 270도 회전 필요.
        final baked = await bakeExifOrientation(XFile(path));

        final firstRead = img.decodeImage(File(baked.path).readAsBytesSync())!;
        // warpCardToFile이 자기 소스를 읽을 때 항상 하는 것과 같은 호출.
        final secondBake = img.bakeOrientation(firstRead);

        expect(secondBake.width, firstRead.width);
        expect(secondBake.height, firstRead.height);
      },
    );
  });
}
