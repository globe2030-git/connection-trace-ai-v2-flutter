import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';

class FilePickerModalView extends StatefulWidget {
  const FilePickerModalView({super.key});

  @override
  State<FilePickerModalView> createState() => _FilePickerModalViewState();
}

class _FilePickerModalViewState extends State<FilePickerModalView> {
  int _selectedImageIndex = 0;
  bool _isProcessing = false;

  final List<Map<String, String>> _sampleDeviceImages = const [
    {
      'title': '명함_촬영본_김민준_테크노바.jpg',
      'size': '1.4 MB · 2026.07.31',
      'url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
    },
    {
      'title': '명함_스캔_한소율_바이오넥스트.png',
      'size': '2.1 MB · 2026.07.30',
      'url': 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=300',
    },
    {
      'title': '스타트업랩_박지훈_명함.png',
      'size': '980 KB · 2026.07.28',
      'url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300',
    },
  ];

  Future<void> _processSelectedImage() async {
    setState(() {
      _isProcessing = true;
    });

    final result = await OcrScannerService.scanBusinessCard(isFromCamera: false);

    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final currentImage = _sampleDeviceImages[_selectedImageIndex];

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
                    Icon(Icons.folder_open, color: AppColors.accentLime, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '기기 갤러리 / 이미지 파일 탐색기',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),

            const SizedBox(height: 14),

            // Image File Explorer Grid Picker
            const Text(
              '📁 스캔할 명함 이미지 선택',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),

            Row(
              children: List.generate(_sampleDeviceImages.length, (idx) {
                final isSelected = idx == _selectedImageIndex;
                final img = _sampleDeviceImages[idx];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedImageIndex = idx),
                    child: Container(
                      margin: EdgeInsets.only(right: idx < _sampleDeviceImages.length - 1 ? 8 : 0),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.bgDarkSlate,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.accentLime : AppColors.borderDark,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(img['url']!, height: 70, width: double.infinity, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            img['title']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.accentLime : AppColors.textPrimary,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 18),

            // Preview Selected Card Image Banner
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderDark),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(currentImage['url']!, fit: BoxFit.cover, width: double.infinity),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            currentImage['title']!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          currentImage['size']!,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _processSelectedImage,
                icon: _isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner, color: Colors.white),
                label: Text(
                  _isProcessing ? '선택한 이미지 OCR 스캔 중...' : '선택한 이미지 명함 스캔 실행',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentLime,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
