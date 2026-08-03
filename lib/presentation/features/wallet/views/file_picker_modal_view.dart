import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';

class FilePickerModalView extends StatefulWidget {
  const FilePickerModalView({super.key});

  @override
  State<FilePickerModalView> createState() => _FilePickerModalViewState();
}

class _FilePickerModalViewState extends State<FilePickerModalView> {
  // 이 화면은 자체 Scaffold 없이 showModalBottomSheet의 콘텐츠로만 쓰여서
  // ScaffoldMessenger.of(context)를 쓰면 스낵바가 모달 뒤 페이지로 가서 안 보이고,
  // Scaffold로 감싸면 시트 높이 계산과 충돌해 레이아웃이 깨진다 — 폼 안에 직접
  // 그리는 배너로 우회한다(add_card_modal_view.dart와 동일 패턴).
  String? _errorNotice;
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  bool _isPicking = false;
  bool _isProcessing = false;

  Future<void> _pickFromGallery() async {
    setState(() => _isPicking = true);
    try {
      final image = await OcrScannerService.pickImageFromGallery();
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImage = image;
        _pickedImageBytes = bytes;
      });
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _processSelectedImage() async {
    final image = _pickedImage;
    if (image == null) return;

    setState(() => _isProcessing = true);
    try {
      final result = await OcrScannerService.scanBusinessCard(image);
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorNotice = '⚠️ 명함 인식에 실패했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderDark,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.folder_open,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '갤러리에서 명함 이미지 선택',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_errorNotice != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.destructive.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.destructive,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorNotice!,
                        style: const TextStyle(
                          color: AppColors.destructive,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.destructive,
                      ),
                      onPressed: () => setState(() => _errorNotice = null),
                    ),
                  ],
                ),
              ),

            if (!OcrScannerService.isSupportedOnThisPlatform)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.destructive.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.destructive,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '웹 브라우저에서는 OCR 인식이 지원되지 않습니다. 이미지 선택은 미리 볼 수 있지만, 실제 텍스트 인식은 모바일(Android/iOS) 앱에서만 가능합니다.',
                        style: TextStyle(
                          color: AppColors.destructive,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 실제 기기 갤러리에서 고른 이미지 미리보기 / 선택 트리거
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: _pickedImageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _pickedImageBytes!,
                          fit: BoxFit.contain,
                          width: double.infinity,
                        ),
                      )
                    : InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isPicking ? null : _pickFromGallery,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isPicking)
                                const CircularProgressIndicator(
                                  color: AppColors.accentText,
                                )
                              else ...[
                                const Icon(
                                  Icons.add_photo_alternate,
                                  size: 48,
                                  color: AppColors.accentText,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '탭하여 갤러리에서 명함 사진 선택',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
              ),
            ),

            if (_pickedImageBytes != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isPicking ? null : _pickFromGallery,
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: AppColors.accentText,
                  ),
                  label: const Text(
                    '다른 이미지 선택',
                    style: TextStyle(color: AppColors.accentText),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                    (_pickedImage == null ||
                        _isProcessing ||
                        !OcrScannerService.isSupportedOnThisPlatform)
                    ? null
                    : _processSelectedImage,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.document_scanner, color: Colors.white),
                label: Text(
                  _isProcessing ? '선택한 이미지 OCR 스캔 중...' : '선택한 파일 명함 OCR 스캔 실행',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
