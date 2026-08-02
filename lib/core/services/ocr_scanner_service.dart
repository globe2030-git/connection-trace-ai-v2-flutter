import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrScanResult {
  final String rawText;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String officePhone;
  final String email;
  final String address;
  final List<String> tags;
  final String? avatarUrl;
  final String? imagePath;

  const OcrScanResult({
    required this.rawText,
    required this.name,
    required this.company,
    required this.title,
    required this.phone,
    required this.officePhone,
    required this.email,
    required this.address,
    required this.tags,
    this.avatarUrl,
    this.imagePath,
  });
}

class OcrScannerService {
  static final ImagePicker _picker = ImagePicker();

  /// Google ML Kit은 온디바이스 전용 SDK라 웹(브라우저)에서는 아예 실행할 수
  /// 없다 — 화면단에서 이 값을 보고 시도하기 전에 안내를 보여주는 데 쓴다.
  static bool get isSupportedOnThisPlatform => !kIsWeb;

  /// 갤러리에서 명함 이미지를 고른다. 사용자가 취소하면 null.
  /// (카메라 촬영은 실시간 프리뷰/후면 렌즈 제어가 필요해 camera 패키지로
  /// CameraScanModalView에서 직접 처리하고, 여기서는 갤러리 선택만 담당한다.)
  static Future<XFile?> pickImageFromGallery() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      // OCR 인식률은 원본 해상도/압축 손실에 크게 좌우된다(명함 글자가 작아서
      // 저해상도·저품질이면 특히 취약함) — maxWidth를 두지 않아 원본 해상도를
      // 그대로 쓰고, JPEG 압축 손실도 최소화한다.
      imageQuality: 100,
    );
  }

  /// 실제로 캡처/선택된 명함 이미지에서 ML Kit 온디바이스 텍스트 인식으로 텍스트를
  /// 추출하고, 위치 기반 재정렬 + 키워드 휴리스틱으로 이름/전화/이메일/주소 등
  /// 필드를 채운다. 명함 레이아웃은 회사마다 제각각이라(2단 레이아웃, 이름이
  /// 위/아래 등) 전용 명함 파싱 모델 없이는 완벽한 필드 분류가 불가능하다 —
  /// 전화번호·이메일·주소처럼 형식이 명확한 항목은 정확히 뽑고, 이름/회사/직함은
  /// 직함·회사 키워드로 우선 매칭한 뒤 남은 줄은 순서 기반으로 채워 사용자가
  /// 폼에서 직접 수정하는 것을 전제로 한다.
  static Future<OcrScanResult> scanBusinessCard(XFile imageFile) async {
    if (kIsWeb) {
      throw UnsupportedError('OCR 명함 인식은 현재 모바일(Android/iOS) 기기에서만 지원됩니다.');
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognizedText = await recognizer.processImage(inputImage);
      final orderedLines = _extractOrderedLines(recognizedText);
      return _parse(orderedLines, imageFile.path);
    } finally {
      await recognizer.close();
    }
  }

  /// ML Kit이 반환하는 `RecognizedText.text`는 내부 휴리스틱으로 줄 순서를
  /// 정하는데, 명함처럼 로고/QR과 텍스트가 좌우로 나뉜 2단 레이아웃에서는 이
  /// 순서가 뒤섞이기 쉽다(왼쪽 단 중간 줄 다음에 오른쪽 단 줄이 끼어드는 식).
  /// 각 줄의 실제 화면 좌표(boundingBox)를 기준으로 위→아래, 같은 줄 안에서는
  /// 왼→오 순으로 다시 정렬해 실제 명함을 읽는 순서에 가깝게 재구성한다.
  static List<String> _extractOrderedLines(RecognizedText recognizedText) {
    final allLines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.isEmpty) return [];

    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final avgHeight = allLines.map((l) => l.boundingBox.height).reduce((a, b) => a + b) / allLines.length;
    final rowTolerance = avgHeight * 0.6;

    final rows = <List<TextLine>>[];
    for (final line in allLines) {
      if (rows.isNotEmpty) {
        final rowTop = rows.last.map((l) => l.boundingBox.top).reduce((a, b) => a < b ? a : b);
        if ((line.boundingBox.top - rowTop).abs() <= rowTolerance) {
          rows.last.add(line);
          continue;
        }
      }
      rows.add([line]);
    }

    return rows.map((row) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      return row.map((l) => l.text.trim()).where((t) => t.isNotEmpty).join(' ');
    }).where((l) => l.isNotEmpty).toList();
  }

  static const _titleKeywords = [
    '대표이사', '대표', '이사', '상무', '전무', '부사장', '부장', '차장', '과장',
    '대리', '사원', '팀장', '실장', '본부장', '지점장', '원장', '소장', '매니저',
    '연구원', '교수', 'CEO', 'CTO', 'CFO', 'COO', 'President', 'Director',
    'Manager', 'Founder', 'VP', 'Lead',
  ];

  static const _companyKeywords = [
    '주식회사', '(주)', '㈜', 'Corp', 'Corporation', 'Inc.', 'Inc', 'Co.,',
    'Co.', 'Ltd', '그룹', 'Group', '컴퍼니', 'Company',
  ];

  static final _koreanNameRegExp = RegExp(r'^[가-힣]{2,4}$');

  static OcrScanResult _parse(List<String> lines, String imagePath) {
    final emailRegExp = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final mobileRegExp = RegExp(r'01[0-9][-.\s]?\d{3,4}[-.\s]?\d{4}');
    // 02(서울)/031~069(지역 국번) 외에 070(인터넷전화)도 요즘 명함에 흔히
    // 쓰이는데 빠져 있었음 — 회사 전화번호가 있어도 인식이 안 되는 원인이었음.
    final officeRegExp = RegExp(r'0(2|[3-6][0-9]|70)[-.\s]?\d{3,4}[-.\s]?\d{4}');
    final addressRegExp = RegExp(
      r'(서울|경기|인천|부산|대구|광주|대전|울산|세종|강원|충북|충남|전북|전남|경북|경남|제주)[^\n]*(로|길|동|구)[^\n]*',
    );

    String? mobile;
    String? office;
    String? email;
    String? address;
    final remaining = <String>[];

    for (final line in lines) {
      final emailMatch = emailRegExp.firstMatch(line);
      if (email == null && emailMatch != null) {
        email = emailMatch.group(0);
        continue;
      }
      final mobileMatch = mobileRegExp.firstMatch(line);
      if (mobile == null && mobileMatch != null) {
        mobile = _normalizePhone(mobileMatch.group(0)!);
        continue;
      }
      final officeMatch = officeRegExp.firstMatch(line);
      if (office == null && officeMatch != null) {
        office = _normalizePhone(officeMatch.group(0)!);
        continue;
      }
      final addressMatch = addressRegExp.firstMatch(line);
      if (address == null && addressMatch != null) {
        address = addressMatch.group(0)?.trim();
        continue;
      }
      remaining.add(line);
    }

    // 직함/회사 키워드로 먼저 매칭하고, 순수 한글 2~4자 줄은 이름 후보로 잡는다.
    // 셋 다 못 찾은 나머지는 예전처럼 "남은 줄 중 앞에서부터" 순서로 채운다.
    String? titleLine;
    String? companyLine;
    String? nameLine;
    final leftover = <String>[];

    for (final line in remaining) {
      if (titleLine == null && _titleKeywords.any((k) => line.contains(k))) {
        titleLine = line;
        continue;
      }
      if (companyLine == null && _companyKeywords.any((k) => line.contains(k))) {
        companyLine = line;
        continue;
      }
      if (nameLine == null && _koreanNameRegExp.hasMatch(line)) {
        nameLine = line;
        continue;
      }
      leftover.add(line);
    }

    final name = nameLine ?? (leftover.isNotEmpty ? leftover.removeAt(0) : '');
    final company = companyLine ?? (leftover.isNotEmpty ? leftover.removeAt(0) : '');
    final title = titleLine ?? (leftover.isNotEmpty ? leftover.removeAt(0) : '');

    final rawText = lines.join('\n');

    return OcrScanResult(
      rawText: rawText.isEmpty ? '[텍스트를 인식하지 못했습니다]' : rawText,
      name: name,
      company: company,
      title: title,
      phone: mobile ?? '',
      officePhone: office ?? '',
      email: email ?? '',
      address: address ?? '',
      tags: const [],
      avatarUrl: null,
      imagePath: imagePath,
    );
  }

  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return raw;
  }
}
