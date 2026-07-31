import 'dart:math';

class OcrScanResult {
  final String rawText;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String email;
  final String address;
  final List<String> tags;
  final String? avatarUrl;

  const OcrScanResult({
    required this.rawText,
    required this.name,
    required this.company,
    required this.title,
    required this.phone,
    required this.email,
    required this.address,
    required this.tags,
    this.avatarUrl,
  });
}

class OcrScannerService {
  static final List<OcrScanResult> _mockOcrCardTemplates = [
    const OcrScanResult(
      rawText: '''[스캔 텍스트 RAW]
테크노바 (TechNova Corp)
이사 김민준 (Minjun Kim)
Mobile: 010-8977-9661
Email: minjun.kim@technova.co.kr
Office: 02-555-1234
Address: 서울특별시 강남구 테헤란로 123
Tag: #AI #클라우드 #IT''',
      name: '김민준',
      company: '테크노바',
      title: '이사 / 파트너십',
      phone: '010-8977-9661',
      email: 'minjun.kim@technova.co.kr',
      address: '서울특별시 강남구 테헤란로 123',
      tags: ['AI', '클라우드', 'IT'],
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
    ),
    const OcrScanResult(
      rawText: '''[스캔 텍스트 RAW]
바이오넥스트 (BioNext Inc)
팀장 한소율 (Soyul Han)
Phone: 010-3456-7890
Office: 02-345-6789
Email: soyul.han@bionext.co.kr
Address: 서울특별시 서초구 반포대로 45
Tag: #바이오 #R&D #신약''',
      name: '한소율',
      company: '바이오넥스트',
      title: '팀장 / R&D 파트너십',
      phone: '010-3456-7890',
      email: 'soyul.han@bionext.co.kr',
      address: '서울특별시 서초구 반포대로 45',
      tags: ['바이오', 'R&D', '신약'],
      avatarUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
    ),
    const OcrScanResult(
      rawText: '''[스캔 텍스트 RAW - 주소 미확인 예시]
스타트업랩 (Startup Lab)
대표 박지훈 (Jihun Park)
Tel: 010-9988-1122
Email: jihun@startuplab.io
Address: 역삼동 빌딩 3층 (상세주소 확인 필요)
Tag: #벤처 #투자 #스캔완료''',
      name: '박지훈',
      company: '스타트업랩',
      title: '대표이사 / CEO',
      phone: '010-9988-1122',
      email: 'jihun@startuplab.io',
      address: '역삼동 빌딩 3층',
      tags: ['벤처', '투자', '스캔완료'],
      avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
    ),
  ];

  /// Simulate AI OCR Business Card scanning from Camera or Image Upload
  static Future<OcrScanResult> scanBusinessCard({required bool isFromCamera}) async {
    // Simulate OCR Processing delay
    await Future.delayed(const Duration(milliseconds: 1200));

    final random = Random();
    final template = _mockOcrCardTemplates[random.nextInt(_mockOcrCardTemplates.length)];

    return template;
  }
}
