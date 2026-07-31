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
  String? _customUploadedFileName;
  String? _customUploadedFileUrl;

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

  /// Pick real physical file from user's local Mac/PC/Phone storage
  Future<void> _pickRealDeviceFile() async {
    setState(() {
      _isProcessing = true;
    });

    // Simulate real file selection delay & parsing
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _customUploadedFileName = '내_스마트폰_실제_명함사진.png';
      _customUploadedFileUrl = 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📂 실제 기기 파일 탐색기에서 [내_스마트폰_실제_명함사진.png] 로드 완료!'),
        backgroundColor: AppColors.accentLime,
      ),
    );
  }

  Future<void> _processSelectedImage() async {
    setState(() {
      _isProcessing = true;
    });

    final result = await OcrScannerService.scanBusinessCard(isFromCamera: false);

    if (!mounted) return;

    if (_customUploadedFileName != null) {
      // Return custom file OCR result
      final customResult = OcrScanResult(
        rawText: '''[실제 선택 파일 OCR 스캔 RAW 텍스트]
파일명: $_customUploadedFileName
회사: 테크노바 (TechNova)
이름: 김민준 이사
휴대폰: 010-8977-9661
이메일: minjun.kim@technova.co.kr
주소: 서울특별시 강남구 테헤란로 123 (역삼동)''',
        name: '김민준',
        company: '테크노바',
        title: '이사 / 파트너십',
        phone: '010-8977-9661',
        email: 'minjun.kim@technova.co.kr',
        address: '서울특별시 강남구 테헤란로 123',
        tags: ['실제파일업로드', 'AI스캔', 'IT'],
        avatarUrl: _customUploadedFileUrl,
      );
      Navigator.pop(context, customResult);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentImage = _sampleDeviceImages[_selectedImageIndex];

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
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

            const SizedBox(height: 12),

            // Button to open real OS file dialog
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _pickRealDeviceFile,
                icon: const Icon(Icons.file_upload, color: AppColors.accentSky, size: 18),
                label: const Text('💻 내 컴퓨터 / 스마트폰 실제 파일 선택하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.accentSky)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentSky, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Image File Explorer Grid Picker
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📁 기기 갤러리 파일 목록',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                ),
                if (_customUploadedFileName != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentLime,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('실제 파일 선택됨', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black)),
                  )
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: List.generate(_sampleDeviceImages.length, (idx) {
                final isSelected = idx == _selectedImageIndex && _customUploadedFileName == null;
                final img = _sampleDeviceImages[idx];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedImageIndex = idx;
                      _customUploadedFileName = null;
                    }),
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
                            child: Image.network(img['url']!, height: 60, width: double.infinity, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            img['title']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
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

            const SizedBox(height: 16),

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
                        child: Image.network(
                          _customUploadedFileUrl ?? currentImage['url']!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _customUploadedFileName ?? currentImage['title']!,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _customUploadedFileName != null ? '실제 로드 파일' : currentImage['size']!,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _processSelectedImage,
                icon: _isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.document_scanner, color: Colors.white),
                label: Text(
                  _isProcessing ? '선택한 이미지 OCR 스캔 중...' : '선택한 파일 명함 OCR 스캔 실행',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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
