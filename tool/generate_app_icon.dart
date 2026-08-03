// 앱 아이콘(커넥션센스) 마스터 이미지를 코드로 직접 그려서 생성하는 1회성 스크립트.
// `dart run tool/generate_app_icon.dart`로 실행하면 assets/icon/ 아래에
// icon_full.png(밝은 배경, iOS·Android 레거시용)와
// icon_foreground.png(투명 배경, Android adaptive icon foreground용) 두 개를 만든다.
//
// 도안은 바깥 링 반지름(outerRadius)을 기준으로 한 상대 좌표로 그려서, 버전별로
// 캔버스를 얼마나 채울지만 다르게 준다 — icon_full은 캔버스 대부분을 채우고,
// icon_foreground는 Android adaptive icon 안전 영역(중심에서 반경 약 340px,
// 런처별 마스킹 모양에 안 잘리는 범위)에 맞춰 더 작게 그린다.
//
// 바깥/중간 링은 한쪽이 트인 부채꼴(방향성 있는 "센스/감지" 신호)로 그려서,
// 완전히 닫힌 동심원(레이더 느낌)과 구분되게 했다 — 안쪽 링만 닫힌 원으로
// 남겨 중심을 잡아준다.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const _size = 1024;
const _cx = 512.0;
const _cy = 512.0;

img.Color get _bg => img.ColorRgba8(0xFF, 0xFF, 0xFF, 255);
img.Color get _accent => img.ColorRgba8(0x00, 0x4E, 0xA2, 255);
img.Color get _accentSoft => img.ColorRgba8(0x5A, 0x90, 0xC8, 255);
img.Color get _dark => img.ColorRgba8(0x0B, 0x0E, 0x14, 255);

img.Color _withAlpha(img.Color c, double alpha) {
  return img.ColorRgba8(c.r.toInt(), c.g.toInt(), c.b.toInt(), (255 * alpha).round());
}

/// 두께가 있는 "닫힌" 원형 링을 그린다 — 반지름을 1px씩 늘려가며 안티앨리어싱
/// 원을 여러 번 겹쳐 그리는 방식이라(image 패키지에 두꺼운 원 그리기가 없음)
/// 이음매 없이 매끈하게 나온다.
void _drawThickRing(img.Image image, {required double radius, required double thickness, required img.Color color}) {
  final rStart = (radius - thickness / 2).round();
  final rEnd = (radius + thickness / 2).round();
  for (var r = rStart; r <= rEnd; r++) {
    img.drawCircle(image, x: _cx.round(), y: _cy.round(), radius: r, color: color, antialias: true);
  }
}

/// 두께가 있는 "열린" 호를 그린다 — 각도를 촘촘히 나눠 그 위치마다 작은 원을
/// 겹쳐 찍는 방식(스탬핑)이라, 짧은 직선을 이어붙일 때 생기는 이음매/계단
/// 현상 없이 매끈한 곡선이 나온다.
void _drawThickArc(img.Image image, {required double radius, required double startDeg, required double endDeg, required double thickness, required img.Color color}) {
  final arcLength = radius * (endDeg - startDeg).abs() * pi / 180;
  final steps = max(24, (arcLength / (thickness * 0.35)).ceil());
  for (var i = 0; i <= steps; i++) {
    final t = startDeg + (endDeg - startDeg) * (i / steps);
    final rad = t * pi / 180;
    final x = _cx + radius * cos(rad);
    final y = _cy + radius * sin(rad);
    img.fillCircle(image, x: x.round(), y: y.round(), radius: (thickness / 2).round(), color: color, antialias: true);
  }
}

/// 열린 호 구간 안에서만 짧은 조각(dash)들을 그린다 — "스캔 중" 느낌을 주기 위함.
void _drawDashedArc(img.Image image, {required double radius, required double startDeg, required double endDeg, required double thickness, required img.Color color, required int dashCount}) {
  final span = endDeg - startDeg;
  final dashSpan = span / dashCount;
  for (var i = 0; i < dashCount; i++) {
    final segStart = startDeg + i * dashSpan + dashSpan * 0.18;
    final segEnd = startDeg + i * dashSpan + dashSpan * 0.82;
    _drawThickArc(image, radius: radius, startDeg: segStart, endDeg: segEnd, thickness: thickness, color: color);
  }
}

void _drawSpark(img.Image image, {required double cx, required double cy, required double size, required img.Color color}) {
  final pts = [
    img.Point(cx, cy - size),
    img.Point(cx + size * 0.24, cy - size * 0.24),
    img.Point(cx + size, cy),
    img.Point(cx + size * 0.24, cy + size * 0.24),
    img.Point(cx, cy + size),
    img.Point(cx - size * 0.24, cy + size * 0.24),
    img.Point(cx - size, cy),
    img.Point(cx - size * 0.24, cy - size * 0.24),
  ];
  img.fillPolygon(image, vertices: pts, color: color);
}

/// [outerRadius]를 기준으로 전체 도안 비율을 맞춰 그린다.
img.Image _buildIcon({required bool transparentBg, required double outerRadius}) {
  final image = img.Image(width: _size, height: _size, numChannels: 4);
  img.fill(image, color: transparentBg ? img.ColorRgba8(0, 0, 0, 0) : _bg);

  final ringOuter = outerRadius;
  final ringMid = outerRadius * 0.72;
  final ringInner = outerRadius * 0.42;
  final ringThickness = outerRadius * 0.055;

  // 우측(3시 방향)이 열려 있는 300도 부채꼴 — 나머지 60도가 트인 방향.
  const startDeg = 55.0;
  const endDeg = 355.0;

  _drawThickArc(image, radius: ringOuter, startDeg: startDeg, endDeg: endDeg, thickness: ringThickness, color: _withAlpha(_accentSoft, 0.5));
  _drawDashedArc(image, radius: ringMid, startDeg: startDeg, endDeg: endDeg, thickness: ringThickness, color: _withAlpha(_accentSoft, 0.75), dashCount: 8);
  _drawThickRing(image, radius: ringInner, thickness: ringThickness, color: _withAlpha(_accent, 0.9));

  // 감지된 두 점 + 연결선 — "커넥션"을 표현.
  final dotA = (
    x: _cx + ringOuter * 0.86 * cos(-28 * pi / 180),
    y: _cy + ringOuter * 0.86 * sin(-28 * pi / 180),
  );
  final dotB = (
    x: _cx + ringMid * 0.82 * cos(158 * pi / 180),
    y: _cy + ringMid * 0.82 * sin(158 * pi / 180),
  );

  img.drawLine(image, x1: _cx.round(), y1: _cy.round(), x2: dotA.x.round(), y2: dotA.y.round(), color: _withAlpha(_accent, 0.9), thickness: outerRadius * 0.015, antialias: true);
  img.drawLine(image, x1: _cx.round(), y1: _cy.round(), x2: dotB.x.round(), y2: dotB.y.round(), color: _withAlpha(_accent, 0.7), thickness: outerRadius * 0.015, antialias: true);

  img.fillCircle(image, x: dotA.x.round(), y: dotA.y.round(), radius: (outerRadius * 0.06).round(), color: _dark, antialias: true);
  img.fillCircle(image, x: dotB.x.round(), y: dotB.y.round(), radius: (outerRadius * 0.05).round(), color: _accent, antialias: true);

  // 감지 순간의 반짝임 — 아이콘의 시그니처 요소라 크고 진하게.
  _drawSpark(image, cx: dotA.x - outerRadius * 0.02, cy: dotA.y - outerRadius * 0.1, size: outerRadius * 0.1, color: _accent);

  // 중심 센서 점(나 자신) — 가장 마지막에 그려서 항상 위에 보이게 한다.
  img.fillCircle(image, x: _cx.round(), y: _cy.round(), radius: (outerRadius * 0.196).round(), color: _withAlpha(_accent, 0.22), antialias: true);
  img.fillCircle(image, x: _cx.round(), y: _cy.round(), radius: (outerRadius * 0.139).round(), color: _accent, antialias: true);

  return image;
}

void main() {
  final outDir = Directory('assets/icon');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  // iOS/Android 레거시 아이콘 — 동심원 크기를 10%씩 두 차례 줄여달라는 피드백으로
  // 460→414→373.
  final full = _buildIcon(transparentBg: false, outerRadius: 373);
  File('${outDir.path}/icon_full.png').writeAsBytesSync(img.encodePng(full));

  // Android adaptive icon foreground — 안전 영역 비율은 유지한 채 동일하게 축소(300→270→243).
  final foreground = _buildIcon(transparentBg: true, outerRadius: 243);
  File('${outDir.path}/icon_foreground.png').writeAsBytesSync(img.encodePng(foreground));

  stdout.writeln('Generated ${outDir.path}/icon_full.png and icon_foreground.png (1024x1024)');
}
