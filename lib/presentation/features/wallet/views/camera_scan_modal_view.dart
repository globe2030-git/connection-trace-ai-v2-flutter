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

  late AnimationController _laserController;
  CameraController? _controller;
  bool _isInitializing = true;
  String? _initError;
  bool _isFlashOn = false;
  bool _isCapturing = false;

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
        imageFormatGroup: ImageFormatGroup.jpeg,
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

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);

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
                  Container(
                    width: _guideFrameSize.width,
                    height: _guideFrameSize.height,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 1.5),
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
                    child: const Text(
                      '가이드 틀 안에 명함을 맞추어 촬영해 주세요',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
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
