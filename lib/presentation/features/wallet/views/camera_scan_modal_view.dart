import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';

class CameraScanModalView extends StatefulWidget {
  const CameraScanModalView({super.key});

  @override
  State<CameraScanModalView> createState() => _CameraScanModalViewState();
}

class _CameraScanModalViewState extends State<CameraScanModalView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _guideFrameSize = Size(320, 200);

  // 자동 촬영 안정성 감지 파라미터 — 명함이 프레임 안에서 흔들리지 않고
  // 멈춰 있다고 판단되면 자동으로 셔터를 누른다. 셔터 버튼을 손가락으로
  // 눌러서 생기는 순간적인 흔들림(모션 블러)이 OCR 인식률을 떨어뜨리는
  // 주된 원인이라, 사용자가 직접 누르지 않아도 되게 하는 게 목적.
  static const _requiredStableFrames = 8;
  static const _stabilityDiffThreshold = 6.0;
  static const _sampleGridSize = 24;
  static const _autoCaptureWarmup = Duration(milliseconds: 900);

  late AnimationController _laserController;
  CameraController? _controller;
  bool _isInitializing = true;
  String? _initError;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _isStreamingForAutoCapture = false;
  bool _isFrameStable = false;
  int _stableFrameCount = 0;
  List<int>? _previousLumaSample;
  DateTime? _streamStartedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // takePicture()의 실제 촬영 결과물 포맷과는 무관하고(항상 JPEG),
        // startImageStream()으로 안정성(흔들림) 감지용 프레임을 받아오기
        // 위한 포맷 — yuv420이 플랫폼 간 가장 널리 지원됨.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
      await _startAutoCaptureStream();
    } catch (e) {
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _isStreamingForAutoCapture = false;
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    _stableFrameCount = 0;
    _previousLumaSample = null;
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
    // 카메라가 막 열렸을 때 자동 노출/초점이 안정되기 전까지는 안정 여부
    // 판단을 건너뛴다 — 오탐(초점 잡는 중인데 "안정됨"으로 오인) 방지.
    final startedAt = _streamStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) < _autoCaptureWarmup) {
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

    if (avgDiff < _stabilityDiffThreshold) {
      _stableFrameCount++;
    } else {
      _stableFrameCount = 0;
    }

    final nowStable = _stableFrameCount >= 3;
    if (nowStable != _isFrameStable) {
      setState(() => _isFrameStable = nowStable);
    }

    if (_stableFrameCount >= _requiredStableFrames) {
      _stableFrameCount = 0;
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

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;

    // takePicture()는 이미지 스트림이 활성화된 상태에서 호출하면 실패하는
    // 기기가 있어서, 촬영 직전엔 항상 스트림을 먼저 멈춘다.
    await _stopAutoCaptureStream();

    setState(() {
      _isCapturing = true;
      _isFrameStable = false;
    });

    try {
      final rawFile = await controller.takePicture();
      if (!mounted) return;
      final screenSize = MediaQuery.of(context).size;
      final croppedFile = await _cropToGuideFrame(rawFile, screenSize);
      final scanResult = await OcrScannerService.scanBusinessCard(croppedFile);
      if (!mounted) return;
      Navigator.pop(context, scanResult);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ 명함 인식에 실패했습니다: $e'), backgroundColor: AppColors.destructive),
      );
      // 실패해서 다시 화면이 보이는 상태로 남으면, 재시도할 수 있게 안정성
      // 감지를 다시 시작한다.
      await _startAutoCaptureStream();
    }
  }

  /// 화면에 보이는 가이드 프레임(카드 사각형) 위치를 실제 촬영본의 픽셀 좌표로
  /// 환산해 크롭한다. 프리뷰는 [_buildCameraPreview]에서 cover 방식(화면을
  /// 꽉 채우고 넘치는 부분은 잘림)으로 그리므로, 화면 중심 기준 비율을 그대로
  /// 이미지에 적용하면 동일한 영역이 나온다. 명함 주변 배경 글자/노이즈를
  /// 제거해 OCR 인식률을 높이는 게 목적이며, 계산이 살짝 어긋나도 카드가
  /// 잘리지 않도록 가이드 프레임보다 15% 여유를 두고 크롭 범위를 화면 안으로
  /// clamp한다.
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

      const margin = 1.15;
      final guideW = _guideFrameSize.width * margin;
      final guideH = _guideFrameSize.height * margin;
      final scaleX = visibleImgW / screenSize.width;
      final scaleY = visibleImgH / screenSize.height;

      final cropW = (guideW * scaleX).clamp(1.0, imgW);
      final cropH = (guideH * scaleY).clamp(1.0, imgH);
      final rawCropX = offsetX + (visibleImgW - cropW) / 2;
      final rawCropY = offsetY + (visibleImgH - cropH) / 2;
      final cropX = rawCropX.clamp(0.0, imgW - cropW);
      final cropY = rawCropY.clamp(0.0, imgH - cropH);

      final cropped = img.copyCrop(
        decoded,
        x: cropX.round(),
        y: cropY.round(),
        width: cropW.round(),
        height: cropH.round(),
      );

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

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Viewfinder — 실제 후면 카메라 실시간 프리뷰.
            Positioned.fill(
              child: Container(
                color: AppColors.bgDarkSlate,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isReady) _buildCameraPreview(),
                    if (!isReady && !_isInitializing && _initError == null)
                      Icon(Icons.camera, size: 180, color: Colors.white.withValues(alpha: 0.04)),
                    if (_isInitializing)
                      const CircularProgressIndicator(color: AppColors.accentText),
                    if (_initError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _initError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    if (_isCapturing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: AppColors.accentText),
                              SizedBox(height: 16),
                              Text(
                                '📸 명함 촬영 완료! AI 텍스트 추출 중...',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                        ),
                      )
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
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        '명함 카메라 스캔',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off, color: _isFlashOn ? AppColors.accentText : Colors.white, size: 24),
                        onPressed: isReady ? _toggleFlash : null,
                      ),
                    ],
                  ),
                  if (!OcrScannerService.isSupportedOnThisPlatform)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '웹 브라우저에서는 OCR 인식이 지원되지 않습니다. 모바일 앱에서 테스트해 주세요.',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _guideFrameSize.width,
                    height: _guideFrameSize.height,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isFrameStable ? Colors.greenAccent : Colors.white,
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
                              top: _laserController.value * 190,
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
                        const Positioned(top: 12, left: 12, child: Icon(Icons.crop_free, color: Colors.white70, size: 20)),
                        const Positioned(bottom: 12, right: 12, child: Icon(Icons.crop_free, color: Colors.white70, size: 20)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _isFrameStable ? '고정됨 · 자동으로 촬영합니다' : '가이드 틀 안에 명함을 맞추고 잠시 멈춰 주세요',
                      style: TextStyle(
                        color: _isFrameStable ? Colors.greenAccent : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                ],
              ),
            ),

            // Bottom Shutter Controls
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
                        color: isReady ? AppColors.accent : AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
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
