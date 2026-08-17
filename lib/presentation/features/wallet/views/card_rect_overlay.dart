import 'package:flutter/material.dart';

import '../../../../core/utils/card_quad_geometry.dart';

/// 검출된 명함 테두리를 화면에 그린다(B′).
///
/// 지금까지는 화면 한가운데 **고정된 가이드 상자**만 있었다. 사용자가 거기에
/// 명함을 맞춰야 했고, 맞췄는지는 스스로 판단해야 했다. 여기서는 **찾아낸
/// 명함 위에 테두리가 달라붙는다** — 앱이 무엇을 보고 있는지가 그대로 보인다.
///
/// ⚠️ **이 위젯은 판단하지 않는다.** 명함처럼 생겼는지는 이미 걸러진 뒤이고
/// ([judgeCardShape]), 여기 들어오는 것은 그릴 것뿐이다.
class CardRectOverlay extends StatelessWidget {
  const CardRectOverlay({
    super.key,
    required this.quad,
    required this.color,
    this.strokeWidth = 3,
  });

  /// **가시 좌표**(0~1)의 네 귀퉁이 — 화면에 보이는 영역 기준이다.
  final CardQuad quad;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: Size.infinite,
      painter: _CardRectPainter(
        quad: quad,
        color: color,
        strokeWidth: strokeWidth,
      ),
    ),
  );
}

class _CardRectPainter extends CustomPainter {
  const _CardRectPainter({
    required this.quad,
    required this.color,
    required this.strokeWidth,
  });

  final CardQuad quad;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad.corners
        .map(
          (corner) => Offset(corner.dx * size.width, corner.dy * size.height),
        )
        .toList();

    final path = Path()..addPolygon(points, true);

    // 안쪽을 살짝 밝혀 "이 영역을 찍는다"를 보이게 한다. 꽉 채우면 명함
    // 글자가 안 보여 초점이 맞았는지 사용자가 확인할 수 없다.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.12),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // 네 귀퉁이를 굵게 — 테두리만으로는 기울어진 정도가 잘 안 읽힌다.
    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var i = 0; i < 4; i++) {
      final current = points[i];
      final next = points[(i + 1) % 4];
      final previous = points[(i + 3) % 4];
      canvas.drawLine(current, _towards(current, next, 0.18), cornerPaint);
      canvas.drawLine(current, _towards(current, previous, 0.18), cornerPaint);
    }
  }

  /// [from]에서 [to] 쪽으로 [fraction]만큼 간 점.
  Offset _towards(Offset from, Offset to, double fraction) => Offset(
    from.dx + (to.dx - from.dx) * fraction,
    from.dy + (to.dy - from.dy) * fraction,
  );

  @override
  bool shouldRepaint(_CardRectPainter oldDelegate) =>
      oldDelegate.quad != quad ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
