import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 앱 아이콘(커넥션센스)의 신호 링 모티프를 아주 옅은 배경 장식으로 재사용한다.
/// 화면 우상단 바깥쪽에 중심을 두고 일부만 걸치게 그려서, 콘텐츠를 가리지
/// 않으면서 브랜드 아이덴티티를 은은하게 드러낸다(불투명도 5~9%로 낮게 유지).
class ConnectionSenseBackgroundPainter extends CustomPainter {
  const ConnectionSenseBackgroundPainter();

  static const _dashCount = 14;
  static const _dashDeg = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.86, size.height * 0.08);
    final outerRadius = size.width * 0.62;
    final midRadius = outerRadius * 0.72;
    final innerRadius = outerRadius * 0.44;
    final strokeWidth = outerRadius * 0.045;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(
      center,
      outerRadius,
      ringPaint..color = AppColors.accentText.withValues(alpha: 0.05),
    );
    _drawDashedRing(
      canvas,
      center,
      midRadius,
      strokeWidth,
      AppColors.accentText.withValues(alpha: 0.07),
    );
    canvas.drawCircle(
      center,
      innerRadius,
      ringPaint..color = AppColors.accentText.withValues(alpha: 0.09),
    );
  }

  void _drawDashedRing(
    Canvas canvas,
    Offset center,
    double radius,
    double strokeWidth,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _dashCount; i++) {
      final centerDeg = i * (360 / _dashCount);
      final a1 = (centerDeg - _dashDeg / 2) * pi / 180;
      final a2 = (centerDeg + _dashDeg / 2) * pi / 180;
      final p1 = center + Offset(radius * cos(a1), radius * sin(a1));
      final p2 = center + Offset(radius * cos(a2), radius * sin(a2));
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionSenseBackgroundPainter oldDelegate) =>
      false;
}
