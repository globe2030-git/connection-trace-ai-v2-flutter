import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/vcard_util.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/glass_card.dart';

/// 내 명함을 vCard QR로 보여주거나, 상대방 명함 QR을 실제 카메라로 스캔해
/// [ContactModel]로 만든다. 스캔에 성공하면 이 화면은 [Navigator.pop]으로
/// 파싱된 ContactModel을 반환하고, 호출한 쪽(RadarView)이 그 값을 받아
/// AddCardModalView(prefillData: ...)를 이어서 연다.
class QrCodeModalView extends StatefulWidget {
  const QrCodeModalView({super.key});

  @override
  State<QrCodeModalView> createState() => _QrCodeModalViewState();
}

class _QrCodeModalViewState extends State<QrCodeModalView> {
  bool _isScannerMode = false;
  MobileScannerController? _scannerController;
  bool _isProcessingScan = false;
  String? _scanError;

  void _setScannerMode(bool value) {
    setState(() {
      _isScannerMode = value;
      _scanError = null;
      _isProcessingScan = false;
      if (value) {
        _scannerController ??= MobileScannerController(formats: const [BarcodeFormat.qrCode]);
      } else {
        _scannerController?.dispose();
        _scannerController = null;
      }
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessingScan) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null) return;

    final parsed = VCardUtil.decode(raw);
    if (parsed == null || (parsed['name'] ?? '').isEmpty) {
      setState(() => _scanError = '명함 QR 코드가 아닙니다. 상대방의 "내 명함 QR 코드" 화면을 스캔해 주세요.');
      return;
    }

    setState(() {
      _isProcessingScan = true;
      _scanError = null;
    });
    _scannerController?.stop();

    final contact = ContactModel(
      id: 'contact_${DateTime.now().millisecondsSinceEpoch}',
      name: parsed['name'] ?? '',
      company: parsed['company'] ?? '',
      title: parsed['title'] ?? '',
      phone: parsed['phone'] ?? '',
      email: parsed['email'] ?? '',
      address: parsed['address'],
      tags: const [],
      talkingPoints: const [],
    );

    Navigator.pop(context, contact);
  }

  @override
  Widget build(BuildContext context) {
    final myProfile = context.watch<MyProfileRepository>().profile;

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
                    onTap: () => _setScannerMode(false),
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
                    onTap: () => _setScannerMode(true),
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
              // QR Code Display View — 실제 vCard 데이터를 담은 스캔 가능한 QR.
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
                      child: QrImageView(
                        data: VCardUtil.encodeProfile(myProfile),
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${myProfile.name}${myProfile.title.isNotEmpty ? ' ${myProfile.title}' : ''} / ${myProfile.company}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '상대방이 스캔하면 디지털 명함이 자동으로 채워집니다.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Real Camera QR Scanner
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 260,
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            MobileScanner(
                              controller: _scannerController,
                              onDetect: _onDetect,
                              fit: BoxFit.cover,
                            ),
                            IgnorePointer(
                              child: Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.accentText, width: 2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                            if (_isProcessingScan)
                              Container(
                                color: Colors.black.withValues(alpha: 0.55),
                                child: const Center(
                                  child: CircularProgressIndicator(color: AppColors.accentText),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _scanError ?? '상대방의 명함 QR 코드를 카메라 프레임에 맞춰주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _scanError != null ? AppColors.destructive : AppColors.textPrimary,
                      ),
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
