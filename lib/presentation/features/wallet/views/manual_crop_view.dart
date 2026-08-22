import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/card_quad_geometry.dart';
import '../../../../core/utils/crop_mode_corners.dart';
import '../../../../core/utils/gallery_auto_detect.dart';
import '../../../../core/utils/gallery_crop_banner.dart';
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

/// [ManualCropView]가 [ManualCropResult] 대신 돌려줄 수 있는 값(398) —
/// **[자르기 없이 사용]**을 눌렀다는 신호.
///
/// ⚠️ **뒤로 가기(취소)와 다르다.** 취소는 `null`을 그대로 돌려준다(예전과
/// 같은 계약 — `camera_scan_modal_view.dart`의 `_cropPendingShotByHand`가
/// 이미 그렇게 본다). 이 값은 "잘라내지 않고 **원본 그대로** 쓰겠다"는
/// 명시적 선택이라 부르는 쪽이 둘을 구분해야 한다 — 취소는 처리를 멈추고,
/// 이것은 원본으로 계속 진행한다.
class ManualCropSkipped {
  const ManualCropSkipped();
}

/// [ManualCropView]가 닫히며 넘긴 값을 보고 **다음에 할 일**을 정한다(398).
///
/// Navigator·위젯 없이 순수하게 검사하려고 뺐다 — 부르는 쪽 화면
/// (`file_picker_modal_view.dart`) 안에서만 이 갈래를 타면, `is` 검사
/// 순서 하나가 잘못 뒤집혀도 위젯 테스트 없이는 못 잡는다.
enum GalleryCropOutcome {
  /// 잘라낸 새 파일을 쓴다 — [popResult]가 유효한 [ManualCropResult].
  cropped,

  /// [자르기 없이 사용] — 원본 그대로 쓴다.
  useOriginal,

  /// 뒤로 가기 등으로 취소 — 부르는 쪽은 전체 처리를 중단한다.
  cancelled,
}

/// [ManualCropView]를 `Navigator.push<Object?>`로 연 뒤 받은 값을
/// [GalleryCropOutcome]으로 분류한다.
GalleryCropOutcome galleryCropOutcomeFor(Object? popResult) {
  if (popResult is ManualCropResult && popResult.corners.length == 4) {
    return GalleryCropOutcome.cropped;
  }
  if (popResult is ManualCropSkipped) return GalleryCropOutcome.useOriginal;
  return GalleryCropOutcome.cancelled;
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
  const ManualCropView({
    super.key,
    required this.imagePath,
    this.allowSkip = false,
    this.stepLabel,
    this.initialMode = CropAdjustMode.auto,
    this.autoDetectEnabled = false,
  });

  /// **똑바로 선** 사진 경로(부르는 쪽이 이미 회전을 구워서 넘긴다).
  final String imagePath;

  /// **[자르기 없이 사용]** 탈출구를 보여줄지(398, 갤러리 경로).
  ///
  /// ⚠️ 기본값 false — 촬영 경로(`camera_scan_modal_view.dart`)는 이 화면에
  /// 들어오는 것 자체가 이미 선택 사항이다(F-03 "손으로 자르기" 버튼을 눌러야만
  /// 온다). 탈출구가 따로 필요 없다. 갤러리 경로(398)는 이 화면이 사진을 고르면
  /// **자동으로** 열리므로, 원본 그대로 쓰고 싶은 사용자를 막지 않기 위해 켠다
  /// (공존 원칙).
  final bool allowSkip;

  /// 2장 선택(P2-②)에서 "앞면 자르기 1/2"처럼 단계를 보여줄 라벨. null이면
  /// 아무것도 표시하지 않는다 — 촬영 경로·갤러리 1장 선택은 항상 null이다.
  final String? stepLabel;

  /// 처음 열릴 때 어느 세그먼트로 시작할지.
  ///
  /// ⚠️ 갤러리 경로(398·399)는 [CropAdjustMode.manual]로 연다. [autoDetectEnabled]가
  /// 켜져 있어도 검출은 이 화면이 뜬 **뒤에 비동기로** 도니, 화면이 열리는
  /// 순간에는 아직 결과가 없다 — 그래서 안전한 수동 시작 자리에서 출발하고,
  /// 검출이 성공하면(그리고 사용자가 아직 아무것도 만지지 않았으면)
  /// [CropAdjustMode.auto]로 스스로 전환한다(`_runAutoDetect` 참고). 촬영
  /// 경로는 기존대로 [CropAdjustMode.auto]를 그대로 쓴다 — 그 경로는 이
  /// 화면에 오기 전에 가이드·검출 크롭을 실제로 거친 사진이다.
  final CropAdjustMode initialMode;

  /// 이 화면 안에서 **정지 이미지 검출을 직접 돌릴지**(결함 399).
  ///
  /// ⚠️ 기본값 false — 촬영 경로는 이 화면에 오기 전에 이미 실시간 검출을
  /// 거친 사진을 받으므로(`camera_scan_modal_view.dart`), 여기서 또 돌리면
  /// 중복이다. **갤러리 경로만 켠다**: 그 경로의 원본은 한 번도 검출을 거친
  /// 적이 없는 사진이라, [CropAdjustMode.auto] 세그먼트와 "찾았어요" 배너가
  /// 뜻하는 바를 실제로 만들어 내야 한다.
  ///
  /// 켜면 [initState]에서 [detectGalleryCardCorners]를 `compute()`로 돌린다
  /// (`gallery_auto_detect.dart`). 결과에 따라 배너·세그먼트·시작 귀퉁이가
  /// 갈린다 — [_buildBanner]·[_startCornersFor] 참고.
  final bool autoDetectEnabled;

  @override
  State<ManualCropView> createState() => _ManualCropViewState();
}

class _ManualCropViewState extends State<ManualCropView> {
  /// 지금 편집 중인 사진 경로. [회전]을 누르면 새 파일로 바뀐다.
  late String _imagePath;

  /// [widget.imagePath]와 다르면(=이 화면 안에서 회전을 구웠으면) 화면을
  /// 나갈 때 지워야 하는 임시 파일이다.
  String? _bakedPathToCleanUp;

  /// [widget.initialMode]로 initState에서 채운다 — 필드 초기화 목록에서는
  /// `widget`을 아직 못 읽는다.
  late CropAdjustMode _mode;

  /// 네 귀퉁이 — **이미지 정규 좌표(0~1)**, 시계 방향(좌상·우상·우하·좌하).
  ///
  /// 모드별 시작 위치는 [_startCornersFor]가 정한다 — 세그먼트 전환·
  /// [다시 찾기]·[회전]이 전부 이 함수 하나로 리셋해야 셋 중 하나만 따로
  /// 어긋나지 않는다.
  late List<Offset> _corners;

  /// 지금 끌고 있는 귀퉁이 번호. 없으면 null.
  int? _dragging;

  Size? _imageSize;
  Object? _loadError;
  bool _isRotating = false;

  // ── 정지 이미지 자동 검출(결함 399, [widget.autoDetectEnabled]일 때만) ──

  /// [detectGalleryCardCorners]가 실제로 찾아낸 귀퉁이. 성공하기 전에는
  /// null — 이때 [CropAdjustMode.auto]를 골라도 "찾은 것"을 보여줄 수
  /// 없다([_startCornersFor] 참고).
  List<Offset>? _detectedCorners;

  /// 검출이 지금 도는 중인가 — 배너에 진행 표시를 띄우는 데만 쓴다.
  ///
  /// ⚠️ "실패했나"는 별도 필드로 안 둔다. [_detectedCorners]가 null이고
  /// 이것도 false면 그 자체가 "끝났는데 못 찾았다"는 뜻이다 — 상태 두 개를
  /// 따로 들면 언젠가 서로 어긋난다.
  bool _autoDetecting = false;

  /// 사용자가 세그먼트를 직접 바꾸거나 귀퉁이를 끌었는가.
  ///
  /// ⚠️ 검출이 끝나기 전에 사용자가 먼저 손을 대면, 검출이 뒤늦게 성공해도
  /// **그 결과로 사용자가 이미 하던 조정을 덮어쓰지 않는다.** 검출은
  /// 대개 눈 깜짝할 새 끝나지만(386 측정: 다운샘플 후 프레임당 ~5ms 수준),
  /// 큰 사진 디코드까지 합치면 0이 아니다 — 그 틈을 사용자가 이길 수 있다.
  bool _userInteracted = false;

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
    _mode = widget.initialMode;
    _corners = _startCornersFor(_mode);
    unawaited(_loadImageSize());
    if (widget.autoDetectEnabled) {
      unawaited(_runAutoDetect());
    }
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
    // 검출이 늦게 끝나도 사용자가 방금 고른 세그먼트를 덮어쓰지 않는다.
    _userInteracted = true;
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _corners = _startCornersFor(mode);
    });
  }

  /// [자르기 없이 사용](398) — 잘라내지 않고 원본 그대로 쓰겠다는 신호를
  /// 돌려준다. [widget.allowSkip]일 때만 화면에 버튼이 보인다.
  void _skip() {
    Navigator.of(context).pop(const ManualCropSkipped());
  }

  /// [다시 찾기] — 지금 모드의 시작 자리로 귀퉁이를 되돌린다.
  ///
  /// ⚠️ **다시 검출을 돌리지는 않는다** — [_detectedCorners]가 이미 있으면
  /// (결함 399, [widget.autoDetectEnabled]) 그 값으로 되돌릴 뿐이다. 매번
  /// 다시 디코드·검출하면 버튼을 누를 때마다 짧게 멈추는데, "다시 찾기"는
  /// 귀퉁이를 만지다 잘못 짚었을 때 되돌리는 용도라 새로 찾을 이유가 없다.
  void _resetCorners() {
    setState(() => _corners = _startCornersFor(_mode));
  }

  /// [회전] — 90도씩 시계 방향. 사진을 실제로 다시 굽고, 귀퉁이는
  /// 초기화한다(좌표계를 섞지 않기 위해 — 클래스 문서 참고).
  ///
  /// ⚠️ **[widget.autoDetectEnabled]면 검출도 다시 돈다**(결함 399). 회전 전에
  /// 찾아 둔 [_detectedCorners]는 회전 전 사진 기준이라 그대로 두면 좌표가
  /// 90도 어긋난 채 "찾았다"고 계속 말하게 된다 — 그건 회전과 자르기 좌표를
  /// 섞어 실기기에서 두 번 헤맨 것(추가 273)과 같은 종류의 결함이라, 값을
  /// 버리고 새로 판 사진으로 다시 찾는다.
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
        if (widget.autoDetectEnabled) {
          // 회전 전 검출 결과는 지금 사진에 안 맞는다 — 통째로 버리고
          // 수동 시작 자리로 되돌린 뒤 새로 찾는다.
          _detectedCorners = null;
          _userInteracted = false;
          _mode = CropAdjustMode.manual;
        }
        _corners = _startCornersFor(_mode);
      });
      // 직전에 이 화면 안에서 구운 회전본이 있었다면(=원본이 아니었다면)
      // 더는 쓰이지 않으니 지운다 — 안 지우면 회전을 누를 때마다 평문
      // 사본이 쌓인다.
      if (previous != null && !previousIsOriginal) {
        await deleteQuietly(previous);
      }
      await _loadImageSize();
      if (widget.autoDetectEnabled) {
        unawaited(_runAutoDetect());
      }
    } finally {
      if (mounted) setState(() => _isRotating = false);
    }
  }

  /// [_corners]가 처음 놓일 자리. 세그먼트 전환·[다시 찾기]·[회전]이 전부
  /// 이 함수 하나로 정해야 셋 중 하나만 따로 어긋나지 않는다.
  ///
  /// 실제 판정은 [cropStartCornersForDetection](순수 함수,
  /// `crop_mode_corners.dart`)이 한다 — 화면 없이 검사할 수 있는 부분은
  /// 그쪽에 둔다.
  List<Offset> _startCornersFor(CropAdjustMode mode) =>
      cropStartCornersForDetection(
        mode: mode,
        autoDetectEnabled: widget.autoDetectEnabled,
        detectedCorners: _detectedCorners,
      );

  /// 갤러리 사진에 실제 테두리 검출을 돌린다(결함 399).
  ///
  /// `compute()`로 별도 isolate에서 돈다 — 디코드·리사이즈·OpenCV 검출이
  /// 화면 진입을 막으면 안 되는 무거운 일이다(브리프 요구사항 3).
  Future<void> _runAutoDetect() async {
    setState(() => _autoDetecting = true);
    GalleryAutoDetectResult result;
    try {
      result = await compute(
        detectGalleryCardCorners,
        GalleryAutoDetectRequest(_imagePath),
      );
    } catch (_) {
      result = const GalleryAutoDetectResult(success: false);
    }
    if (!mounted) return;
    setState(() {
      _autoDetecting = false;
      final flat = result.cornersFlat;
      if (result.success && flat != null && flat.length == 8) {
        final corners = <Offset>[
          for (var i = 0; i < 8; i += 2) Offset(flat[i], flat[i + 1]),
        ];
        _detectedCorners = corners;
        // 사용자가 이미 손을 댔으면 지금 보고 있는 것을 조용히 덮지 않는다
        // — 다시 [자동 인식] 탭으로 가면 그때 이 값을 쓴다.
        if (!_userInteracted) {
          _mode = CropAdjustMode.auto;
          _corners = corners;
        }
      } else if (!_userInteracted && _mode == CropAdjustMode.auto) {
        // 못 찾았다 — "찾았다"는 상자(2~98%)를 계속 보여주지 않는다.
        _corners = _startCornersFor(_mode);
      }
    });
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
            if (widget.stepLabel != null || widget.allowSkip)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.stepLabel != null)
                      Text(
                        widget.stepLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    // 398: 갤러리 경로에서만 켠다 — 클래스 문서(allowSkip) 참고.
                    if (widget.allowSkip)
                      TextButton(
                        onPressed: _isRotating ? null : _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(44, 44),
                        ),
                        child: const Text(
                          '자르기 없이 사용',
                          style: TextStyle(
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
                          onPanStart: (d) => setState(() {
                            final index = _nearestCorner(d.localPosition, box);
                            _dragging = index;
                            // 귀퉁이를 실제로 잡았을 때만 "손을 댔다"로 본다
                            // — 사진을 그냥 톡 눌러서는(귀퉁이가 안 잡히면)
                            // 늦게 끝난 검출 결과를 덮어쓸 이유가 없다.
                            if (index != null) _userInteracted = true;
                          }),
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

  /// 배너에 띄울 아이콘·문구를 정한다.
  ///
  /// 실제 판정은 [galleryCropBannerKind](순수 함수, `gallery_crop_banner.dart`)가
  /// 한다 — "찾지 못했는데 찾았다고 말하는" 경로가 있는지를 화면 없이
  /// 검사하기 위해서다(그 함수 문서 참고).
  ({IconData icon, String text}) _bannerContent() {
    final kind = galleryCropBannerKind(
      autoDetectEnabled: widget.autoDetectEnabled,
      detecting: _autoDetecting,
      hasDetectedCorners: _detectedCorners != null,
      mode: _mode,
    );
    final icon = switch (kind) {
      GalleryCropBannerKind.detecting => Icons.hourglass_top,
      GalleryCropBannerKind.notFound => Icons.crop,
      GalleryCropBannerKind.autoFound => Icons.auto_fix_high,
      GalleryCropBannerKind.manualHint => Icons.crop,
    };
    return (icon: icon, text: galleryCropBannerText(kind));
  }

  Widget _buildBanner() {
    final content = _bannerContent();
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
            if (_autoDetecting)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              Icon(content.icon, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                content.text,
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
