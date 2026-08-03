// 앱 아이콘(커넥션센스) 마스터 이미지를 코드로 직접 그려서 생성하는 1회성 스크립트.
// `dart run tool/generate_app_icon.dart`로 실행하면 assets/icon/ 아래에
// icon_full.png(불투명 배경, iOS·Android 레거시용)와
// icon_foreground.png(투명 배경, Android adaptive icon foreground용) 두 개를 만든다.
//
// 도안은 바깥 링 반지름(outerRadius)을 기준으로 한 상대 좌표로 그려서, 버전별로
// 캔버스를 얼마나 채울지만 다르게 준다 — icon_full은 캔버스 대부분을 채우고,
// icon_foreground는 Android adaptive icon 안전 영역(중심에서 반경 약 340px,
// 런처별 마스킹 모양에 안 잘리는 범위)에 맞춰 더 작게 그린다.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const _size = 1024;
const _cx = 512.0;
const _cy = 512.0;

img.Color get _bg => img.ColorRgba8(0x0B, 0x0E, 0x14, 255);
img.Color get _accent => img.ColorRgba8(0x00, 0x4E, 0xA2, 255);
img.Color get _accentText => img.ColorRgba8(0x5A, 0x90, 0xC8, 255);
img.Color get _fg => img.ColorRgba8(0xF5, 0xF6, 0xF7, 255);

img.Color _withAlpha(img.Color c, double alpha) {
  return img.ColorRgba8(c.r.toInt(), c.g.toInt(), c.b.toInt(), (255 * alpha).round());
}

/// 두께가 있는 원형 링을 그린다 — 촘촘하게 반지름을 1px씩 늘려가며 안티앨리어싱
/// 원을 여러 번 겹쳐 그리는 방식이라(image 패키지에 두꺼운 원 그리기가 없음)
/// 이음매 없이 매끈하게 나온다.
void _drawThickRing(img.Image image, {required double radius, required double thickness, required img.Color color}) {
  final rStart = (radius - thickness / 2).round();
  final rEnd = (radius + thickness / 2).round();
  for (var r = rStart; r <= rEnd; r++) {
    img.drawCircle(image, x: _cx.round(), y: _cy.round(), radius: r, color: color, antialias: true);
  }
}

/// 링을 짧은 두꺼운 조각(dash)으로 나눠 그린다 — "스캔 중" 느낌을 주기 위함.
/// 각 조각은 독립된 직선 하나로만 그려서(여러 짧은 세그먼트를 이어붙이지 않음)
/// 이음매가 보이는 문제가 없다.
void _drawDashedRing(img.Image image, {required double radius, required double thickness, required img.Color color, required int dashCount, required double dashDeg}) {
  for (var i = 0; i < dashCount; i++) {
    final centerDeg = i * (360 / dashCount);
    final a1 = (centerDeg - dashDeg / 2) * pi / 180;
    final a2 = (centerDeg + dashDeg / 2) * pi / 180;
    final x1 = _cx + radius * cos(a1);
    final y1 = _cy + radius * sin(a1);
    final x2 = _cx + radius * cos(a2);
    final y2 = _cy + radius * sin(a2);
    img.drawLine(image, x1: x1.round(), y1: y1.round(), x2: x2.round(), y2: y2.round(), color: color, thickness: thickness, antialias: true);
  }
}

void _drawSpark(img.Image image, {required double cx, required double cy, required double size, required img.Color color}) {
  final pts = [
    img.Point(cx, cy - size),
    img.Point(cx + size * 0.22, cy - size * 0.22),
    img.Point(cx + size, cy),
    img.Point(cx + size * 0.22, cy + size * 0.22),
    img.Point(cx, cy + size),
    img.Point(cx - size * 0.22, cy + size * 0.22),
    img.Point(cx - size, cy),
    img.Point(cx - size * 0.22, cy - size * 0.22),
  ];
  img.fillPolygon(image, vertices: pts, color: color);
}

/// [outerRadius]를 기준으로 전체 도안 비율을 맞춰 그린다.
img.Image _buildIcon({required bool transparentBg, required double outerRadius}) {
  final image = img.Image(width: _size, height: _size, numChannels: 4);
  img.fill(image, color: transparentBg ? img.ColorRgba8(0, 0, 0, 0) : _bg);

  final ringOuter = outerRadius;
  final ringMid = outerRadius * 0.72;
  final ringInner = outerRadius * 0.44;
  final ringThickness = outerRadius * 0.05;

  _drawThickRing(image, radius: ringOuter, thickness: ringThickness, color: _withAlpha(_accentText, 0.22));
  _drawDashedRing(image, radius: ringMid, thickness: ringThickness, color: _withAlpha(_accentText, 0.5), dashCount: 14, dashDeg: 16);
  _drawThickRing(image, radius: ringInner, thickness: ringThickness, color: _withAlpha(_accentText, 0.75));

  // 감지된 두 점 + 연결선 — "커넥션"을 표현. 캔버스 전체를 균형 있게 채우도록
  // 서로 다른 방향(우상단/좌하단)에 배치.
  final dotA = (
    x: _cx + ringOuter * 0.86 * cos(-28 * pi / 180),
    y: _cy + ringOuter * 0.86 * sin(-28 * pi / 180),
  );
  final dotB = (
    x: _cx + ringMid * 0.82 * cos(158 * pi / 180),
    y: _cy + ringMid * 0.82 * sin(158 * pi / 180),
  );

  img.drawLine(image, x1: _cx.round(), y1: _cy.round(), x2: dotA.x.round(), y2: dotA.y.round(), color: _withAlpha(_accentText, 0.85), thickness: outerRadius * 0.015, antialias: true);
  img.drawLine(image, x1: _cx.round(), y1: _cy.round(), x2: dotB.x.round(), y2: dotB.y.round(), color: _withAlpha(_accentText, 0.6), thickness: outerRadius * 0.015, antialias: true);

  img.fillCircle(image, x: dotA.x.round(), y: dotA.y.round(), radius: (outerRadius * 0.06).round(), color: _fg, antialias: true);
  img.fillCircle(image, x: dotB.x.round(), y: dotB.y.round(), radius: (outerRadius * 0.05).round(), color: _accentText, antialias: true);

  // 감지 순간의 반짝임 — dotA 옆에 살짝 겹치게 배치.
  _drawSpark(image, cx: dotA.x - outerRadius * 0.03, cy: dotA.y - outerRadius * 0.09, size: outerRadius * 0.075, color: _withAlpha(_accentText, 0.9));

  // 중심 센서 점(나 자신) — 가장 마지막에 그려서 항상 위에 보이게 한다.
  img.fillCircle(image, x: _cx.round(), y: _cy.round(), radius: (outerRadius * 0.196).round(), color: _withAlpha(_accent, 0.35), antialias: true);
  img.fillCircle(image, x: _cx.round(), y: _cy.round(), radius: (outerRadius * 0.139).round(), color: _accent, antialias: true);

  return image;
}

void main() {
  final outDir = Directory('assets/icon');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // iOS/Android 레거시 아이콘 — 캔버스 대부분(반경 460, 가장자리 여백 약 52px)을 채운다.
  final full = _buildIcon(transparentBg: false, outerRadius: 460);
  File('${outDir.path}/icon_full.png').writeAsBytesSync(img.encodePng(full));

  // Android adaptive icon foreground — 런처 마스킹에 안 잘리는 안전 영역(반경 300)에 맞춤.
  final foreground = _buildIcon(transparentBg: true, outerRadius: 300);
  File('${outDir.path}/icon_foreground.png').writeAsBytesSync(img.encodePng(foreground));

  stdout.writeln('Generated ${outDir.path}/icon_full.png and icon_foreground.png (1024x1024)');
}
