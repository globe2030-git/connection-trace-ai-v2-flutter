import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

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
  final String? imagePath;

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
    this.imagePath,
  });
}

class OcrScannerService {
  static final ImagePicker _picker = ImagePicker();

  /// Google ML Kit은 온디바이스 전용 SDK라 웹(브라우저)에서는 아예 실행할 수
  /// 없다 — 화면단에서 이 값을 보고 시도하기 전에 안내를 보여주는 데 쓴다.
  static bool get isSupportedOnThisPlatform => !kIsWeb;

  /// 실제 카메라(네이티브 카메라 앱) 또는 갤러리에서 이미지를 고른다.
  /// 사용자가 취소하면 null.
  static Future<XFile?> pickImage({required bool fromCamera}) {
    return _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // 명함은 상대방에게 받아서 촬영하는 물건이라 후면 카메라가 기본이어야
      // 함(전면 카메라는 셀카용). image_picker 자체 기본값도 rear이긴 하지만,
      // 명시적으로 지정해서 의도를 분명히 하고 혹시 모를 플랫폼별 예외를 막는다.
      preferredCameraDevice: CameraDevice.rear,
      // OCR 인식률은 원본 해상도/압축 손실에 크게 좌우된다(명함 글자가 작아서
      // 저해상도·저품질이면 특히 취약함) — maxWidth를 두지 않아 카메라 원본
      // 해상도를 그대로 쓰고, JPEG 압축 손실도 최소화한다.
      imageQuality: 100,
    );
  }

  /// 실제로 캡처/선택된 명함 이미지에서 ML Kit 온디바이스 텍스트 인식으로 텍스트를
  /// 추출하고, 정규식 기반 휴리스틱으로 이름/전화/이메일/주소 등 필드를 채운다.
  /// 명함 레이아웃은 회사마다 제각각이라(이름이 위/아래, 회사명이 크게/작게 등)
  /// 전용 명함 파싱 모델 없이는 완벽한 필드 분류가 불가능하다 — 전화번호·이메일·
  /// 주소처럼 형식이 명확한 항목은 정확히 뽑고, 이름/회사/직함은 "가장 그럴듯한
  /// 남은 줄" 수준의 합리적 근사치로 채운 뒤 사용자가 폼에서 직접 수정하는 것을
  /// 전제로 한다.
  static Future<OcrScanResult> scanBusinessCard(XFile imageFile) async {
    if (kIsWeb) {
      throw UnsupportedError('OCR 명함 인식은 현재 모바일(Android/iOS) 기기에서만 지원됩니다.');
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognizedText = await recognizer.processImage(inputImage);
      return _parse(recognizedText.text, imageFile.path);
    } finally {
      await recognizer.close();
    }
  }

  static OcrScanResult _parse(String rawText, String imagePath) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final emailRegExp = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    final mobileRegExp = RegExp(r'01[0-9][-.\s]?\d{3,4}[-.\s]?\d{4}');
    final officeRegExp = RegExp(r'0(2|[3-6][0-9])[-.\s]?\d{3,4}[-.\s]?\d{4}');
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

    final name = remaining.isNotEmpty ? remaining.removeAt(0) : '';
    final company = remaining.isNotEmpty ? remaining.removeAt(0) : '';
    final title = remaining.isNotEmpty ? remaining.removeAt(0) : '';

    return OcrScanResult(
      rawText: rawText.isEmpty ? '[텍스트를 인식하지 못했습니다]' : rawText,
      name: name,
      company: company,
      title: title,
      phone: mobile ?? office ?? '',
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
