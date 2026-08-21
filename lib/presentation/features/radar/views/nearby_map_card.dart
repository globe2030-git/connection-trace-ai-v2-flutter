import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../utils/nearby_map_layout.dart';
import '../view_models/radar_view_model.dart';

/// 주변 홈 지도 카드(⑥-C, 2026-08-21 확정) — 기존 "지금 가까운 사람 N명"
/// 요약 카드를 대신한다.
///
/// **실제 지도 타일이 아니다.** 배경은 [_MapBackgroundPainter]가 그린 장식용
/// 지도풍 그래픽이고, 점 위치는 [computeNearbyMapDots]가 계산한 거리·방위
/// 기준 배치다 — 외부 지도 사업자에게 어떤 요청도 나가지 않는다(방침 10-3이
/// 이 구현의 전제, `_NearbyCountCard`의 map.jpg를 대신하는 이유와 같다).
///
/// 카드를 탭하면 **기존과 같은 동작**(위치 새로고침)을 하고, "지도로 보기"
/// 버튼만 실제 지도 화면을 연다 — 이 둘을 같은 탭 영역에 겹쳐 두면 어느
/// 쪽 탭인지 제스처 아레나가 갈라 먹는 문제가 생겨, 버튼을 지도 영역
/// 바깥(하단 띠)에 따로 뒀다.
class NearbyMapCard extends StatelessWidget {
  const NearbyMapCard({
    super.key,
    required this.locationAccessState,
    required this.origin,
    required this.contactsSortedByDistance,
    required this.radiusMeters,
    required this.isRefreshing,
    required this.onTap,
    required this.onOpenMap,
  });

  /// 위치 자체를 아직 못 쓰는 상태(동의 전·거부·권한 없음 등)를 가리기 위해
  /// 쓴다. [origin]이 없을 때의 빈 상태 문구를 상태별로 구체화한다.
  final LocationAccessState locationAccessState;

  final GeoPosition? origin;

  /// 가까운 순으로 이미 정렬된 반경 안 인맥. 좌표 없는 인맥은 호출부가
  /// 미리 걸러 넘긴다(이 카드는 "거리·방위"만 다룬다).
  final List<ContactModel> contactsSortedByDistance;

  /// 감지 반경. `double.infinity`("전체")면 카드 안에서
  /// [resolveDisplayRadiusMeters]로 표시용 척도를 다시 정한다.
  final double radiusMeters;

  final bool isRefreshing;

  /// 카드(지도 영역) 탭 — 기존 요약 카드와 동일하게 위치 새로고침/상태별
  /// 동작(`handleLocationAccessAction`)을 그대로 잇는다.
  final VoidCallback? onTap;

  /// "지도로 보기" — 실제 지도 화면(`NearbyMapView`)을 연다.
  final VoidCallback onOpenMap;

  static const double height = 300;

  @override
  Widget build(BuildContext context) {
    final hasOrigin = origin != null;
    final displayRadius = hasOrigin
        ? resolveDisplayRadiusMeters(
            selectedRadiusMeters: radiusMeters,
            distancesMeters: contactsSortedByDistance
                .map((c) => GeoUtils.getDistanceMeters(origin, c.geo))
                .toList(),
          )
        : 1000.0;
    final dots = hasOrigin
        ? computeNearbyMapDots(
            origin: origin!,
            contactsSortedByDistance: contactsSortedByDistance,
            displayRadiusMeters: displayRadius,
          )
        : const <MapDotPlacement>[];

    final count = hasOrigin ? contactsSortedByDistance.length : null;

    return Semantics(
      container: true,
      label: hasOrigin
          ? '주변 지도 카드, 감지된 인맥 ${contactsSortedByDistance.length}명. 실제 지도가 아니라 거리·방향 기준 표시입니다.'
          : '주변 지도 카드, 위치를 아직 사용할 수 없습니다.',
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderFunctional),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Expanded(
                child: InkWell(
                  onTap: isRefreshing ? null : onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ExcludeSemantics(
                        child: RepaintBoundary(
                          child: CustomPaint(painter: _MapBackgroundPainter()),
                        ),
                      ),
                      if (hasOrigin)
                        ExcludeSemantics(
                          child: CustomPaint(
                            painter: _RadiusRingsPainter(
                              radiusMeters: displayRadius,
                            ),
                          ),
                        ),
                      if (hasOrigin)
                        ExcludeSemantics(
                          child: _DotsLayer(dots: dots),
                        ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _CountPill(
                          count: count,
                          isRefreshing: isRefreshing,
                        ),
                      ),
                      if (!hasOrigin)
                        const _MapEmptyMessage(
                          text: '위치를 사용하면 주변 인맥을 이 지도 위에 표시해요',
                        )
                      else if (dots.isEmpty)
                        const _MapEmptyMessage(
                          text: '지금 반경 안에 감지된 인맥이 없어요',
                        ),
                    ],
                  ),
                ),
              ),
              _BottomStrip(onOpenMap: onOpenMap),
            ],
          ),
        ),
      ),
    );
  }
}

/// 왼쪽 위 "N명 감지됨" 알약. 새로고침 중에는 숫자 대신 진행 표시기.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.isRefreshing});

  final int? count;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRefreshing) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            count != null ? '$count명 감지됨' : '위치 확인 중',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.accentText,
            ),
          ),
        ],
      ),
    );
  }
}

/// 지도 영역 가운데에 얹는 빈 상태 문구 — 위치 없음/근처 0명 공용.
class _MapEmptyMessage extends StatelessWidget {
  const _MapEmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

/// 하단 띠 — 과장 금지 문구("실제 지도가 아님")와 "지도로 보기" 버튼.
/// 지도 탭 영역과 겹치지 않는 별도 구획이라 두 탭이 서로를 가리지 않는다.
class _BottomStrip extends StatelessWidget {
  const _BottomStrip({required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardSurface,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          // 과장 금지 원칙 — 이 카드가 실제 지도가 아니라는 사실은 빼지
          // 않는다(브리프 4항, "이 문구는 빼지 않는다").
          const Expanded(
            child: Text(
              '거리·방향 기준 표시 (실제 지도가 아님)',
              maxLines: 2,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
                height: 1.3,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onOpenMap,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentText,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.zoom_out_map, size: 16),
            label: const Text(
              '지도로 보기',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// 점 목록을 실제 픽셀 좌표로 옮겨 그리는 레이어.
/// [computeNearbyMapDots]의 정규화 좌표(-1~1)에 [_ringRadiusPx]를 곱한다 —
/// 링과 반드시 같은 반지름 계산식을 써야 "링 안쪽 = 반경 안"이 맞는다.
class _DotsLayer extends StatelessWidget {
  const _DotsLayer({required this.dots});

  final List<MapDotPlacement> dots;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size.width / 2, size.height / 2);
        final r = _ringRadiusPx(size);
        return Stack(
          children: [
            for (final dot in dots)
              Positioned(
                left: center.dx + dot.dx * r - _dotDiameter(dot) / 2,
                top: center.dy + dot.dy * r - _dotDiameter(dot) / 2,
                child: _Dot(dot: dot),
              ),
          ],
        );
      },
    );
  }

  double _dotDiameter(MapDotPlacement dot) => dot.isBadge ? 26 : 30;
}

class _Dot extends StatelessWidget {
  const _Dot({required this.dot});

  final MapDotPlacement dot;

  @override
  Widget build(BuildContext context) {
    final diameter = dot.isBadge ? 26.0 : 30.0;
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dot.isBadge ? AppColors.accentText : Colors.white,
        border: Border.all(
          color: dot.isBadge ? Colors.white : AppColors.accentText,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        dot.label,
        maxLines: 1,
        style: TextStyle(
          fontSize: dot.isBadge ? 12 : 13,
          fontWeight: FontWeight.w800,
          color: dot.isBadge ? Colors.white : AppColors.accentText,
        ),
      ),
    );
  }
}

/// 링·점이 함께 쓰는 반지름 계산 — 카드 가로세로 중 짧은 쪽을 기준으로
/// 삼아 카드가 정사각형이 아니어도 원이 잘리지 않게 한다.
double _ringRadiusPx(Size size) {
  const padding = 34.0; // 가장 바깥 링 라벨이 카드 테두리에 안 닿을 여백.
  return (size.shortestSide / 2) - padding;
}

/// 반경 동심원. 가장 바깥 링에만 실제 거리를 적어 둔다(모든 링에 라벨을
/// 적으면 점·이름과 겹쳐 오히려 읽기 어렵다).
class _RadiusRingsPainter extends CustomPainter {
  const _RadiusRingsPainter({required this.radiusMeters});

  final double radiusMeters;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = _ringRadiusPx(size);
    if (maxR <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.accentText.withValues(alpha: 0.35);

    const ringFractions = [1 / 3, 2 / 3, 1.0];
    for (final f in ringFractions) {
      canvas.drawCircle(center, maxR * f, paint);
    }

    final label = _formatRingLabel(radiusMeters);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - maxR - tp.height - 2),
    );
  }

  static String _formatRingLabel(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)}km';
  }

  @override
  bool shouldRepaint(covariant _RadiusRingsPainter oldDelegate) =>
      oldDelegate.radiusMeters != radiusMeters;
}

/// 사실적 지도풍 배경 — **번들 그래픽이지 실제 지도 타일이 아니다.**
///
/// 크림 바탕에 테두리 있는 흰 도로망(간선은 노란 중앙선), 건물 발자국,
/// 공원 녹지, 물길을 고정된 구도로 그린다. 카드 크기가 기기마다 달라도
/// 비율이 깨지지 않도록 400×300 가상 좌표계에서 그린 뒤
/// [Canvas.scale]로 실제 카드 크기에 맞춘다 — 지리적 정확도가 필요한
/// 그림이 아니라 장식이므로 가로세로 비율이 살짝 눌리거나 늘어나도 무방하다.
class _MapBackgroundPainter extends CustomPainter {
  const _MapBackgroundPainter();

  static const _designWidth = 400.0;
  static const _designHeight = 300.0;

  // 장식용 팔레트 — 앱 시맨틱 토큰(AppColors)과는 별개다. 실제 지도 그래픽을
  // 흉내 내야 해서 브랜드 2색 원칙 대신 지도 관용색(크림·아스팔트 흰색·
  // 간선 노랑·공원 녹색·물 파랑)을 쓴다.
  static const _cream = Color(0xFFF3ECDD);
  static const _roadFill = Color(0xFFFFFFFF);
  static const _roadBorder = Color(0xFFD8CFB8);
  static const _roadCenterline = Color(0xFFF4C430);
  static const _buildingFill = Color(0xFFE4DAC3);
  static const _buildingBorder = Color(0xFFCFC2A2);
  static const _parkFill = Color(0xFFCFE3C4);
  static const _waterFill = Color(0xFFBBDCEF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.scale(size.width / _designWidth, size.height / _designHeight);

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _designWidth, _designHeight),
      Paint()..color = _cream,
    );

    // 물길 — 왼쪽 아래 모서리를 가로지르는 굽은 띠.
    final waterPath = Path()
      ..moveTo(-10, 260)
      ..quadraticBezierTo(60, 230, 120, 260)
      ..quadraticBezierTo(170, 285, 230, 270)
      ..lineTo(230, 320)
      ..lineTo(-10, 320)
      ..close();
    canvas.drawPath(waterPath, Paint()..color = _waterFill);

    // 공원 — 오른쪽 위의 둥근 녹지.
    canvas.drawOval(
      const Rect.fromLTWH(260, -20, 150, 130),
      Paint()..color = _parkFill,
    );

    _drawBuildings(canvas);
    _drawRoads(canvas);

    canvas.restore();
  }

  void _drawBuildings(Canvas canvas) {
    final fill = Paint()..color = _buildingFill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _buildingBorder;
    const footprints = [
      Rect.fromLTWH(40, 40, 46, 34),
      Rect.fromLTWH(100, 30, 30, 30),
      Rect.fromLTWH(40, 120, 36, 40),
      Rect.fromLTWH(150, 160, 50, 34),
      Rect.fromLTWH(220, 90, 34, 46),
      Rect.fromLTWH(300, 190, 40, 30),
      Rect.fromLTWH(60, 220, 40, 26),
      Rect.fromLTWH(330, 60, 30, 26),
    ];
    for (final rect in footprints) {
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, border);
    }
  }

  void _drawRoads(Canvas canvas) {
    // 간선 도로 두 개(가로/세로 큰 길) — 노란 중앙선이 있는 넓은 도로.
    _drawRoad(
      canvas,
      Path()
        ..moveTo(-10, 150)
        ..lineTo(410, 145),
      width: 18,
      arterial: true,
    );
    _drawRoad(
      canvas,
      Path()
        ..moveTo(180, -10)
        ..lineTo(190, 310),
      width: 16,
      arterial: true,
    );
    // 이면도로 — 얇고 중앙선 없음.
    _drawRoad(
      canvas,
      Path()
        ..moveTo(-10, 70)
        ..lineTo(410, 75),
      width: 8,
      arterial: false,
    );
    _drawRoad(
      canvas,
      Path()
        ..moveTo(-10, 220)
        ..lineTo(410, 225),
      width: 8,
      arterial: false,
    );
    _drawRoad(
      canvas,
      Path()
        ..moveTo(90, -10)
        ..lineTo(85, 310),
      width: 8,
      arterial: false,
    );
    _drawRoad(
      canvas,
      Path()
        ..moveTo(310, -10)
        ..lineTo(305, 310),
      width: 8,
      arterial: false,
    );
  }

  void _drawRoad(
    Canvas canvas,
    Path path, {
    required double width,
    required bool arterial,
  }) {
    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = _roadFill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width + 2.4
      ..color = _roadBorder;
    canvas.drawPath(path, borderPaint);
    canvas.drawPath(path, fillPaint);
    if (arterial) {
      final centerline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _roadCenterline;
      canvas.drawPath(path, centerline);
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackgroundPainter oldDelegate) => false;
}
