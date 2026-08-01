import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';

class QrCodeModalView extends StatefulWidget {
  const QrCodeModalView({super.key});

  @override
  State<QrCodeModalView> createState() => _QrCodeModalViewState();
}

class _QrCodeModalViewState extends State<QrCodeModalView> {
  bool _isScannerMode = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modal Handle Bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Segmented Tab Selector
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isScannerMode = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isScannerMode ? AppColors.accentText : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '내 명함 QR 코드',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: !_isScannerMode ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isScannerMode = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isScannerMode ? AppColors.accentText : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '상대방 QR 스캔',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _isScannerMode ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (!_isScannerMode) ...[
              // QR Code Display View
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.qr_code_2,
                        size: 180,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '홍길동 대표 / 커넥션 트레이스 AI',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '스캔하면 디지털 명함이 자동으로 저장됩니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Camera Scanner View Simulator
              GlassCard(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.accentText, width: 2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        const Icon(Icons.qr_code_scanner, size: 80, color: AppColors.accentText),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '명함 QR 코드를 카메라 프레임에 맞춰주세요.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
