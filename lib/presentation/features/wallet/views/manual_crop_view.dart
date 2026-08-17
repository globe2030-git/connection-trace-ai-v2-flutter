import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/card_quad_geometry.dart';

/// [ManualCropView]가 돌려주는 값.
///
/// ⚠️ **사진 크기를 함께 돌려준다.** 부르는 쪽이 워프에 넘길 "화면 크기"를
/// 사진 비율과 같게 맞춰야 정규 좌표가 그대로 통한다. 크기를 알아내려고
/// 사진을 한 번 더 디코드하지 않으려는 것이다.
class ManualCropResult {
  const ManualCropResult({required this.corners, required this.imageSize});

  /// 네 귀퉁이 — 이미지 정규 좌표(0~1), 시계 방향.
  final List<Offset> corners;
  final Size imageSize;
}

/// 손으로 자르기(F-03, 추가 290).
///
/// ## 왜 필요한가
///
/// 자동 테두리 검출(B′)을 기본으로 쓰지 않기로 하면서(추가 277), 자동이
/// 잘못 잘랐을 때 **사람이 고칠 길이 없어졌다.** 지금까지는 다시 찍는 것이
/// 유일한 수단이었다. 이 화면이 그 자리를 메운다.
///
/// ## 무엇을 하나
///
/// 사진을 통째로 보여 주고 **네 귀퉁이를 끌어** 명함 자리를 정하게 한다.
/// 정해진 네 점은 자동 자르기가 쓰는 것과 **같은 워프 코드**로 넘어간다 —
/// 새 자르기 코드를 만들지 않는다.
///
/// ⚠️ **회전과 섞지 않는다.** 부르는 쪽이 회전을 먼저 구워서 **똑바로 선
/// 사진**을 넘긴다. 화면에서 돌린 각도와 자르는 좌표를 함께 다루면 좌표계가
/// 둘이 되고, 그건 이 저장소가 실기기에서 두 번 헤맨 자리다(추가 273).
class ManualCropView extends StatefulWidget {
  const ManualCropView({super.key, required this.imagePath});

  /// **똑바로 선** 사진 경로.
  final String imagePath;

  @override
  State<ManualCropView> createState() => _ManualCropViewState();
}

class _ManualCropViewState extends State<ManualCropView> {
  /// 네 귀퉁이 — **이미지 정규 좌표(0~1)**, 시계 방향(좌상·우상·우하·좌하).
  ///
  /// 처음에는 사진 안쪽으로 조금 들여 놓는다. 가장자리에 딱 붙여 두면
  /// 손잡이를 잡기 어렵고, 명함이 사진 전체를 채우는 경우는 드물다.
  List<Offset> _corners = const [
    Offset(0.08, 0.08),
    Offset(0.92, 0.08),
    Offset(0.92, 0.92),
    Offset(0.08, 0.92),
  ];

  /// 지금 끌고 있는 귀퉁이 번호. 없으면 null.
  int? _dragging;

  Size? _imageSize;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadImageSize());
  }

  /// 사진의 실제 크기를 알아야 레터박스 자리를 계산할 수 있다.
  Future<void> _loadImageSize() async {
    try {
      final stream = FileImage(
        File(widget.imagePath),
      ).resolve(ImageConfiguration.empty);
      final completer = Completer<Size>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(
              Size(info.image.width.toDouble(), info.image.height.toDouble()),
            );
          }
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final size = await completer.future;
      if (!mounted) return;
      setState(() => _imageSize = size);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  /// 손가락에서 가장 가까운 귀퉁이를 고른다.
  ///
  /// ⚠️ 아무리 멀어도 잡히면 사진을 톡 눌렀을 뿐인데 귀퉁이가 날아온다.
  /// 손가락 굵기 정도(48논리픽셀) 안에 있을 때만 잡는다.
  int? _nearestCorner(Offset point, Size box) {
    final image = _imageSize;
    if (image == null) return null;
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _corners.length; i++) {
      final handle = imageNormalizedToContainPoint(_corners[i], image, box);
      final d = (handle - point).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return bestDistance <= 48 ? best : null;
  }

  void _moveCorner(Offset point, Size box) {
    final image = _imageSize;
    final index = _dragging;
    if (image == null || index == null) return;
    setState(() {
      final next = [..._corners];
      next[index] = containPointToImageNormalized(point, image, box);
      _corners = next;
    });
  }

  /// 네 점이 **자를 만한 모양**인가.
  ///
  /// ⚠️ 귀퉁이를 한곳에 모아 놓고 자르면 1px짜리 그림이 나온다. 막지 않으면
  /// 사용자는 "자르기를 눌렀는데 아무것도 안 보인다"를 겪는다.
  bool get _isUsable {
    final xs = _corners.map((c) => c.dx);
    final ys = _corners.map((c) => c.dy);
    final w =
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
    final h =
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
    return w >= 0.15 && h >= 0.15;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                '네 귀퉁이를 명함 모서리에 맞춰 주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: _loadError != null
                  ? const Center(
                      child: Text(
                        '사진을 열지 못했습니다.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : _imageSize == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final box = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (d) => setState(
                            () => _dragging = _nearestCorner(
                              d.localPosition,
                              box,
                            ),
                          ),
                          onPanUpdate: (d) => _moveCorner(d.localPosition, box),
                          onPanEnd: (_) => setState(() => _dragging = null),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                              ),
                              CustomPaint(
                                painter: _CropPainter(
                                  corners: _corners,
                                  imageSize: _imageSize!,
                                  active: _dragging,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isUsable
                          ? () => Navigator.of(context).pop(
                              ManualCropResult(
                                corners: _corners,
                                imageSize: _imageSize!,
                              ),
                            )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('이대로 자르기'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 자를 자리와 손잡이를 그린다.
class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.corners,
    required this.imageSize,
    required this.active,
  });

  final List<Offset> corners;
  final Size imageSize;
  final int? active;

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners
        .map((c) => imageNormalizedToContainPoint(c, imageSize, size))
        .toList();

    final path = Path()..addPolygon(points, true);

    // 바깥을 어둡게 덮어 자를 자리를 눈에 띄게 한다.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        path,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );

    for (var i = 0; i < points.length; i++) {
      final isActive = i == active;
      canvas.drawCircle(
        points[i],
        isActive ? 16 : 12,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        points[i],
        isActive ? 10 : 7,
        Paint()..color = AppColors.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.corners != corners || old.active != active;
}
