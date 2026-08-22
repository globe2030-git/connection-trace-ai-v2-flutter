/// 촬영 가이드의 **모서리 표식**(추가 387).
///
/// ## 왜 네 변을 지웠나
///
/// 자르기는 이미 **검출된 명함 테두리**를 따라간다(`cardRectCropEnabled`,
/// 2026-08-17 사용자 확정). 그러니 가이드를 꽉 채울 이유가 없다 — 넉넉한 틀
/// 안에 대충 두기만 하면 파란 테두리가 명함을 찾아 그 자리로 자른다.
///
/// 그런데 사용자는 *"맞추기 불편"*이라고 했다. 이유는 생김새였다.
///
/// > **네 변이 다 그려진 직사각형은 "채우라"는 신호다.** 실제 뜻은 *"이 안쪽
/// > 어딘가에 두세요"*인데, 그림이 다른 말을 하고 있었다.
///
/// 그래서 네 변을 지우고 **귀퉁이 갈고리 넷**만 남긴다. 크기는 그대로다 —
/// 추가 383이 플랫폼별로(iOS 50% · Android 65% · 상한 267dp) 재고 실기기
/// 확인까지 받은 값이라 **건드리지 않는다.**
///
/// ## ⚠️ 언제 쓰면 안 되는가
///
/// **자르기가 가이드 기준일 때는 네 변을 그대로 둔다.** 그때는 이 상자가
/// 진짜로 잘리는 자리라 *"채우세요"*가 맞는 말이다. 추가 293에서 실기기
/// 지적으로 *"실제로 잘리는 자리를 흐리게 만들면 안 된다"*고 정한 것과 같은
/// 이유다. 부르는 쪽이 `cardRectCropEnabled`를 보고 갈라 준다.
library;

import 'package:flutter/material.dart';

/// 갈고리 한 팔의 길이(논리 픽셀).
///
/// 가이드가 작으면 팔이 너무 길어 네 변처럼 보이고, 크면 점처럼 보인다. 그래서
/// **짧은 변에 비례**시키되 위아래로 묶는다.
///
/// ⚠️ 0.18·16·44는 **고른 값이지 잰 값이 아니다.** 실기기에서 "안 채워도
/// 된다"가 전달되는지 확인한 뒤 조정한다 — 387의 성패가 그 확인 하나에 달려
/// 있다.
double guideCornerArmLength(Size guideSize) {
  final shortEdge = guideSize.width < guideSize.height
      ? guideSize.width
      : guideSize.height;
  if (shortEdge <= 0) return 0;
  final arm = shortEdge * kGuideCornerArmRatio;
  if (arm < kGuideCornerArmMin) return kGuideCornerArmMin;
  if (arm > kGuideCornerArmMax) return kGuideCornerArmMax;
  return arm;
}

/// 짧은 변 대비 갈고리 팔 길이.
const double kGuideCornerArmRatio = 0.18;

/// 팔 길이 하한 — 이보다 짧으면 모서리가 "점"으로 보여 틀로 안 읽힌다.
const double kGuideCornerArmMin = 16;

/// 팔 길이 상한 — 이보다 길면 네 변이 이어진 것처럼 보여 다시 "채우세요"가
/// 된다. **이 값이 이 화면의 목적을 지킨다.**
const double kGuideCornerArmMax = 44;

/// 네 귀퉁이에 갈고리를 그린다. 상자의 둥근 모서리(radius)를 따라간다.
class GuideCornerMarksPainter extends CustomPainter {
  const GuideCornerMarksPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final arm = guideCornerArmLength(size);
    if (arm <= 0) return;

    // 팔이 모서리 곡선보다 짧으면 곡선만 그리게 되어 갈고리로 안 보인다.
    final r = radius > arm ? arm : radius;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // 왼쪽 위
    path
      ..moveTo(0, r + arm)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(r + arm, 0);
    // 오른쪽 위
    path
      ..moveTo(w - r - arm, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, r + arm);
    // 오른쪽 아래
    path
      ..moveTo(w, h - r - arm)
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(w - r - arm, h);
    // 왼쪽 아래
    path
      ..moveTo(r + arm, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, h - r - arm);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(GuideCornerMarksPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius;
}
