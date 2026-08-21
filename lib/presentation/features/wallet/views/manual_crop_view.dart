import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/card_quad_geometry.dart';
import '../../../../core/utils/crop_mode_corners.dart';
import '../../../../core/utils/image_rotation_bake.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';

/// [ManualCropView]가 돌려주는 값.
///
/// ⚠️ **사진 크기를 함께 돌려준다.** 부르는 쪽이 워프에 넘길 "화면 크기"를
/// 사진 비율과 같게 맞춰야 정규 좌표가 그대로 통한다. 크기를 알아내려고
/// 사진을 한 번 더 디코드하지 않으려는 것이다.
///
/// ⚠️ **[imagePath]도 함께 돌려준다 — 부르는 쪽이 넘긴 경로가 아니라
/// "귀퉁이가 실제로 찍힌" 경로다.** P2-③에서 이 화면 안에 [회전]이
/// 생기면서, 화면을 여는 시점의 경로와 자르기를 확정하는 시점의 경로가
/// 달라질 수 있게 됐다(회전을 누르면 새 파일을 굽는다). [corners]는
/// 항상 **이 [imagePath]를 기준으로 한 정규 좌표**다 — 부르는 쪽이 자기가
/// 넘겼던 원래 경로를 그대로 워프에 쓰면, 회전 전 사진에 회전 후 좌표를
/// 대는 꼴이 되어 **좌표계가 섞인다**(추가 273이 실기기에서 겪은 것과 같은
/// 종류의 결함). 반드시 이 필드를 워프의 `sourcePath`로 써야 한다.
class ManualCropResult {
  const ManualCropResult({
    required this.imagePath,
    required this.corners,
    required this.imageSize,
  });

  /// 네 귀퉁이가 찍힌 **바로 그** 사진 경로.
  final String imagePath;

  /// 네 귀퉁이 — 이미지 정규 좌표(0~1), 시계 방향.
  final List<Offset> corners;
  final Size imageSize;
}

/// 크롭 UX 공존안(P2-③, 2026-08-22 확정) + F-03(추가 290) 손으로 자르기.
///
/// ## 무엇이 바뀌었나
///
/// 예전에는 "자동 크롭 결과를 확인" 화면과 "손으로 자르기" 화면이 완전히
/// 분리돼 있었다 — 자동이 잘못 잘랐을 때만 별도 버튼으로 이 화면에 들어올
/// 수 있었다. 지금은 **상단 세그먼트([자동 인식]/[직접 조정])로 같은
/// 화면 안에서 오간다.** 두 모드 모두 모서리 핸들이 **상시 노출**된다 —
/// "자동 인식"은 이미 자른 사진을 살짝 다듬는 자리, "직접 조정"은 더 넓은
/// 시작 상자에서 새로 잡는 자리라는 차이만 있다.
///
/// ⚠️ **크롭 엔진은 손대지 않았다.** 네 점을 골라 [warpCardToFile]로 넘기는
/// 것은 예전 그대로다(F-03 회귀 0). 이 화면이 새로 하는 일은 **배치와
/// 안내뿐**이다 — 세그먼트에 따라 시작 귀퉁이 위치와 안내 문구만 바뀐다.
///
/// ⚠️ **회전과 자르기 좌표를 섞지 않는다**(추가 273, 실기기에서 두 번 헤맨
/// 자리). [회전]을 누르면 [bakeImageRotation]으로 **새 파일**을 굽고, 그
/// 새 파일에 맞춰 귀퉁이를 **다시 초기화**한다 — 이전 좌표를 새로 돌아간
/// 사진 위에 그대로 쓰지 않는다.
class ManualCropView extends StatefulWidget {
  const ManualCropView({super.key, required this.imagePath});

  /// **똑바로 선** 사진 경로(부르는 쪽이 이미 회전을 구워서 넘긴다).
  final String imagePath;

  @override
  State<ManualCropView> createState() => _ManualCropViewState();
}

class _ManualCropViewState extends State<ManualCropView> {
  /// 지금 편집 중인 사진 경로. [회전]을 누르면 새 파일로 바뀐다.
  late String _imagePath;

  /// [widget.imagePath]와 다르면(=이 화면 안에서 회전을 구웠으면) 화면을
  /// 나갈 때 지워야 하는 임시 파일이다.
  String? _bakedPathToCleanUp;

  CropAdjustMode _mode = CropAdjustMode.auto;

  /// 네 귀퉁이 — **이미지 정규 좌표(0~1)**, 시계 방향(좌상·우상·우하·좌하).
  ///
  /// 모드별 시작 위치는 [cropStartCornersFor](순수 함수,
  /// `crop_mode_corners.dart`)가 정한다 — 세그먼트 전환·[다시 찾기]·
  /// [회전]이 전부 이 함수 하나로 리셋해야 셋 중 하나만 따로 어긋나지
  /// 않는다.
  List<Offset> _corners = cropStartCornersFor(CropAdjustMode.auto);

  /// 지금 끌고 있는 귀퉁이 번호. 없으면 null.
  int? _dragging;

  Size? _imageSize;
  Object? _loadError;
  bool _isRotating = false;

  /// **[_imagePath]의 책임을 부른 쪽에 넘겼는지**(file_picker_modal_view.dart의
  /// `_handedOverToCaller`와 같은 패턴).
  ///
  /// ⚠️ 이게 없으면 [dispose]가 방금 [Navigator.pop]으로 돌려준 파일을
  /// **부르는 쪽이 다 쓰기도 전에** 지워 버릴 수 있다 — `pop()`이 끝나도
  /// 이 State의 `dispose()`는 전환 애니메이션이 끝난 뒤에야 불릴 수도
  /// 있고, 반대로 그 타이밍에 기대는 것 자체가 실기기에서만 드러나는 경합
  /// 조건이다.
  bool _handedOverImagePath = false;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.imagePath;
    unawaited(_loadImageSize());
  }

  @override
  void dispose() {
    // 이 화면 안에서 회전을 굴며 만든 임시본만 지운다 — 원본은 부르는
    // 쪽(카메라 확인 화면)의 책임이다.
    //
    // ⚠️ **넘겨준 파일은 지우지 않는다.** [_handedOverImagePath]가 true면
    // 지금 [_bakedPathToCleanUp]이 곧 부르는 쪽에 돌려준 [ManualCropResult
    // .imagePath]다 — 워프가 그 파일을 아직 읽고 있을 수 있다.
    final orphan = _bakedPathToCleanUp;
    if (orphan != null && !_handedOverImagePath) {
      unawaited(deleteQuietly(orphan));
    }
    super.dispose();
  }

  /// 사진의 실제 크기를 알아야 레터박스 자리를 계산할 수 있다.
  Future<void> _loadImageSize() async {
    try {
      final stream = FileImage(
        File(_imagePath),
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

  /// 세그먼트를 바꾸면 그 모드의 시작 귀퉁이로 되돌린다 — 두 모드가 같은
  /// 좌표를 공유하면 "자동에서 다듬은 것"과 "직접 새로 잡은 것"이 섞인다.
  void _selectMode(CropAdjustMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _corners = cropStartCornersFor(mode);
    });
  }

  /// [다시 찾기] — 지금 모드의 시작 자리로 귀퉁이를 되돌린다.
  ///
  /// ⚠️ 살아 있는 카메라 스트림이 없는 화면이라 "재검출"은 할 수 없다 —
  /// 이 화면이 받는 사진은 이미 촬영이 끝난 정지 이미지다. 그래서 "다시
  /// 찾기"는 **자동/수동 각 모드가 처음 제안하던 자리로 리셋**하는
  /// 동작이다(귀퉁이를 만지다 잘못 짚었을 때 되돌리는 용도).
  void _resetCorners() {
    setState(() => _corners = cropStartCornersFor(_mode));
  }

  /// [회전] — 90도씩 시계 방향. 사진을 실제로 다시 굽고, 귀퉁이는
  /// 초기화한다(좌표계를 섞지 않기 위해 — 클래스 문서 참고).
  Future<void> _rotate() async {
    if (_isRotating) return;
    setState(() => _isRotating = true);
    try {
      final baked = await bakeImageRotation(XFile(_imagePath), 90);
      if (!mounted) return;
      final previous = _bakedPathToCleanUp;
      final previousIsOriginal = _imagePath == widget.imagePath;
      setState(() {
        _imagePath = baked.path;
        _bakedPathToCleanUp = baked.path == widget.imagePath ? null : baked.path;
        _imageSize = null;
        _corners = cropStartCornersFor(_mode);
      });
      // 직전에 이 화면 안에서 구운 회전본이 있었다면(=원본이 아니었다면)
      // 더는 쓰이지 않으니 지운다 — 안 지우면 회전을 누를 때마다 평문
      // 사본이 쌓인다.
      if (previous != null && !previousIsOriginal) {
        await deleteQuietly(previous);
      }
      await _loadImageSize();
    } finally {
      if (mounted) setState(() => _isRotating = false);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: _buildModeSegment(),
            ),
            _buildBanner(),
            Expanded(
              child: _loadError != null
                  ? const Center(
                      child: Text(
                        '사진을 열지 못했습니다.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : (_imageSize == null || _isRotating)
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
                                File(_imagePath),
                                fit: BoxFit.contain,
                              ),
                              // 모서리 핸들 — 상시 노출(자동/직접 조정 공통).
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
                  // F-03: 자동이 잘못 잘랐을 때 실제로 돌려 볼 수 있어야
                  // 한다. 좌표는 섞지 않는다 — [_rotate] 문서 참고.
                  OutlinedButton(
                    onPressed: _isRotating ? null : _rotate,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    child: const Icon(Icons.rotate_right, size: 20),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _isRotating ? null : _resetCorners,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    child: const Icon(Icons.replay, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isUsable && !_isRotating)
                          ? () {
                              // ⚠️ **여기서 넘긴다** — 지금 이 순간의
                              // [_imagePath]가 [_corners]의 기준이다. 넘긴
                              // 뒤에는 dispose()가 이 파일을 지우면 안
                              // 된다(클래스 문서 참고).
                              _handedOverImagePath = true;
                              Navigator.of(context).pop(
                                ManualCropResult(
                                  imagePath: _imagePath,
                                  corners: _corners,
                                  imageSize: _imageSize!,
                                ),
                              );
                            }
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

  /// 상단 [자동 인식]/[직접 조정] 세그먼트(P2-③). 기본은 자동.
  Widget _buildModeSegment() {
    return Row(
      children: [
        Expanded(
          child: _modeSegmentButton(
            label: '자동 인식',
            selected: _mode == CropAdjustMode.auto,
            onTap: () => _selectMode(CropAdjustMode.auto),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _modeSegmentButton(
            label: '직접 조정',
            selected: _mode == CropAdjustMode.manual,
            onTap: () => _selectMode(CropAdjustMode.manual),
          ),
        ),
      ],
    );
  }

  Widget _modeSegmentButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    final isAuto = _mode == CropAdjustMode.auto;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isAuto ? Icons.auto_fix_high : Icons.crop,
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isAuto
                    ? '테두리를 자동으로 찾았어요 — 모서리 점을 끌어 바로 고칠 수 있어요'
                    : '네 귀퉁이를 명함 모서리에 맞춰 주세요',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  height: 1.35,
                ),
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
