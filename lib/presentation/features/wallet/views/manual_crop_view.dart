import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/card_quad_geometry.dart';
import '../../../../core/utils/crop_mode_corners.dart';
import '../../../../core/utils/crop_rotation_bake_state.dart';
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
/// 자리). [회전]/[반시계 회전]을 누르면 [bakeImageRotation]으로 **새 파일**을
/// 굽는다 — 이전 좌표를 새로 돌아간 사진 위에 **그대로**(재계산 없이) 쓰지는
/// 않는다. **[_rotateBy] 문서에 적었듯 굽기는 백그라운드에서 돌고 화면은
/// 즉시 돌아간다**(P2-③ 2차) — 귀퉁이는 클릭 즉시 [rotateCornersCw90]/
/// [rotateCornersCcw90]으로 정확히 변환하고, 실제 파일이 그 방향을
/// 따라잡으면 경로만 조용히 바꿔 낀다. "섞지 않는다"는 원칙 자체는
/// 그대로고, 지키는 방법만 바뀌었다.
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

  // ── 회전 즉시 미리보기 + 배경 굽기(P2-③ 2차, "굽기 ~2초" 실기기 후속) ──

  /// 누적 회전·배경 굽기 진행 상태 — 실제 전이 규칙은 순수 클래스
  /// [CropRotationBakeState]가 갖고 있다(테스트는 그쪽 파일).
  CropRotationBakeState _bakeState = const CropRotationBakeState();

  /// 지금 도는 배경 굽기의 Future. [_ensureFullyBaked]가 직접 기다리는
  /// 데만 쓴다 — 분기 판단은 [_bakeState]가 한다.
  Future<void>? _activeBakeFuture;

  /// [자르기 확정]을 누른 뒤 밀린 굽기를 기다리는 중인가 — 이때만 화면에
  /// 로딩을 보여준다("완료 시점에 굽기가 안 끝났으면 그때만 로딩").
  bool _isFinalizing = false;

  /// [widget.imagePath] 기준으로 지금까지 순누적된 시계 방향 회전 —
  /// **굽기가 끝나도 리셋되지 않는다**([_bakeState.pendingTurns]와 다른
  /// 점). [_runAutoDetect]가 [widget.imagePath] 원본을 기준으로 찾은
  /// 결과를 "지금 화면 방향"으로 보정하는 데만 쓴다([_runAutoDetect] 문서
  /// 참고) — 검출 도중 회전이 이미 구워져 [_bakeState.pendingTurns]가
  /// 0으로 돌아온 뒤에도 보정이 필요할 수 있어서 따로 둔다.
  int _totalTurnsCwSinceOpen = 0;

  /// [rotateCornersCw90]/[rotateCornersCcw90] 호출에서 크기가 계산에 안 쓰이는
  /// 자리(실패 되돌리기·검출 보정)에 넘기는 더미 값 — 두 함수 모두 계산에는
  /// 크기를 쓰지 않고 양수인지만 assert로 확인한다(각 함수 문서 참고).
  static const _dummyRotationSize = Size(1, 1);

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

  /// 지금 화면에 **보이는** 방향 기준 이미지 크기.
  ///
  /// ⚠️ 실제 파일([_imageSize])은 배경 굽기가 끝나야 바뀐다 — 그 전까지는
  /// [RotatedBox]로 화면만 돌려 보여주므로, 오버레이·제스처가 참고할
  /// "지금 보이는" 크기가 따로 필요하다. 밀린 회전이 홀수 번이면 가로·
  /// 세로가 바뀐다.
  Size? get _visualImageSize {
    final size = _imageSize;
    if (size == null) return null;
    return _bakeState.pendingTurns.isOdd ? Size(size.height, size.width) : size;
  }

  /// [corners]에 90도 [times]번을 적용한다 — 실패 되돌리기·검출 보정처럼
  /// "지금 화면에 보이는 크기"가 없거나 의미가 없는 자리에서만 쓴다(더미
  /// 크기로 충분한 이유는 [_dummyRotationSize] 문서 참고). 클릭 한 번에
  /// 대응하는 실시간 변환은 [_rotateBy]가 실제 시각 크기로 직접 한다.
  List<Offset> _rotateNTimes(
    List<Offset> corners, {
    required int times,
    required bool clockwise,
  }) {
    var result = corners;
    for (var i = 0; i < times; i++) {
      result = clockwise
          ? rotateCornersCw90(result, _dummyRotationSize)
          : rotateCornersCcw90(result, _dummyRotationSize);
    }
    return result;
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

  /// [회전]/[반시계 회전] — 화면부터 즉시 돌리고, 실제 파일 굽기는
  /// 백그라운드로 미룬다(P2-③ 2차, 실기기 피드백: "굽는 동안 2초 멈춘다").
  ///
  /// ## 왜 예전처럼 굽기를 기다리지 않나
  ///
  /// 1차 개선(추가 446)까지는 `bakeImageRotation` 자체는 `compute()`로
  /// isolate를 옮겨 메인 스레드를 막지 않게 했지만, `_rotate`가 여전히 그
  /// 결과를 **await한 뒤에야** 화면을 갱신했다 — 무거운 디코드+인코딩이
  /// 끝날 때까지 사용자가 기다리는 체감은 그대로였다. 이번에는 파일을
  /// 굽기 **전에** 먼저 화면과 귀퉁이 좌표를 돌려 보여준다
  /// ([RotatedBox](build 참고))ㅡ실제 굽기는 [_kickBakeIfNeeded]가 뒤에서
  /// 돌리고, 끝나면 화면 흔들림 없이 파일 경로만 조용히 바꿔 낀다([_runBake]
  /// 참고, [_bakeState]가 `pendingTurns→0`이 되면서 [RotatedBox]의
  /// `quarterTurns`도 함께 0으로 돌아가므로 시각 결과는 그대로다).
  ///
  /// ## 귀퉁이는 클릭마다 즉시 변환한다
  ///
  /// [rotateCornersCw90]/[rotateCornersCcw90](`crop_mode_corners.dart`,
  /// 순수 함수 + 왕복 테스트)로 **클릭하는 순간** [_corners]·
  /// [_detectedCorners]를 옮긴다 — 굽기가 끝나길 기다리지 않는다. 이 값들이
  /// 항상 "지금 화면에 보이는 방향" 기준이라서, 실제 굽기가 나중에 그
  /// 방향을 따라잡으면([_runBake]) 좌표를 다시 계산할 게 없다(파일만
  /// 바꿔 끼우면 그대로 맞는다).
  ///
  /// ## 연타
  ///
  /// 굽는 도중 또 누르면 [_bakeState.pendingTurns]만 더 누적된다 — 클릭마다
  /// 새 굽기를 쌓지 않는다. 도는 굽기가 끝났을 때 그 목표가 이미 낡았으면
  /// (더 눌렸으면) 결과를 버리고 **그 순간의 누적분을 한 번에** 다시 굽는다
  /// (`bakeImageRotation`에 `pendingTurns*90`을 통째로 넘긴다 — 90을 여러
  /// 번 나눠 굽지 않는다). [CropRotationBakeState] 문서·테스트 참고.
  void _rotateBy({required bool clockwise}) {
    final oldVisualSize = _visualImageSize;
    if (oldVisualSize == null) return; // 이미지 크기를 아직 모르면 손대지 않는다.
    setState(() {
      _bakeState = clockwise ? _bakeState.rotatedCw() : _bakeState.rotatedCcw();
      _totalTurnsCwSinceOpen = (_totalTurnsCwSinceOpen + (clockwise ? 1 : 3)) % 4;
      _corners = clockwise
          ? rotateCornersCw90(_corners, oldVisualSize)
          : rotateCornersCcw90(_corners, oldVisualSize);
      final detected = _detectedCorners;
      if (detected != null) {
        _detectedCorners = clockwise
            ? rotateCornersCw90(detected, oldVisualSize)
            : rotateCornersCcw90(detected, oldVisualSize);
      }
    });
    _kickBakeIfNeeded();
  }

  /// 지금 밀려 있는 회전을 배경에서 굽는다. 이미 굽는 중이면 아무것도
  /// 안 한다 — [_runBake]가 끝나면 스스로 다시 이 함수를 불러 낡지 않았는지
  /// 확인한다(연타 처리, [_rotateBy] 문서 참고).
  void _kickBakeIfNeeded() {
    if (_bakeState.isBaking) return;
    final started = _bakeState.startBakeIfNeeded();
    if (!started.isBaking) return; // 밀린 회전이 없다(상쇄됐거나 이미 정착).
    setState(() => _bakeState = started);
    _activeBakeFuture = _runBake(started.bakingTarget!);
  }

  /// [target]을 실제로 굽는다 — `_imagePath`가 아직 반영하지 않은 만큼
  /// (90도 단위)을 `bakeImageRotation`에 한 번에 넘긴다.
  Future<void> _runBake(int target) async {
    final sourcePath = _imagePath;
    final baked = await bakeImageRotation(XFile(sourcePath), target * 90);
    if (!mounted) {
      // 화면이 이미 닫혔다 — 아무도 못 쓰는 파일이니 지운다.
      if (baked.path != sourcePath) await deleteQuietly(baked.path);
      _activeBakeFuture = null;
      return;
    }
    final stillCurrent = _bakeState.pendingTurns == target;
    if (stillCurrent && baked.path != sourcePath) {
      // 성공 — 파일을 바꿔 끼운다. 귀퉁이는 클릭마다 이미 [_rotateBy]가
      // 변환해 뒀으니 다시 계산할 게 없다.
      final previous = _bakedPathToCleanUp;
      final previousIsOriginal = _imagePath == widget.imagePath;
      setState(() {
        _imagePath = baked.path;
        _bakedPathToCleanUp = baked.path == widget.imagePath ? null : baked.path;
        _bakeState = _bakeState.bakeCompleted();
      });
      await _loadImageSize();
      if (previous != null && !previousIsOriginal) {
        await deleteQuietly(previous);
      }
    } else if (stillCurrent) {
      // ⚠️ 굽기 실패 — `bakeImageRotation`은 실패하면 원본 경로를 그대로
      // 돌려준다(`image_rotation_bake.dart` 문서 참고). 화면과 실물이
      // 어긋나지 않도록(이 작업의 인수 기준 1번) **화면 회전도 함께
      // 되돌린다** — 재시도를 기다리며 [자르기 확정]이 영영 안 끝나는
      // 것보다, 방향은 못 바꿨어도 저장물이 화면과 일치하는 편이 낫다.
      setState(() {
        _corners = _rotateNTimes(_corners, times: target, clockwise: false);
        final detected = _detectedCorners;
        if (detected != null) {
          _detectedCorners = _rotateNTimes(detected, times: target, clockwise: false);
        }
        _bakeState = _bakeState.bakeCompleted();
      });
    } else {
      // 굽는 동안 더 눌려 목표가 낡았다 — 결과를 버린다. 아래에서 최신
      // 값으로 다시 건다.
      if (baked.path != sourcePath) await deleteQuietly(baked.path);
      setState(() => _bakeState = _bakeState.bakeCompleted());
    }
    _activeBakeFuture = null;
    if (mounted) _kickBakeIfNeeded();
  }

  /// [자르기 확정]을 누른 시점에 밀린 굽기가 있으면 끝날 때까지 기다린다.
  /// 저장물이 화면에 보이는 방향과 달라지는 일이 없게 하려는 것이다(이
  /// 작업의 인수 기준 1번).
  Future<void> _ensureFullyBaked() async {
    while (!_bakeState.isSettled) {
      _kickBakeIfNeeded();
      final active = _activeBakeFuture;
      if (active == null) break; // 이론상 오지 않는다 — 안전장치.
      await active;
    }
  }

  /// [이대로 자르기] — 밀린 굽기가 있으면 그때만 로딩을 보여주고 기다린 뒤
  /// 넘긴다.
  ///
  /// ⚠️ **[_imageSize]가 아직 null이면 손대지 않는다**(추가 407 ②). 버튼
  /// 행은 이미지 로딩 스피너와 무관하게 처음부터 그려지므로([build] 참고),
  /// 로드가 끝나기 전에 눌리면 아래 [ManualCropResult]의 `_imageSize!`가
  /// 크래시한다 — 버튼 비활성화([build]의 `onPressed`)가 1차 방어선이고,
  /// 이건 그 방어선이 뚫려도(예: 위젯 트리 재구성 경합) 조용히 잘못된
  /// 좌표로 저장되지 않게 하는 2차 방어선이다.
  Future<void> _confirm() async {
    if (_isFinalizing || !_isUsable || _imageSize == null) return;
    if (!_bakeState.isSettled) {
      setState(() => _isFinalizing = true);
      await _ensureFullyBaked();
      if (!mounted) return;
      setState(() => _isFinalizing = false);
    }
    if (!mounted) return;
    // ⚠️ **여기서 넘긴다** — 지금 이 순간의 [_imagePath]가 [_corners]의
    // 기준이다(위 대기 덕분에 항상 정착된 상태). 넘긴 뒤에는 dispose()가
    // 이 파일을 지우면 안 된다(클래스 문서 참고).
    _handedOverImagePath = true;
    Navigator.of(context).pop(
      ManualCropResult(
        imagePath: _imagePath,
        corners: _corners,
        imageSize: _imageSize!,
      ),
    );
  }

  /// [_corners]가 처음 놓일 자리. 세그먼트 전환·[다시 찾기]가 이 함수
  /// 하나로 정해야 서로 어긋나지 않는다.
  ///
  /// ⚠️ [회전]은 이 함수를 거치지 않는다 — [rotateCornersCw90]/
  /// [rotateCornersCcw90]으로 지금 좌표를 직접 변환한다([_rotateBy] 문서
  /// 참고). 이 함수가 돌려주는 시작 사각형은 세로·가로 대칭이라 회전에
  /// 영향을 안 받는다(kAutoModeStartCorners/kManualModeStartCorners는 중심
  /// 대칭 정사각형) — 그래서 세그먼트 전환·[다시 찾기]는 지금 회전 상태를
  /// 몰라도 그대로 안전하다.
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
        var corners = <Offset>[
          for (var i = 0; i < 8; i += 2) Offset(flat[i], flat[i + 1]),
        ];
        // ⚠️ 검출은 이 함수가 불릴 때(=initState, [widget.imagePath] 기준)
        // 시작했다. 그사이 [회전]을 눌렀으면(검출은 ~5ms 수준이라 극히
        // 드물다, 386 측정) 결과가 그만큼 낡은 방향이다 — [_bakeState
        // .pendingTurns]는 굽기가 끝나면 0으로 돌아가 이 보정에 못 쓰므로,
        // 굽기 완료와 무관하게 계속 누적되는 [_totalTurnsCwSinceOpen]으로
        // "지금 화면 방향" 기준으로 맞춘다.
        if (_totalTurnsCwSinceOpen != 0) {
          corners = _rotateNTimes(
            corners,
            times: _totalTurnsCwSinceOpen,
            clockwise: true,
          );
        }
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
    // ⚠️ **[_visualImageSize]를 쓴다**([_imageSize]가 아니다) — 회전을 눌러
    // 밀린 회전이 있는 동안은 화면([RotatedBox])만 돌아가 있고 실제 파일은
    // 아직 그대로다. 여기서 파일 크기를 쓰면 홀수 번 밀린 상태에서 손잡이가
    // 엉뚱한 자리에 잡힌다.
    final image = _visualImageSize;
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
    final image = _visualImageSize; // 이유는 [_nearestCorner] 주석 참고.
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
  /// 이미지 실제 크기를 아직 모르는가 — 회전·확정 버튼이 기준으로 삼는
  /// 값이라 로딩 전에는 손대면 안 된다(추가 407 ②).
  bool get _isImageSizeUnknown => _imageSize == null;

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
                        onPressed: _isFinalizing ? null : _skip,
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
                  // ⚠️ **[_isFinalizing]일 때만 막는다** — 회전은 백그라운드
                  // 굽기라 화면을 가릴 이유가 없다([_rotateBy] 문서 참고).
                  // 밀린 굽기를 기다리는 건 [자르기 확정]을 누른 뒤뿐이다.
                  : (_imageSize == null || _isFinalizing)
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
                              // ⚠️ **화면만 즉시 돌린다** — 실제 파일
                              // ([_imagePath])은 아직 그대로일 수 있다
                              // ([_rotateBy] 문서 참고). [_bakeState
                              // .pendingTurns]가 0으로 돌아오는 순간
                              // `quarterTurns`도 0이 되므로, 그 시점엔
                              // 파일 자체가 이미 그 방향으로 구워져 있어
                              // 시각 결과가 그대로 이어진다(흔들림 없음).
                              RotatedBox(
                                quarterTurns: _bakeState.pendingTurns,
                                child: Image.file(
                                  File(_imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              // 모서리 핸들 — 상시 노출(자동/직접 조정 공통).
                              // ⚠️ [RotatedBox] 밖에 그대로 둔다 —
                              // [_corners]가 이미 "지금 보이는 방향" 기준
                              // (visual frame)이라 [_visualImageSize]로
                              // 매핑하면 화면과 그대로 맞는다. 여기를
                              // [RotatedBox] 안에 넣으면 이중으로 돌아간다.
                              CustomPaint(
                                painter: _CropPainter(
                                  corners: _corners,
                                  imageSize: _visualImageSize!,
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
                  // 반시계 — 실기기 피드백("반시계 회전이 안 된다") 대응.
                  //
                  // ⚠️ [_isImageSizeUnknown]일 때도 비활성화한다(추가 407
                  // ②) — [_rotateBy]가 내부에서 이미 null 가드를 하므로
                  // 크래시는 안 나지만, 눌러도 아무 반응이 없는 죽은 버튼을
                  // 보여주는 것 자체가 혼동이다.
                  OutlinedButton(
                    onPressed: (_isFinalizing || _isImageSizeUnknown)
                        ? null
                        : () => _rotateBy(clockwise: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    child: const Icon(Icons.rotate_left, size: 20),
                  ),
                  const SizedBox(width: 10),
                  // F-03: 자동이 잘못 잘랐을 때 실제로 돌려 볼 수 있어야
                  // 한다. 좌표는 섞지 않는다 — [_rotateBy] 문서 참고.
                  OutlinedButton(
                    onPressed: (_isFinalizing || _isImageSizeUnknown)
                        ? null
                        : () => _rotateBy(clockwise: true),
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
                  // [다시 찾기] — 귀퉁이를 지금 모드의 시작 자리로 되돌린다.
                  //
                  // ⚠️ 예전엔 Icons.replay(원형 화살표)라 옆의 회전 버튼
                  // 둘(마찬가지로 원형 화살표)과 혼동됐다 — 실기기에서
                  // 사용자가 "되돌리기 버튼인가?"라고 물었다(추가 407 ①).
                  // Icons.undo는 회전류 아이콘과 모양이 뚜렷이 다르고,
                  // "되돌리기"라는 사용자의 심성 모델과도 맞아 이걸로
                  // 바꿨다. Tooltip·Semantics로 역할도 함께 읽히게 한다.
                  Tooltip(
                    message: '귀퉁이 되돌리기',
                    child: Semantics(
                      label: '귀퉁이 되돌리기',
                      hint: '귀퉁이를 지금 모드의 시작 위치로 되돌립니다',
                      button: true,
                      child: OutlinedButton(
                        onPressed: _isFinalizing ? null : _resetCorners,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        child: const Icon(Icons.undo, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          (_isUsable && !_isFinalizing && !_isImageSizeUnknown)
                          ? _confirm
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(_isFinalizing ? '처리 중…' : '이대로 자르기'),
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
