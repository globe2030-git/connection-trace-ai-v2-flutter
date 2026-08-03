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

  // 실제 홈 화면 아이콘 크기(약 60~180px)로 축소해서 보니, 넓은 비네트가
  // 전체적으로 흐릿하게 뭉개져 보인다는 피드백을 받았다 — 오브젝트를 훨씬
  // 크게 채우고(0.82→0.94) 경계를 다듬는 범위도 바깥 12%로 좁혀서, 작은
  // 크기에서도 또렷하게 읽히도록 다시 조정.
  const scale = 0.94;
  final insetSize = (canvasSize * scale).round();
  final resized = img.copyResize(src, width: insetSize, height: insetSize, interpolation: img.Interpolation.cubic);

  final offsetX = (canvasSize - insetSize) ~/ 2;
  final offsetY = (canvasSize - insetSize) ~/ 2;
  final radius = insetSize / 2;
  final innerR = radius * 0.88; // 대부분은 원본 그대로(완전 불투명) — 작은 크기에서도 또렷하게
  final outerR = radius; // 가장자리 12%만 배경색으로 부드럽게 녹아듦
  final bgColor = img.ColorRgb8(0x00, 0x4E, 0xA2);

  for (var y = 0; y < insetSize; y++) {
    for (var x = 0; x < insetSize; x++) {
      final dx = x - radius + 0.5;
      final dy = y - radius + 0.5;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist >= outerR) continue;

      final srcPixel = resized.getPixel(x, y);
      double t;
      if (dist <= innerR) {
        t = 1.0;
      } else {
        final linear = ((outerR - dist) / (outerR - innerR)).clamp(0.0, 1.0);
        t = linear * linear * (3 - 2 * linear); // smoothstep — 부드러운 감쇠 곡선
      }
      final r = srcPixel.r * t + bgColor.r * (1 - t);
      final g = srcPixel.g * t + bgColor.g * (1 - t);
      final b = srcPixel.b * t + bgColor.b * (1 - t);
      canvas.setPixelRgb(offsetX + x, offsetY + y, r.round(), g.round(), b.round());
    }
  }

  File('assets/icons3d/radar_on_brand_bg.png').writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generated assets/icons3d/radar_on_brand_bg.png (1024x1024)');
}
