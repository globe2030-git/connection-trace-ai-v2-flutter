// assets/icons3d/radar.png(3D 레이더 아이콘)은 배경이 거의 흰색에 가까운
// 옅은 회색이라 홈 화면(특히 밝은 배경/앱스토어 등)에서 잘 안 보인다는
// 피드백으로, 브랜드 액센트 컬러(#004EA2)를 배경으로 깔고 그 위에 원본
// 아이콘을 살짝 축소해 중앙에 합성한 새 아이콘 원본을 만든다.
// `dart run tool/generate_app_icon_bg.dart`로 실행하면
// assets/icons3d/radar_on_brand_bg.png가 생성된다.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  // 파일 확장자는 .png지만 실제로는 JPEG로 저장돼 있어서(sips로 확인)
  // 포맷을 자동 감지하는 decodeImage를 쓴다.
  final src = img.decodeImage(File('assets/icons3d/radar.png').readAsBytesSync())!;

  const canvasSize = 1024;
  final canvas = img.Image(width: canvasSize, height: canvasSize, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(0x00, 0x4E, 0xA2));

  const scale = 0.82;
  final insetSize = (canvasSize * scale).round();
  final resized = img.copyResize(src, width: insetSize, height: insetSize, interpolation: img.Interpolation.cubic);

  // 원본이 정사각형 배경을 그대로 갖고 있어서 그냥 합성하면 각진 사각형
  // 테두리가 보인다("사각을 둥근형태로") — compositeImage의 mask 옵션은
  // 채널 수가 다른 이미지끼리 섞을 때 색이 탁해지는 문제가 있어서, 픽셀
  // 단위로 원 안쪽만 직접 복사하는 방식으로 확실하게 원형으로 잘라낸다.
  // 가장자리 2px 정도는 배경색과 섞어서(안티앨리어싱) 계단 현상을 줄인다.
  final offsetX = (canvasSize - insetSize) ~/ 2;
  final offsetY = (canvasSize - insetSize) ~/ 2;
  final radius = insetSize / 2;
  const featherPx = 2.0;
  final bgColor = img.ColorRgb8(0x00, 0x4E, 0xA2);

  for (var y = 0; y < insetSize; y++) {
    for (var x = 0; x < insetSize; x++) {
      final dx = x - radius + 0.5;
      final dy = y - radius + 0.5;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist > radius + featherPx) continue;

      final srcPixel = resized.getPixel(x, y);
      final t = ((radius - dist) / featherPx).clamp(0.0, 1.0);
      final r = srcPixel.r * t + bgColor.r * (1 - t);
      final g = srcPixel.g * t + bgColor.g * (1 - t);
      final b = srcPixel.b * t + bgColor.b * (1 - t);
      canvas.setPixelRgb(offsetX + x, offsetY + y, r.round(), g.round(), b.round());
    }
  }

  File('assets/icons3d/radar_on_brand_bg.png').writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generated assets/icons3d/radar_on_brand_bg.png (1024x1024)');
}
