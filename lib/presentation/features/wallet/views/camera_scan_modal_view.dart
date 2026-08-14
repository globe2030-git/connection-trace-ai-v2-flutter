import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/frame_contrast.dart';
import '../../../../core/services/ocr_scanner_service.dart';

class CameraScanModalView extends StatefulWidget {
  /// 지금 찍는 면("앞면"/"뒷면"). 화면 아래에 항상 띄운다.
  ///
  /// 명함 한 장은 앞면과 뒷면까지가 최대인데(추가 189), 카메라 화면에는 지금
  /// 무엇을 찍는 중인지 표시가 없어서 뒷면 스캔을 고르고 들어와도 알 수 없었다.
  /// 다른 명함 앱들이 공통으로 이 라벨을 두고 있다(2026-08-14 참고 자료).
  final String sideLabel;

  const CameraScanModalView({super.key, this.sideLabel = '앞면'});

  @override
  State<CameraScanModalView> createState() => _CameraScanModalViewState();
}

class _CameraScanModalViewState extends State<CameraScanModalView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 국내 명함 표준 규격(90×50mm, 가로세로비 약 1.8:1)이지만, 가이드
  // 프레임 자체는 세로로 긴 모양(비율을 뒤집음)으로 그린다. 폰은 계속
  // 세로로 잡고, 명함을 시계 방향으로 90도 돌려서 그 세로 프레임 안에
  // 맞춰 넣는 방식 — 2026-08-03에 화면 자체를 가로로 고정했다가 "버튼
  // 조작이 어려워졌다"는 피드백으로 되돌렸고, 이후 다시 화면 회전
  // 방식으로 시도했으나(2026-08-06 오전) 사용자가 다른 명함 앱 영상을
  // 보여주며 "이 방법이 아니다"라고 정정함 — 화면/기기는 그대로 세로
  // 유지하고 명함만 돌려서 넣는 게 맞는 방식이었다(2026-08-06 저녁,
  // backlog 추가 85). 세로 프레임에 맞춰 명함을 최대한 크게(고해상도로)
  // 담을 수 있는 장점도 있다. 촬영 후 [_cropToGuideFrame]에서 크롭한
  // 결과물을 고정 -90도(반시계) 회전시켜 정방향으로 되돌린다 — 기기
  // 회전이 없으므로 EXIF 기반이 아니라 항상 같은 방향으로 고정 회전.
  // 실제 픽셀 크기는 화면 크기별로 [_guideFrameSizeFor]가 다시 계산한다.
  static const _cardAspectRatio = 184 / 330;

  // 자동 촬영 안정성 감지 파라미터 — 명함이 프레임 안에서 흔들리지 않고
  // 멈춰 있다고 판단되면 자동으로 셔터를 누른다. 셔터 버튼을 손가락으로
  // 눌러서 생기는 순간적인 흔들림(모션 블러)이 OCR 인식률을 떨어뜨리는
  // 주된 원인이라, 사용자가 직접 누르지 않아도 되게 하는 게 목적.
  // 임계값을 넉넉히 잡아 자연스러운 손떨림 정도는 "불안정"으로 치지 않게
  // 하고(정렬 여유), 실제 촬영은 프레임 개수가 아니라 안정 상태가 시작된
  // 시점부터 경과 시간으로 판단한다(기기 프레임레이트와 무관하게 일정
  // 시간 유지되면 촬영). 유지 시간은 2026-08-06 저녁 사이 0.15초 → 1초 →
  // 0.5초 → 0.25초 → 0.2초로 여러 차례 재조정됐다(짧다/길다 피드백이
  // 반복돼 왔다는 뜻 — 값 자체보다 "사용자가 직접 다시 조정을 요청할 수
  // 있다"는 점을 기억할 것). 임계값은 "가이드 안에
  // 훨씬 정확히 들어와야(≈95%) 촬영되면 좋겠다"는 요청에 맞춰 다시
  // 좁혔다 — 실제로 카드-가이드 겹침 비율을 픽셀 단위로 재는 건 아니고
  // (별도의 문서 경계 검출이 필요한 더 큰 작업), 전체 화면 흔들림
  // 허용치를 좁혀서 더 정확히 멈춰야만 "안정"으로 인정되게 하는 근사치.
  static const _stabilityDiffThreshold = 8.0;
  static const _requiredStableDuration = Duration(milliseconds: 200);
  static const _sampleGridSize = 24;
  static const _autoCaptureWarmup = Duration(milliseconds: 900);
  // 카메라는 초당 30~60프레임을 보내지만 흔들림 판단에는 8fps면
  // 충분하다. 나머지 프레임은 즉시 버려 CPU·배터리 사용을 줄인다.
  static const _frameAnalysisInterval = Duration(milliseconds: 125);
  /// 가이드 프레임 안쪽 밝기의 **표준편차** 하한. 이 아래면 "볼 것이 없다"로
  /// 보고 자동 촬영하지 않는다.
  ///
  /// 왜 필요한가: 예전 자동 촬영 조건은 **"화면이 흔들리지 않으면"** 하나뿐이라
  /// **명함이 있는지는 보지 않았다.** 그래서 빈 벽이나 책상을 향해 가만히 들고
  /// 있으면 — 오히려 가장 안정적이라 — 자동으로 찍혔다(테스터 E-01
  /// "촬영 버튼을 누르지 않았는데 빈 공간이 촬영됨"). 역설적으로 빈 공간이 더
  /// 잘 찍히는 구조였다.
  ///
  /// 글자가 있는 명함은 밝고 어두운 픽셀이 섞여 표준편차가 크고(대개 25 이상),
  /// 민무늬 벽·책상은 거의 평평하다(10 미만). **낮게 잡아 명백히 빈 장면만**
  /// 막는다 — 임계값을 높이면 진짜 명함까지 자동 촬영이 안 되는데, 그쪽이 더
  /// 나쁜 고장이다(셔터는 언제든 직접 누를 수 있다).
  /// ⚠️ **이 값은 추측으로 정하면 안 된다.** 처음 10.0으로 잡았다가 진짜 명함이
  /// 자동 촬영되지 않는 회귀를 냈다(사용자 제보 2026-08-14 "조절하고 나니까
  /// 명함을 가이드가 파란색으로 변하지를 않아").
  ///
  /// 원인: 격자가 24×24로 거칠어서 **명함 글자를 거의 밟지 못한다.** 대부분의
  /// 샘플이 바탕에 떨어져 표준편차가 생각보다 훨씬 작다. 촘촘한 체커보드로
  /// 만든 테스트가 실제 샘플링 밀도를 반영하지 못했다 — 숫자만 보고 세운
  /// 가설이 틀린 또 하나의 사례다.
  ///
  /// 그래서 **민무늬 면만 겨우 걸러낼 만큼** 낮춘다. 실기기에서 실제 값을 읽어
  /// 본 뒤에 다시 조인다(디버그 빌드에 값이 화면에 뜬다).
  static const _minCenterContrast = 3.5;
  /// 가이드 안쪽에서 **한쪽 톤이 차지해야 하는 최소 비율**.
  ///
  /// 명함은 바탕이 지배적이라 대개 0.75 이상이다. 책상·벽 **모서리**는 밝은
  /// 면과 어두운 면이 반반이라 0.5 근처에 머문다 — 대비만 보면 오히려 커서
  /// 걸러지지 않던 장면이다. 밝은 명함과 어두운 명함을 모두 받으려고
  /// **더 많은 쪽**을 본다.
  /// 같은 이유로 느슨하게 잡는다. 모서리(0.5)와 명함을 가르되, 실측 전까지는
  /// **막지 않는 쪽**으로 기운다.
  static const _minDominantToneRatio = 0.55;

  late AnimationController _laserController;
  CameraController? _controller;
  bool _isInitializing = true;
  String? _initError;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _isStreamingForAutoCapture = false;
  bool _isFrameStable = false;
  /// 디버그 빌드에서만 화면에 띄우는 "대비 / 지배톤" 실측값.
  String? _debugMetrics;
  DateTime? _stableSince;
  List<int>? _previousLumaSample;
  DateTime? _streamStartedAt;
  DateTime? _lastAnalyzedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 이 화면은 **세로 전용**이다. 안내부터가 "명함을 시계 방향으로 90° 돌려서
    // 넣어주세요"이고, 가이드 프레임의 긴 변을 **화면 폭** 기준으로 잡는다.
    // 가로로 돌리면 폭이 높이보다 커져 가이드가 화면 밖으로 넘친다 — 실기기에서
    // `BOTTOM OVERFLOWED BY 52 PIXELS`가 떴다(사용자 제보 2026-08-14
    // "핸드폰을 90도 돌리니까 아래에 노란색이 보여").
    //
    // ⚠️ 그 노란 줄무늬는 **debug 빌드에서만** 보인다. release에서는 경고 없이
    // 촬영 버튼 아래 안내가 잘린다 — 보이지 않을 뿐 더 나쁘다.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (!OcrScannerService.isSupportedOnThisPlatform) {
      setState(() => _isInitializing = false);
      return;
    }
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        backCamera,
        // OCR 인식률 개선 요청(2026-08-06 밤)에 대응해 veryHigh(약 1080p)
        // 에서 기기가 지원하는 최대 해상도로 올렸다 — 명함 글자가 원본에서
        // 차지하는 실제 픽셀 수가 많을수록 ML Kit 인식률이 좋아진다. 파일
        // 용량/처리 시간이 늘지만 이 화면은 어차피 한 장씩 찍는 흐름이라
        // 감내 가능한 트레이드오프로 판단.
        ResolutionPreset.max,
        enableAudio: false,
        // takePicture()의 실제 촬영 결과물 포맷과는 무관하고(항상 JPEG),
        // startImageStream()으로 안정성(흔들림) 감지용 프레임을 받아오기
        // 위한 포맷 — yuv420이 플랫폼 간 가장 널리 지원됨.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      // 권한 요청 다이얼로그와 겹치거나 카메라가 다른 프로세스에 점유된
      // 경우 등, initialize()가 예외 없이 그냥 끝없이 대기만 하는 경우가
      // 있었다(사용자 제보 — 화면이 로딩 스피너에서 멈춤). 일정 시간 안에
      // 안 끝나면 에러로 처리해 재시도 버튼이 뜨게 한다.
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // 명함은 보통 10~15cm 거리에서 가깝게 촬영하는데, 초점 관련 설정을
      // 전혀 안 건드리면 기기에 따라 초기 초점이 먼 거리에 맞춰진 채
      // 안 움직이거나(특히 iOS) 흐릿하게 남는 경우가 있었다(사용자 제보 —
      // "카메라 초점이 흐려"). 가이드 프레임이 있는 화면 중앙에 지속
      // 자동초점 지점을 명시적으로 지정해 근거리에서도 계속 초점을
      // 다시 잡도록 한다. 지원 안 하는 기기/플랫폼은 조용히 무시.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } catch (_) {}
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
      await _startAutoCaptureStream();
    } catch (e) {
      // 타임아웃으로 포기한 뒤 initialize()가 뒤늦게 성공해도 카메라를
      // 계속 붙들고 있으면 재시도 시 "카메라 사용 중" 에러가 나므로
      // 반드시 놓아준다.
      try {
        await controller?.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _initError = '카메라를 시작할 수 없습니다.\n설정에서 카메라 접근 권한을 확인해 주세요.\n($e)';
        _isInitializing = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 긴급재난문자 등으로 잠깐 inactive가 됐다가 바로 resumed로 돌아오는
      // 경우, 컨트롤러를 dispose하기 전에 먼저 화면(CameraPreview)에서
      // 떼어내야 한다 — setState 없이 필드만 바꾸면 아직 화면에 남아 있는
      // CameraPreview가 이미 dispose된 컨트롤러를 계속 참조하게 되어
      // 화면이 검정으로 멈춰버리는 문제가 있었다.
      final wasStreaming = _isStreamingForAutoCapture;
      setState(() {
        _controller = null;
        _isStreamingForAutoCapture = false;
        _isFrameStable = false;
        _stableSince = null;
        _isInitializing = true;
      });
      () async {
        if (wasStreaming) {
          try {
            await controller.stopImageStream();
          } catch (_) {}
        }
        await controller.dispose();
      }();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 이 화면을 벗어나면 회전 제한을 반드시 푼다 — 안 그러면 앱 전체가 세로로
    // 묶인다.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _laserController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_isFlashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _isFlashOn = next);
    } catch (_) {
      // 일부 기기는 토치를 지원하지 않음 — 조용히 무시.
    }
  }

  /// 카메라 프리뷰 스트림을 받아 연속된 프레임 간 밝기 차이(흔들림 정도)를
  /// 측정한다. 일정 프레임 이상 안정 상태가 유지되면 자동으로 촬영한다.
  /// 정밀한 카드 사각형 인식(엣지 검출)까지는 아니고 "흔들리지 않고 멈춰
  /// 있는가"만 보는 가벼운 방식이지만, 셔터를 손으로 눌러서 생기는 흔들림을
  /// 없애는 실제 목적에는 충분하다.
  Future<void> _startAutoCaptureStream() async {
    final controller = _controller;
    if (controller == null || _isStreamingForAutoCapture) return;
    _streamStartedAt = DateTime.now();
    _stableSince = null;
    _previousLumaSample = null;
    _lastAnalyzedAt = null;
    try {
      await controller.startImageStream(_onCameraFrame);
      _isStreamingForAutoCapture = true;
    } catch (_) {
      // 스트리밍이 안 되는 기기/상태면 조용히 포기 — 수동 셔터 버튼은 계속 동작.
    }
  }

  Future<void> _stopAutoCaptureStream() async {
    final controller = _controller;
    if (controller == null || !_isStreamingForAutoCapture) return;
    _isStreamingForAutoCapture = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  void _onCameraFrame(CameraImage image) {
    if (_isCapturing || !mounted) return;
    final now = DateTime.now();
    final lastAnalyzedAt = _lastAnalyzedAt;
    if (lastAnalyzedAt != null &&
        now.difference(lastAnalyzedAt) < _frameAnalysisInterval) {
      return;
    }
    _lastAnalyzedAt = now;
    // 카메라가 막 열렸을 때 자동 노출/초점이 안정되기 전까지는 안정 여부
    // 판단을 건너뛴다 — 오탐(초점 잡는 중인데 "안정됨"으로 오인) 방지.
    final startedAt = _streamStartedAt;
    if (startedAt != null && now.difference(startedAt) < _autoCaptureWarmup) {
      return;
    }

    final sample = _sampleLuma(image);
    final previous = _previousLumaSample;
    _previousLumaSample = sample;
    if (previous == null || previous.length != sample.length) return;

    double diffSum = 0;
    for (var i = 0; i < sample.length; i++) {
      diffSum += (sample[i] - previous[i]).abs();
    }
    final avgDiff = diffSum / sample.length;

    // 흔들리지 않는 것만으로는 부족하다 — **가이드 안에 볼 것이 있어야** 한다.
    // 대비 하나로는 모자랐다. 책상·벽 모서리처럼 **각이 진 빈 곳**은 밝은 면과
    // 어두운 면이 반반이라 대비가 오히려 크다(사용자 제보 "빈공간을 찍지는
    // 않는데 각이진 빈곳은 자동 촬영되").
    //
    // 명함은 **바탕이 지배적**이고 글자가 소수다 — 밝든 어둡든 한쪽 톤이
    // 대부분이다. 모서리 장면은 대략 반반이라 여기서 갈린다.
    final contrast = centerFrameContrast(sample, gridSize: _sampleGridSize);
    final dominantTone = centerDominantToneRatio(
      sample,
      gridSize: _sampleGridSize,
    );
    final hasContent =
        contrast >= _minCenterContrast &&
        dominantTone >= _minDominantToneRatio;

    // 임계값을 추측으로 정했다가 진짜 명함을 막는 회귀를 냈다. 실기기에서
    // **실제 장면의 값을 읽을 수 있어야** 제대로 정할 수 있다 — 디버그
    // 빌드에서만 화면에 띄운다(테스터 배포는 release라 보이지 않는다).
    if (kDebugMode) {
      final rounded = '${contrast.toStringAsFixed(1)} / '
          '${dominantTone.toStringAsFixed(2)}';
      if (rounded != _debugMetrics) {
        setState(() => _debugMetrics = rounded);
      }
    }

    if (avgDiff < _stabilityDiffThreshold && hasContent) {
      _stableSince ??= now;
    } else {
      _stableSince = null;
    }

    final stableSince = _stableSince;
    final nowStable = stableSince != null;
    if (nowStable != _isFrameStable) {
      setState(() => _isFrameStable = nowStable);
    }

    if (stableSince != null &&
        now.difference(stableSince) >= _requiredStableDuration) {
      _stableSince = null;
      _capturePhoto();
    }
  }

  /// 프레임 전체를 다 볼 필요 없이 Y(밝기) 평면에서 격자 형태로 샘플링만
  /// 해서 가볍게 비교한다 — 매 프레임 호출되므로 연산량을 최소화해야 함.
  List<int> _sampleLuma(CameraImage image) {
    final plane = image.planes.first;
    final bytesPerRow = plane.bytesPerRow;
    final height = image.height;
    final width = image.width;
    final result = <int>[];
    for (var gy = 0; gy < _sampleGridSize; gy++) {
      final y = (gy * height ~/ _sampleGridSize).clamp(0, height - 1);
      for (var gx = 0; gx < _sampleGridSize; gx++) {
        final x = (gx * width ~/ _sampleGridSize).clamp(0, width - 1);
        final index = y * bytesPerRow + x;
        if (index >= 0 && index < plane.bytes.length) {
          result.add(plane.bytes[index]);
        }
      }
    }
    return result;
  }

  /// 촬영은 했지만 아직 인식(OCR)을 돌리지 않은 사진.
  ///
  /// 예전에는 셔터를 누르면 곧바로 인식까지 하고 화면을 닫았다. 그래서 **초점이
  /// 나간 사진도 그대로 인식**됐고(테스터 E-04), 사용자는 결과를 본 뒤에야
  /// 잘못 찍은 걸 알았다. 인식 전에 한 번 보여주고 [다시 찍기]/[확인]을 받는다.
  XFile? _pendingShot;

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing)
      return;

    // takePicture()는 이미지 스트림이 활성화된 상태에서 호출하면 실패하는
    // 기기가 있어서, 촬영 직전엔 항상 스트림을 먼저 멈춘다.
    await _stopAutoCaptureStream();

    setState(() {
      _isCapturing = true;
      _isFrameStable = false;
      _stableSince = null;
    });

    try {
      final rawFile = await controller.takePicture();
      if (!mounted) return;
      final screenSize = MediaQuery.of(context).size;
      final croppedFile = await _cropToGuideFrame(rawFile, screenSize);
      if (!mounted) return;
      // 바로 인식하지 않고 먼저 보여준다 — 흐린 사진으로 인식을 돌리는 낭비와
      // "결과를 봐야 잘못 찍은 걸 아는" 문제를 없앤다.
      setState(() {
        _pendingShot = croppedFile;
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 명함 인식에 실패했습니다: $e'),
          backgroundColor: AppColors.destructive,
        ),
      );
      // 실패해서 다시 화면이 보이는 상태로 남으면, 재시도할 수 있게 안정성
      // 감지를 다시 시작한다.
      await _startAutoCaptureStream();
    }
  }

  /// 보여준 사진으로 인식을 진행한다.
  Future<void> _confirmPendingShot() async {
    final shot = _pendingShot;
    if (shot == null) return;
    setState(() => _isCapturing = true);
    try {
      final scanResult = await OcrScannerService.scanBusinessCard(shot);
      if (!mounted) return;
      Navigator.pop(context, scanResult);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _pendingShot = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 명함 인식에 실패했습니다: $e'),
          backgroundColor: AppColors.destructive,
        ),
      );
      await _startAutoCaptureStream();
    }
  }

  /// 방금 찍은 사진을 버리고 다시 촬영 상태로 돌아간다.
  Future<void> _retakePendingShot() async {
    setState(() {
      _pendingShot = null;
      _isCapturing = false;
    });
    await _startAutoCaptureStream();
  }

  /// 가이드 박스의 실제 픽셀 크기를 현재 화면 크기 기준으로 계산한다.
  /// 명함의 긴 변(90mm)이 화면에서 차지하는 크기를 화면 "폭"의 86%로 고정
  /// 한다 — 가로 모드였을 때 긴 변(가로)을 이 기준으로 잡았던 것과 동일한
  /// 값이다. 세로 가이드로 바뀌면서 긴 변이 세로가 됐다고 화면 "높이"
  /// 기준(예: 0.62)으로 잡으면, 화면 높이가 폭보다 훨씬 크기 때문에 실제
  /// 화면에 표시되는 카드 이미지가 훨씬 커지고, 그만큼 사용자가 카메라를
  /// 명함에 더 가깝게 대야 한다 — 그 결과 카메라 렌즈의 최소 초점 거리보다
  /// 가까워져 초점이 영영 안 맞는 문제가 있었다(2026-08-06 실기기 확인,
  /// "가이드에 맞추려 가까이 가면서 초점을 못맞춤"). 촬영 거리를 가로
  /// 모드 때와 동일하게 유지하는 게 핵심이라, 긴 변 크기는 화면 폭 기준을
  /// 그대로 쓰고 짧은 변은 비율로 계산한다. 화면이 유난히 작아 긴 변이
  /// 세로 공간을 넘칠 때만 안전장치로 줄인다.
  Size _guideFrameSizeFor(Size screenSize) {
    var longEdge = screenSize.width * 0.86;
    // 화면이 낮으면(가로 방향, 폴더블 펼침) 가이드가 세로로 넘친다. 위아래
    // 안내 문구와 촬영 버튼이 함께 들어가야 하므로 **높이의 0.72까지만** 쓴다.
    //
    // ⚠️ 예전 상한은 0.8이었는데, 그것만으로는 모자라 가로에서
    // `BOTTOM OVERFLOWED BY 52 PIXELS`가 떴다(사용자 제보 "핸드폰을 90도
    // 돌리니까 아래에 노란색이 보여"). 세로 고정(`setPreferredOrientations`)도
    // 함께 걸었지만 **Android는 큰 화면에서 앱의 방향 제한을 무시한다** —
    // 폴더블 펼친 화면에서는 여전히 가로가 되므로 크기 자체를 맞춰야 한다.
    final maxLongEdge = screenSize.height * 0.72;
    if (longEdge > maxLongEdge) longEdge = maxLongEdge;
    final shortEdge = longEdge * _cardAspectRatio;
    return Size(shortEdge, longEdge);
  }

  /// 화면에 보이는 가이드 프레임(카드 사각형) 위치를 실제 촬영본의 픽셀 좌표로
  /// 환산해 크롭한다. 프리뷰는 [_buildCameraPreview]에서 cover 방식(화면을
  /// 꽉 채우고 넘치는 부분은 잘림)으로 그리므로, 화면 중심 기준 비율을 그대로
  /// 이미지에 적용하면 동일한 영역이 나온다. 명함 주변 배경 글자/노이즈를
  /// 제거해 OCR 인식률을 높이는 게 목적이며, 실제 명함 규격이 제각각이라
  /// (표준 90x50mm 외에도 크고 작은 변형이 흔함) 계산이 살짝 어긋나거나
  /// 카드가 가이드보다 커도 잘리지 않도록 가이드 프레임보다 30% 여유를 두고
  /// 크롭 범위를 화면 안으로 clamp한다.
  Future<XFile> _cropToGuideFrame(XFile rawFile, Size screenSize) async {
    try {
      final bytes = await rawFile.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return rawFile;
      decoded = img.bakeOrientation(decoded);

      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();
      final screenAspect = screenSize.width / screenSize.height;
      final imageAspect = imgW / imgH;

      double visibleImgW, visibleImgH;
      if (imageAspect > screenAspect) {
        visibleImgH = imgH;
        visibleImgW = imgH * screenAspect;
      } else {
        visibleImgW = imgW;
        visibleImgH = imgW / screenAspect;
      }
      final offsetX = (imgW - visibleImgW) / 2;
      final offsetY = (imgH - visibleImgH) / 2;

      // 가이드 프레임보다 **넓게** 잘라낸다.
      //
      // ⚠️ 이 값은 한 번 되돌아간 적이 있다. `db605ef`가 **"명함 주변 텍스트
      // 잘림을 방지하기 위해"** 1.5로 넓혔는데, 뒤이은 스타일 커밋 `8fb5ff3`이
      // 배경 노이즈를 없애려고 **1.0(여유 없음)**으로 바꿨다. 그러자 1.5가
      // 막고 있던 결함이 그대로 돌아왔다 — 사용자 제보 "가이드에 맞춰 자동으로
      // 찍힌 명함의 양쪽 끝 글씨가 30~40% 잘린다"(2026-08-14).
      //
      // **잘린 글자는 되찾을 수 없고, 섞인 배경은 파서가 걸러낸다.** 어느
      // 쪽으로 틀릴지 골라야 한다면 넓게 자르는 쪽이다. 배경 글자가 필드를
      // 침범하던 문제는 그 뒤 파싱 규칙에서 많이 잡혔다(추가 199~201).
      const margin = 1.5;
      final guideSize = _guideFrameSizeFor(screenSize);
      final guideW = guideSize.width * margin;
      final guideH = guideSize.height * margin;
      final scaleX = visibleImgW / screenSize.width;
      final scaleY = visibleImgH / screenSize.height;

      final cropW = (guideW * scaleX).clamp(1.0, imgW);
      final cropH = (guideH * scaleY).clamp(1.0, imgH);
      final rawCropX = offsetX + (visibleImgW - cropW) / 2;
      final rawCropY = offsetY + (visibleImgH - cropH) / 2;
      final cropX = rawCropX.clamp(0.0, imgW - cropW);
      final cropY = rawCropY.clamp(0.0, imgH - cropH);

      var cropped = img.copyCrop(
        decoded,
        x: cropX.round(),
        y: cropY.round(),
        width: cropW.round(),
        height: cropH.round(),
      );

      // 가이드 프레임이 세로로 길어서 사용자가 명함을 시계 방향으로 90도
      // 돌려 넣었으므로, 크롭한 결과물은 항상 옆으로 누운 상태다. 기기
      // 자체는 회전하지 않았으니 EXIF가 아니라 고정 각도(반시계 90도)로
      // 되돌리면 된다 — 실제 촬영 영상에서 이 방향으로 확인함.
      cropped = img.copyRotate(cropped, angle: -90);

      final jpgBytes = img.encodeJpg(cropped, quality: 100);
      final outPath =
          '${Directory.systemTemp.path}/card_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpgBytes);
      return XFile(outPath);
    } catch (_) {
      // 크롭 계산이 실패하면 원본을 그대로 사용 — 카드 일부가 잘리는 것보다
      // 배경이 좀 섞이는 게 낫다.
      return rawFile;
    }
  }

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;
    final guideSize = _guideFrameSizeFor(MediaQuery.of(context).size);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Viewfinder — 실제 후면 카메라 실시간 프리뷰.
            Positioned.fill(
              child: Container(
                // ⚠️ 카메라 자리는 **검정**이어야 한다. 예전에는 밝은
                // `AppColors.bgBase`(0xFFF7F8FA)라, 카메라가 준비되는 동안
                // 화면이 통째로 하얬다 — 사용자 제보 "카메라가 하얀색이다가
                // 좀 늦게 화면이 보여". Android는 초기화가 더 느려서 그 흰
                // 화면이 더 오래 노출된다(통합본 E-01·E-06 관련).
                //
                // 아래 워터마크 아이콘이 `white.withValues(alpha: 0.04)`인
                // 것이 원래 어두운 배경을 전제했다는 증거다 — 흰 배경에서는
                // 보이지도 않았다.
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isReady) _buildCameraPreview(),
                    if (!isReady && !_isInitializing && _initError == null)
                      Icon(
                        Icons.camera,
                        size: 180,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    // 기다리는 동안 "고장난 것"처럼 보이지 않게 무엇을 하는
                    // 중인지 알린다. 카메라 초기화는 기기에 따라 몇 초
                    // 걸리는데(Android가 더 느리다), 안내가 없으면 그 시간이
                    // 통째로 오류처럼 읽힌다.
                    if (_isInitializing)
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 14),
                          Text(
                            '카메라를 준비하는 중이에요',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    if (_initError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _initError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 권한을 "다시 묻지 않음"으로 거부한 뒤에는 앱이
                                // 다시 권한 팝업을 띄울 수 없어, OS 설정 화면으로
                                // 직접 보내는 것이 유일한 복구 경로다(P2-6).
                                // geolocator의 openAppSettings는 위치 전용이
                                // 아니라 이 앱의 설정 페이지를 여는 범용 유틸이다.
                                OutlinedButton.icon(
                                  onPressed: () => Geolocator.openAppSettings(),
                                  icon: const Icon(Icons.settings, size: 18),
                                  label: const Text('설정 열기'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _initError = null;
                                      _isInitializing = true;
                                    });
                                    _initCamera();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (_isCapturing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: AppColors.accentText,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '📸 촬영한 사진을 다듬는 중…',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Top Header Bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        '명함 카메라 스캔',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: _isFlashOn
                              ? AppColors.accentText
                              : Colors.white,
                          size: 24,
                        ),
                        onPressed: isReady ? _toggleFlash : null,
                      ),
                    ],
                  ),
                  if (!OcrScannerService.isSupportedOnThisPlatform)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '웹 브라우저에서는 OCR 인식이 지원되지 않습니다. 모바일 앱에서 테스트해 주세요.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),

            // Business Card Bounding Guide Frame Overlay
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isFrameStable)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.rotate_90_degrees_cw,
                            color: Colors.white70,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '명함을 시계 방향으로 90° 돌려서 넣어주세요',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: guideSize.width,
                    height: guideSize.height,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFrameStable ? AppColors.accent : Colors.white,
                        width: _isFrameStable ? 3 : 1.5,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Animated Scanning Laser Line
                        AnimatedBuilder(
                          animation: _laserController,
                          builder: (context, child) {
                            return Positioned(
                              top:
                                  _laserController.value *
                                  (guideSize.height - 10),
                              left: 10,
                              right: 10,
                              child: Container(
                                height: 2,
                                color: AppColors.accentText,
                              ),
                            );
                          },
                        ),
                        // Corner Guides
                        const Positioned(
                          top: 12,
                          left: 12,
                          child: Icon(
                            Icons.crop_free,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                        const Positioned(
                          bottom: 12,
                          right: 12,
                          child: Icon(
                            Icons.crop_free,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isFrameStable
                              ? '고정됨 · 자동으로 촬영합니다'
                              : '가이드 틀 안에 명함을 맞추고 잠시 멈춰 주세요',
                          style: TextStyle(
                            color: _isFrameStable
                                ? AppColors.accent
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // 디버그 빌드에서만 보이는 실측값(대비 / 지배톤).
                        // 자동 촬영 임계값을 **추측으로 정했다가 진짜 명함을
                        // 막는 회귀**를 냈다. 실제 장면의 숫자를 읽을 수 있어야
                        // 제대로 정할 수 있다. release 빌드에는 안 나온다.
                        if (kDebugMode && _debugMetrics != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '대비/지배톤 $_debugMetrics '
                              '(기준 $_minCenterContrast / '
                              '$_minDominantToneRatio)',
                              style: const TextStyle(
                                color: Colors.amberAccent,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 방금 찍은 사진 확인 — 인식 전에 [다시 찍기]/[확인]을 받는다.
            if (_pendingShot != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Image.file(
                            File(_pendingShot!.path),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.sideLabel} · 글자가 또렷한가요?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isCapturing
                                        ? null
                                        : _retakePendingShot,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white54,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: const Text('다시 찍기'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isCapturing
                                        ? null
                                        : _confirmPendingShot,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: Text(_isCapturing ? '인식 중…' : '확인'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 지금 찍는 면 — 셔터 위에 항상 보인다.
            if (_pendingShot == null)
              Positioned(
                bottom: 118,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.sideLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom Shutter Controls
            if (_pendingShot == null)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: (_isCapturing || !isReady) ? null : _capturePhoto,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isReady
                              ? AppColors.accent
                              : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
