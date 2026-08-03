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
  // 테두리가 보인다. 처음엔 원형으로 딱 잘라냈지만("사각을 둥근형태로") 그것도
  // 가운데 흰 원반과 파란 배경이 각지게(둥글어도 경계선이 뚜렷하게) 분리돼
  // 보인다는 피드백을 받아, 경계 몇 px만 다듬는 대신 안쪽 절반부터 바깥까지
  // 넓은 구간에 걸쳐 서서히 배경색으로 녹아드는 비네트(vignette)로 바꿨다.
  final offsetX = (canvasSize - insetSize) ~/ 2;
  final offsetY = (canvasSize - insetSize) ~/ 2;
  final radius = insetSize / 2;
  final innerR = radius * 0.48; // 여기까지는 원본 그대로(완전 불투명)
  final outerR = radius; // 여기서부터는 배경색 100%
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
