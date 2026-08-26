import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show immutable;

/// 명함 자동 테두리 검출(B′)에서 쓰는 **순수 기하 계산**.
///
/// 왜 서비스가 아니라 여기에 있나: 검출 자체는 플랫폼 코드(iOS Vision ·
/// Android OpenCV)가 하지만, **그 결과를 화면과 사진에 맞춰 옮기는 계산은
/// 전부 Dart에서 한다.** 네이티브 코드는 `flutter test`로 못 돌리지만 이
/// 파일은 돌릴 수 있다 — 이 프로젝트에서 실제로 터진 결함이 "코드는 맞는데
/// 실물이 틀린" 유형이었던 만큼, **기계가 검사할 수 있는 부분은 최대한
/// 기계 쪽에 둔다.**
///
/// ⚠️ 좌표계가 셋이라 헷갈리기 쉽다. 이름을 정해 둔다.
///
/// | 이름 | 원점 | 범위 | 무엇 |
/// |---|---|---|---|
/// | **버퍼 좌표** | 왼쪽 위 | 0~1 | 카메라가 준 프레임. **화면과 방향이 다르다** |
/// | **표시 좌표** | 왼쪽 위 | 0~1 | 버퍼를 화면 방향으로 돌린 것 |
/// | **가시 좌표** | 왼쪽 위 | 0~1 | 화면에 **실제로 보이는 영역** 안에서의 위치 |
///
/// 가시 좌표가 중요한 이유: 프리뷰는 cover 방식(화면을 꽉 채우고 넘치는
/// 부분은 잘림)이라 **버퍼의 가장자리는 화면에 안 보인다.** 그런데 촬영
/// 결과물도 같은 방식으로 화면에 대응하므로, **가시 좌표는 프리뷰와 촬영본
/// 양쪽에 그대로 통한다** — 이 값 하나로 테두리도 그리고 크롭도 한다.

/// 검출된 사각형의 네 귀퉁이.
///
/// 좌표는 항상 **0~1 정규화**다. 어느 좌표계인지는 이 클래스가 모르므로
/// 부르는 쪽이 관리한다(위 표 참고).
@immutable
class CardQuad {
  const CardQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  /// 시계 방향 순서(왼쪽 위 → 오른쪽 위 → 오른쪽 아래 → 왼쪽 아래).
  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// 정규화 좌표를 실제 픽셀 위치로 편다.
  ///
  /// ⚠️ **길이·각도를 재려면 반드시 이걸 거쳐야 한다.** 정규화 좌표에서
  /// 그냥 거리를 재면 가로세로 비율이 1:1인 것처럼 계산돼 **가로로 긴
  /// 프레임에서 값이 크게 틀어진다.**
  List<Offset> toPixels(Size size) => [
    Offset(topLeft.dx * size.width, topLeft.dy * size.height),
    Offset(topRight.dx * size.width, topRight.dy * size.height),
    Offset(bottomRight.dx * size.width, bottomRight.dy * size.height),
    Offset(bottomLeft.dx * size.width, bottomLeft.dy * size.height),
  ];

  /// 네 점을 모두 감싸는 사각형(정규화 좌표).
  Rect get bounds {
    final xs = corners.map((c) => c.dx);
    final ys = corners.map((c) => c.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  CardQuad map(Offset Function(Offset) f) => CardQuad(
    topLeft: f(topLeft),
    topRight: f(topRight),
    bottomRight: f(bottomRight),
    bottomLeft: f(bottomLeft),
  );

  @override
  bool operator ==(Object other) =>
      other is CardQuad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'CardQuad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// 네이티브가 보낸 평평한 좌표 배열(x0,y0,x1,y1,...)을 [CardQuad]로 만든다.
///
/// 순서를 믿지 않고 **여기서 다시 정렬한다.** iOS Vision과 OpenCV가 귀퉁이를
/// 내놓는 순서가 서로 다르고(그리고 회전한 명함에서는 어느 쪽도 "왼쪽 위"를
/// 보장하지 않는다), 순서가 틀리면 **크롭 결과가 대각선으로 뒤집힌다.**
CardQuad? cardQuadFromFlat(List<double>? flat) {
  final quads = cardQuadsFromFlat(flat);
  return quads.isEmpty ? null : quads.first;
}

/// 여러 사각형이 담긴 평평한 배열을 나눠 [CardQuad] 목록으로 만든다.
///
/// ⚠️ **검출기는 사각형을 하나만 주지 않는다.** 책상 모서리·모니터·명함
/// 여러 장이 함께 잡히므로, 네이티브는 후보를 여러 개 넘기고 **어느 것이
/// 명함인지는 Dart가 고른다**([pickBestCardQuad]). 고르는 규칙을 Dart에
/// 두는 이유는 네이티브 코드가 `flutter test`로 검사되지 않기 때문이다.
///
/// 8개로 나누어떨어지지 않으면 **통째로 버린다** — 반쯤 읽으면 좌표가
/// 밀려 엉뚱한 사각형이 만들어진다.
List<CardQuad> cardQuadsFromFlat(List<double>? flat) {
  if (flat == null || flat.isEmpty || flat.length % 8 != 0) return const [];
  final quads = <CardQuad>[];
  for (var offset = 0; offset < flat.length; offset += 8) {
    final points = <Offset>[];
    var valid = true;
    for (var i = 0; i < 8; i += 2) {
      final x = flat[offset + i];
      final y = flat[offset + i + 1];
      if (!x.isFinite || !y.isFinite) {
        valid = false;
        break;
      }
      points.add(Offset(x, y));
    }
    // 한 후보가 망가져도 나머지는 살린다 — 검출기가 준 다른 후보가
    // 진짜 명함일 수 있다.
    if (valid) quads.add(sortCornersClockwise(points));
  }
  return quads;
}

/// 후보 여러 개 중 **명함일 가능성이 가장 높은 것**을 고른다.
///
/// 규칙: [judgeCardShape]를 통과한 것들 중 **가장 큰 것**. 화면에 크게
/// 잡힌 쪽이 사용자가 찍으려는 명함이다 — 뒤쪽 배경에 우연히 명함 비율로
/// 보이는 것보다 앞에 든 것이 크다.
///
/// 통과한 것이 하나도 없으면 null. **떨어진 후보 중 큰 것을 억지로 쓰지
/// 않는다** — 명함이 아닌 것을 찍는 것보다 안 찍히는 쪽이 낫다(셔터는
/// 언제든 직접 누를 수 있다).
CardQuad? pickBestCardQuad(
  List<CardQuad> quads,
  Size imageSize, {
  CardShapeCriteria criteria = const CardShapeCriteria(),
}) {
  CardQuad? best;
  var bestArea = 0.0;
  for (final quad in quads) {
    if (judgeCardShape(quad, imageSize, criteria: criteria) !=
        CardShapeVerdict.ok) {
      continue;
    }
    final area = cardQuadAreaFraction(quad);
    if (area > bestArea) {
      bestArea = area;
      best = quad;
    }
  }
  return best;
}

/// 네 점을 "왼쪽 위 → 오른쪽 위 → 오른쪽 아래 → 왼쪽 아래" 순서로 세운다.
///
/// 무게중심에서 본 각도로 돌려 세운다 — 명함이 기울어져 있어도 통한다.
/// (x+y가 가장 작은 점을 왼쪽 위로 잡는 흔한 방법은 **45° 근처로 기울면
/// 두 점이 뒤바뀐다.**)
CardQuad sortCornersClockwise(List<Offset> points) {
  assert(points.length == 4);
  final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / 4;
  final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / 4;
  final sorted = [...points]
    ..sort((a, b) {
      final angleA = math.atan2(a.dy - cy, a.dx - cx);
      final angleB = math.atan2(b.dy - cy, b.dx - cx);
      return angleA.compareTo(angleB);
    });
  // atan2는 -π(왼쪽)에서 시작해 시계 방향(화면 좌표는 y가 아래로 증가)으로
  // 돈다. 왼쪽 위가 -π에 가장 가까우므로 그 점을 처음으로 돌린다.
  var startIndex = 0;
  var best = double.infinity;
  for (var i = 0; i < 4; i++) {
    final p = sorted[i];
    final score = (p.dx - cx) + (p.dy - cy);
    if (score < best) {
      best = score;
      startIndex = i;
    }
  }
  final ordered = [
    sorted[startIndex],
    sorted[(startIndex + 1) % 4],
    sorted[(startIndex + 2) % 4],
    sorted[(startIndex + 3) % 4],
  ];
  return CardQuad(
    topLeft: ordered[0],
    topRight: ordered[1],
    bottomRight: ordered[2],
    bottomLeft: ordered[3],
  );
}

/// 버퍼 좌표를 표시 좌표로 돌린다(시계 방향 90° 단위).
///
/// 카메라 센서는 대개 가로로 누워 있어서, **폰을 세로로 들면 버퍼가 90°
/// 돌아간 채로 온다.** 이 값을 안 맞추면 테두리가 화면에서 엉뚱한 곳에
/// 그려진다 — 사람 눈에는 바로 보이지만, 그때는 이미 실기기까지 간 뒤다.
CardQuad rotateQuadClockwise(CardQuad quad, int quarterTurns) {
  final turns = ((quarterTurns % 4) + 4) % 4;
  if (turns == 0) return quad;
  Offset rotate(Offset p) {
    switch (turns) {
      case 1:
        return Offset(1 - p.dy, p.dx);
      case 2:
        return Offset(1 - p.dx, 1 - p.dy);
      default:
        return Offset(p.dy, 1 - p.dx);
    }
  }

  // 돌리고 나면 "왼쪽 위"가 더 이상 왼쪽 위가 아니므로 다시 세운다.
  return sortCornersClockwise(quad.corners.map(rotate).toList());
}

/// cover 방식으로 화면을 채울 때 이미지에서 **실제로 보이는 영역**(픽셀).
///
/// [_cropToGuideFrame]이 쓰던 계산과 같은 것을 함수로 꺼냈다 — 두 곳이
/// 각자 계산하면 언젠가 어긋난다.
Rect visibleImageRect(Size imageSize, Size screenSize) {
  final imgW = imageSize.width;
  final imgH = imageSize.height;
  final screenAspect = screenSize.width / screenSize.height;
  final imageAspect = imgW / imgH;

  double visibleW, visibleH;
  if (imageAspect > screenAspect) {
    visibleH = imgH;
    visibleW = imgH * screenAspect;
  } else {
    visibleW = imgW;
    visibleH = imgW / screenAspect;
  }
  return Rect.fromLTWH(
    (imgW - visibleW) / 2,
    (imgH - visibleH) / 2,
    visibleW,
    visibleH,
  );
}

/// 표시 좌표(이미지 전체 기준) → 가시 좌표(화면에 보이는 영역 기준).
///
/// 화면 밖으로 밀려난 부분은 0 미만이나 1 초과로 나온다 — **자르지 않는다.**
/// 명함이 화면 가장자리에 걸쳤는지를 부르는 쪽이 판단해야 하기 때문이다.
CardQuad displayQuadToVisibleQuad(
  CardQuad quad,
  Size imageSize,
  Size screenSize,
) {
  final visible = visibleImageRect(imageSize, screenSize);
  return quad.map((p) {
    final px = p.dx * imageSize.width;
    final py = p.dy * imageSize.height;
    return Offset(
      (px - visible.left) / visible.width,
      (py - visible.top) / visible.height,
    );
  });
}

/// 가시 좌표 → 촬영본 픽셀 좌표.
///
/// 프리뷰와 촬영본은 해상도가 다르지만 **같은 장면을 같은 cover 방식으로**
/// 화면에 맞추므로, 가시 좌표는 양쪽에 그대로 통한다.
List<Offset> visibleQuadToImagePixels(
  CardQuad quad,
  Size imageSize,
  Size screenSize,
) {
  final visible = visibleImageRect(imageSize, screenSize);
  return quad.corners
      .map(
        (p) => Offset(
          visible.left + p.dx * visible.width,
          visible.top + p.dy * visible.height,
        ),
      )
      .toList();
}

/// 검출된 사각형이 **명함처럼 생겼는지** 판정한다.
///
/// ⚠️ 이 판정이 B′의 핵심이다. 아이폰 A안(VisionKit)에서 **여러 장을 한꺼번에
/// 잡던 문제**가 여기서 걸러진다 — 검출기는 "사각형"이면 뭐든 내놓으므로,
/// 명함이 아닌 것(책상 모서리·모니터·명함 여러 장을 묶은 큰 사각형)은
/// 우리가 떨어뜨려야 한다.
///
/// | 조건 | 값 | 왜 |
/// |---|---|---|
/// | 가로세로비 | **1.35~2.15** | 아래 참고 — ⚠️ 스펙의 1.3~1.7은 **표준 명함을 배제하는 범위였다** |
/// | 직각 오차 | 기본 **25°** | 비스듬히 찍으면 직각이 아니게 보인다. 그래도 사다리꼴 이상으로 무너지면 명함이 아니다 |
/// | 최소 넓이 | 프레임의 **2%** | 너무 작으면 뒤쪽 배경의 무언가다 |
///
/// ## ⚠️ 최소 넓이는 **한 번 틀렸다** (2026-08-16)
///
/// 처음에 **15%**로 잡았다. 실기기에 붙여 보니 **명함을 가이드에 꽉 채워도
/// 전부 `tooSmall`로 떨어졌다.**
///
/// 실측(아이폰 화면 캡처 1206×2622):
///
/// | | 값 |
/// |---|---|
/// | 가이드 상자 | 약 445×775 = **화면의 10.9%** |
/// | 카메라 프레임 | 3024×4032 (화면보다 가로로 넓어 좌우가 잘림) |
/// | 프레임 기준 환산 | 약 **6.7%** |
///
/// **15%는 계산이었고, 실물은 그 절반 이하였다.** 이 저장소가 자동 촬영
/// 임계값에서 두 번 겪은 것과 **같은 자리, 같은 실수**다 — 숫자만 보고 세운
/// 가설이 실제 화면 기하를 반영하지 못했다.
///
/// 그래서 **실측값(6.7%)보다 넉넉히 아래인 2%**로 잡는다. 사용자가 명함을
/// 조금 멀리 들어도 통과하고, 배경에 있는 자잘한 사각형은 여전히 걸린다.
/// ⚠️ **더 올리려면 먼저 재라.**
/// ## ⚠️ 가로세로비도 틀렸다 — **스펙의 숫자가 표준 명함을 배제했다** (2026-08-16)
///
/// 스펙과 인계 문서가 **1.3~1.7**로 적어 놨다. 실기기에 붙이니 명함이 전부
/// `aspectOutOfRange`로 떨어졌다.
///
/// | 근거 | 값 |
/// |---|---|
/// | 국내 명함 표준 90×50mm | **1.80** |
/// | 앞 세션 실측(A안 크롭 2건) | **1.828 / 1.821** |
/// | 신용카드 85.6×54 | 1.586 |
/// | 스펙이 적어 둔 범위 | ~~1.3~1.7~~ ← **1.8이 안 들어간다** |
///
/// 📌 **답은 이미 우리 손에 있었다.** PM이 인계해 준 실측값이 1.828·1.821
/// 이었는데, 스펙의 범위와 어긋난다는 것을 아무도 대조하지 않았다.
///
/// **1.35~2.15로 넓힌다.** 아래를 1.35까지 낮추는 것은 비스듬히 찍어 원근으로
/// 눌린 경우(짧아 보인다)를 받기 위함이고, 위를 2.15로 두는 것은 실측 1.83에
/// 검출 오차와 기울기를 얹은 값이다. 명함 두 장을 한 덩어리로 잡으면 3 이상이라
/// 여전히 걸린다.
class CardShapeCriteria {
  const CardShapeCriteria({
    this.minAspectRatio = 1.35,
    this.maxAspectRatio = 2.15,
    this.maxCornerDeviationDegrees = 25.0,
    this.minAreaFraction = 0.02,
  });

  final double minAspectRatio;
  final double maxAspectRatio;
  final double maxCornerDeviationDegrees;
  final double minAreaFraction;
}

/// [CardShapeCriteria]로 걸러낸 결과. 왜 떨어졌는지까지 남긴다.
///
/// ⚠️ 떨어진 이유를 안 남기면 실기기에서 "왜 안 잡히지"를 추측하게 된다 —
/// 이 프로젝트가 자동 촬영 게이트에서 이미 겪은 일이다(대비인 줄 알았는데
/// 실제로 막은 건 톤 비율이었다).
enum CardShapeVerdict {
  ok,

  /// 가로세로비가 명함 범위를 벗어남 — 명함 여러 장을 한 덩어리로 잡았거나
  /// 모니터·서류처럼 다른 것을 잡은 경우.
  aspectOutOfRange,

  /// 네 각이 직각에서 너무 벗어남 — 사각형이 아니라 그림자·무늬였을 가능성.
  notRectangular,

  /// 너무 작음 — 배경에 있는 다른 물건.
  tooSmall,
}

/// 사각형의 긴 변 / 짧은 변.
double cardQuadAspectRatio(CardQuad quad, Size imageSize) {
  final p = quad.toPixels(imageSize);
  final top = (p[1] - p[0]).distance;
  final right = (p[2] - p[1]).distance;
  final bottom = (p[2] - p[3]).distance;
  final left = (p[3] - p[0]).distance;
  final horizontal = (top + bottom) / 2;
  final vertical = (right + left) / 2;
  if (horizontal <= 0 || vertical <= 0) return 0;
  return math.max(horizontal, vertical) / math.min(horizontal, vertical);
}

/// 네 각이 직각에서 얼마나 벗어났는지(도) 중 **가장 큰 값**.
double cardQuadMaxCornerDeviation(CardQuad quad, Size imageSize) {
  final p = quad.toPixels(imageSize);
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    final prev = p[(i + 3) % 4];
    final current = p[i];
    final next = p[(i + 1) % 4];
    final a = prev - current;
    final b = next - current;
    final lenA = a.distance;
    final lenB = b.distance;
    if (lenA == 0 || lenB == 0) return 180;
    final cos = ((a.dx * b.dx + a.dy * b.dy) / (lenA * lenB)).clamp(-1.0, 1.0);
    final degrees = math.acos(cos) * 180 / math.pi;
    worst = math.max(worst, (degrees - 90).abs());
  }
  return worst;
}

/// 사각형의 넓이가 이미지 전체에서 차지하는 비율(0~1).
double cardQuadAreaFraction(CardQuad quad) {
  // 신발끈 공식. 정규화 좌표 그대로 쓰면 "전체 대비 비율"이 바로 나온다.
  final c = quad.corners;
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = c[i];
    final b = c[(i + 1) % 4];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return (sum / 2).abs();
}

CardShapeVerdict judgeCardShape(
  CardQuad quad,
  Size imageSize, {
  CardShapeCriteria criteria = const CardShapeCriteria(),
}) {
  if (cardQuadAreaFraction(quad) < criteria.minAreaFraction) {
    return CardShapeVerdict.tooSmall;
  }
  if (cardQuadMaxCornerDeviation(quad, imageSize) >
      criteria.maxCornerDeviationDegrees) {
    return CardShapeVerdict.notRectangular;
  }
  final ratio = cardQuadAspectRatio(quad, imageSize);
  if (ratio < criteria.minAspectRatio || ratio > criteria.maxAspectRatio) {
    return CardShapeVerdict.aspectOutOfRange;
  }
  return CardShapeVerdict.ok;
}

/// 원근 보정에 쓸 **사영 변환 행렬**을 구한다(목적지 → 원본 방향).
///
/// 왜 이 방향인가: 결과 이미지의 픽셀을 하나씩 돌면서 "이 점은 원본의 어디
/// 였나"를 물어야 구멍이 안 생긴다. 반대 방향으로 하면 원본 픽셀이 목적지에
/// 듬성듬성 떨어져 **줄무늬가 생긴다.**
///
/// 8개 미지수를 가우스 소거로 푼다. 실패하면(네 점이 한 줄에 있는 등)
/// null — 부르는 쪽이 기존 크롭으로 되돌아간다.
List<double>? perspectiveTransform(
  List<Offset> source,
  List<Offset> destination,
) {
  assert(source.length == 4 && destination.length == 4);
  // [a b c; d e f; g h 1] 를 구한다. 목적지(x,y) → 원본(u,v).
  final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = destination[i].dx;
    final y = destination[i].dy;
    final u = source[i].dx;
    final v = source[i].dy;

    matrix[i * 2] = [x, y, 1, 0, 0, 0, -x * u, -y * u, u];
    matrix[i * 2 + 1] = [0, 0, 0, x, y, 1, -x * v, -y * v, v];
  }

  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var row = col + 1; row < 8; row++) {
      if (matrix[row][col].abs() > matrix[pivot][col].abs()) pivot = row;
    }
    if (matrix[pivot][col].abs() < 1e-10) return null;
    final tmp = matrix[col];
    matrix[col] = matrix[pivot];
    matrix[pivot] = tmp;

    final pivotValue = matrix[col][col];
    for (var c = col; c < 9; c++) {
      matrix[col][c] /= pivotValue;
    }
    for (var row = 0; row < 8; row++) {
      if (row == col) continue;
      final factor = matrix[row][col];
      if (factor == 0) continue;
      for (var c = col; c < 9; c++) {
        matrix[row][c] -= factor * matrix[col][c];
      }
    }
  }

  final result = [for (var i = 0; i < 8; i++) matrix[i][8], 1.0];
  if (result.any((v) => !v.isFinite)) return null;
  return result;
}

/// [perspectiveTransform]으로 구한 행렬로 점 하나를 옮긴다.
Offset applyPerspective(List<double> m, Offset p) {
  final denominator = m[6] * p.dx + m[7] * p.dy + m[8];
  if (denominator == 0) return Offset.zero;
  return Offset(
    (m[0] * p.dx + m[1] * p.dy + m[2]) / denominator,
    (m[3] * p.dx + m[4] * p.dy + m[5]) / denominator,
  );
}

/// 원근 보정 결과물의 크기를 정한다.
///
/// ⚠️ **여기가 축소 임계(긴 변 1,600px)와 만나는 자리다.** 잘라낸 결과가
/// 1,600을 안 넘으면 `contact_image_service`가 축소를 건너뛰고, 그러면
/// 저장본이 커져 **2,000장 한도의 비용 근거가 흔들린다**(인계 문서 5절).
///
/// 그래서 **검출된 사각형의 실제 픽셀 크기를 그대로 쓴다** — 임의로 정한
/// 값으로 늘리거나 줄이지 않는다. 실제로 몇 px이 나오는지는 **실기기에서
/// 재야 안다.** 재기 전에는 이 함수가 무엇을 내놓는지 단정하지 않는다.
Size perspectiveOutputSize(List<Offset> sourcePixels) {
  final top = (sourcePixels[1] - sourcePixels[0]).distance;
  final bottom = (sourcePixels[2] - sourcePixels[3]).distance;
  final left = (sourcePixels[3] - sourcePixels[0]).distance;
  final right = (sourcePixels[2] - sourcePixels[1]).distance;
  final width = math.max(top, bottom).round().clamp(1, 20000);
  final height = math.max(left, right).round().clamp(1, 20000);
  return Size(width.toDouble(), height.toDouble());
}

// ── 손으로 자르기(F-03, 추가 290) ────────────────────────────────────────
//
// 확인 화면은 사진을 `BoxFit.contain`으로 그린다(전체가 보여야 귀퉁이를 끌 수
// 있으므로). 프리뷰의 cover 방식과 **맞추는 규칙이 다르다** — 그래서 위쪽
// [visibleImageRect]를 그대로 쓸 수 없다.
//
// ⚠️ 두 규칙을 한 함수로 합치려다 실기기에서 좌표가 어긋난 적이 있다.
// **따로 두고 이름으로 구분한다.**

/// `BoxFit.contain`으로 [boxSize] 안에 그렸을 때 **이미지가 실제로 차지하는
/// 사각형**(상자 좌표).
///
/// 남는 자리는 위아래 또는 좌우에 띠로 남는다(레터박스).
Rect containImageRect(Size imageSize, Size boxSize) {
  if (imageSize.width <= 0 ||
      imageSize.height <= 0 ||
      boxSize.width <= 0 ||
      boxSize.height <= 0) {
    return Rect.fromLTWH(0, 0, boxSize.width, boxSize.height);
  }
  final scale = math.min(
    boxSize.width / imageSize.width,
    boxSize.height / imageSize.height,
  );
  final w = imageSize.width * scale;
  final h = imageSize.height * scale;
  return Rect.fromLTWH((boxSize.width - w) / 2, (boxSize.height - h) / 2, w, h);
}

/// 상자 좌표 → **이미지 정규 좌표(0~1)**.
///
/// ⚠️ 0~1로 **자른다**(clamp). 손가락이 사진 밖으로 나가도 귀퉁이는 사진
/// 안에 머물러야 한다 — 밖으로 나간 귀퉁이로 자르면 검은 띠가 섞여 들어온다.
Offset containPointToImageNormalized(
  Offset boxPoint,
  Size imageSize,
  Size boxSize,
) {
  final rect = containImageRect(imageSize, boxSize);
  if (rect.width <= 0 || rect.height <= 0) return Offset.zero;
  return Offset(
    ((boxPoint.dx - rect.left) / rect.width).clamp(0.0, 1.0),
    ((boxPoint.dy - rect.top) / rect.height).clamp(0.0, 1.0),
  );
}

/// 이미지 정규 좌표(0~1) → 상자 좌표. 귀퉁이 손잡이를 그릴 때 쓴다.
Offset imageNormalizedToContainPoint(
  Offset normalized,
  Size imageSize,
  Size boxSize,
) {
  final rect = containImageRect(imageSize, boxSize);
  return Offset(
    rect.left + normalized.dx * rect.width,
    rect.top + normalized.dy * rect.height,
  );
}

// ── 자동 촬영 관문(E-01, 추가 293) ──────────────────────────────────────

/// 자동 촬영에 **"명함이 잡혔을 것"을 요구할지** 정한다.
///
/// ## ⚠️ 2026-08-17 — 시간이 아니라 **검출기 상태**로 정한다 (추가 293)
///
/// 처음에는 *"몇 초 안에 못 잡으면 조건을 풀어 준다"*로 만들었다. 검출이 안
/// 되는 기기에서 자동 촬영을 통째로 잃지 않게 하려던 것이다.
///
/// **실기기에서 그게 막으려던 것을 그대로 통과시켰다** — 빈 벽과 손바닥을
/// **6초만 비추면 자동으로 찍혔다.** 유예가 곧 "6초 뒤에는 아무거나 찍는다"였다.
///
/// 그래서 기준을 바꿨다. **검출기가 살아서 답하고 있으면 명함을 요구한다.**
/// 시간은 보지 않는다.
///
/// | 검출기 상태 | 요구하나 | 왜 |
/// |---|---|---|
/// | 살아서 답한다 | **요구한다** | 못 잡는 것은 **거기 명함이 없다**는 뜻이다 |
/// | 아직 첫 답이 안 왔다 | 안 한다 | 화면을 막 열었을 때 잠깐 |
/// | 없거나 오류다 | 안 한다 | ⚠️ 못 쓰는 장치로 사용자를 막으면 안 된다 |
///
/// ## ⚠️ 못 잡으면 자동 촬영이 안 되는 것은 **의도한 것**이다
///
/// 그게 E-01(*"빈 공간을 찍음"*)을 닫는 방법이다. 빠져나갈 길은 시간이 아니라
/// **셔터 버튼**이다 — 화면 한가운데 크게 있고, 누르면 언제든 찍힌다.
bool requiresCardRectGate({
  required bool supported,
  required bool detectorDisabled,
  required bool detectorAnswering,
}) {
  if (!supported || detectorDisabled) return false;
  return detectorAnswering;
}
