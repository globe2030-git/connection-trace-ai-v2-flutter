import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';

class CameraScanModalView extends StatefulWidget {
  const CameraScanModalView({super.key});

  @override
  State<CameraScanModalView> createState() => _CameraScanModalViewState();
}

class _CameraScanModalViewState extends State<CameraScanModalView> with SingleTickerProviderStateMixin {
  late AnimationController _laserController;
  bool _isFlashOn = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    // 실제 네이티브 카메라 앱을 열어 사진을 찍는다. 이 화면의 가이드 프레임/레이저
    // 애니메이션은 "명함을 어떻게 맞춰 찍을지" 안내용 UI로 남겨두고, 실제 촬영
    // 자체는 기기 카메라 앱에 맡긴다(커스텀 라이브 프리뷰를 새로 구현하는 대신).
    final image = await OcrScannerService.pickImage(fromCamera: true);
    if (image == null || !mounted) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final scanResult = await OcrScannerService.scanBusinessCard(image);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Viewfinder Background Simulation
            Container(
              width: double.infinity,
              height: double.infinity,
              color: AppColors.bgDarkSlate,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Subtle camera grain grid
                  Icon(Icons.camera, size: 180, color: Colors.white.withValues(alpha: 0.04)),
                  if (_isCapturing)
                    Container(
                      color: Colors.black.withValues(alpha: 0.7),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
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

            // Top Header Bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
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
                    onPressed: () => setState(() => _isFlashOn = !_isFlashOn),
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
                    width: 320,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.accentText, width: 1.5),
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
                  onTap: _isCapturing ? null : _capturePhoto,
                  child: Container(
                    width: 76,
                    height: 76,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
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
