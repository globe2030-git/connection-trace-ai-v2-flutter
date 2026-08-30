import 'package:flutter/foundation.dart';

import '../utils/ocr_measure_dump.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// OCR이 읽은 **한 줄과 그 줄이 명함 위 어디에 있었는지.**
///
/// ## 왜 좌표를 들고 다니나 (R-05)
///
/// 지금 파서는 **글자 내용**으로 칸을 정한다(`(주)`가 붙었으면 회사 …).
/// 그런데 103장 실측에서 **회사 오류 39건 중 26건이 "OCR은 읽었는데 파서가
/// 못 고른 것"**이었다. 사람은 내용이 아니라 **위치와 크기**로 안다 — 위쪽
/// 큰 글씨는 회사, 가운데 제일 큰 글씨는 이름, 아래 작은 글씨는 주소다.
///
/// 그 판단을 하려면 좌표가 파서까지 와야 하는데, 예전에는
/// `({String text, double height})`만 넘겨 **높이 말고는 다 버렸다.**
///
/// ⚠️ **이 타입을 넓혔다고 파서가 좌표를 쓰기 시작하는 것은 아니다.** 지금은
/// **실어 나르기만** 한다. 분류에 쓰는 것은 다음 단계이고, 그전에 **좌표가
/// 담긴 스캔 결과로 기준선을 다시 재야** 한다(추가 317).
typedef OcrLineBox = ({
  String text,

  /// 글자 높이. 이름 판정의 폴백 근거로 이미 쓰고 있다.
  double height,

  /// 줄의 위쪽 y좌표(픽셀). 위일수록 작다.
  double top,

  /// 줄의 왼쪽 x좌표(픽셀).
  double left,

  /// 줄의 가로 폭(픽셀).
  double width,
});

/// 좌표를 모르는 자리에서 줄을 만든다(테스트 통로·폴백).
///
/// ⚠️ 0을 "왼쪽 맨 위"로 읽으면 안 된다. **모른다는 뜻**이다 — 좌표를 쓰는
/// 쪽은 값이 전부 0인 목록을 만나면 좌표 판단을 건너뛰어야 한다.
OcrLineBox lineBoxOf(String text, {double height = 0}) =>
    (text: text, height: height, top: 0, left: 0, width: 0);

/// 명함에서 이름을 "어떤 경로로" 뽑았는지. 값(이름 자체)이 아니라 방법만
/// 남긴다 — 약한 폴백(leftoverFallback)의 비율이 높으면 그만큼 파서가
/// 확신 없이 찍고 있다는 뜻이라, 인식 품질 측정의 핵심 신호다.
enum OcrNameSource {
  /// 직함 키워드가 걸린 줄에서 이름을 함께 분리("실장 곽용환").
  keywordSplit,

  /// 순수 한글 2~4자 줄(공백 제거 포함, "최 태 웅").
  koreanStripped,

  /// 한글+영문 혼용 줄의 앞쪽 한글 토큰("이정현 DA Sovargen").
  mixedTokenFront,

  /// 한글+영문 혼용 줄의 마지막 토큰이 이름 모양.
  mixedTokenLast,

  /// 위 규칙이 모두 실패해 남은 줄 맨 앞을 그냥 이름으로 씀(가장 약함).
  leftoverFallback,

  /// 규칙으로 이름을 확신하지 못했지만, 남은 줄 중 **가장 크게 인쇄된 줄**을
  /// 이름으로 골랐다(글자 크기 폴백). leftoverFallback("맨 앞 줄")을 대체하는
  /// 개선 경로 — 명함에서 이름이 대개 가장 큰 글자라는 점을 이용한다.
  fontSizePreferred,

  /// 같은 줄의 **로마자가 그 한글 성씨의 표기**와 맞아 확정한 경우
  /// (`이선경 Sun-Kyoung Lee`, 추가 429).
  romanizedSurname,

  /// **빈자리 재검증**에서 건짐 — 주소와 한 줄로 뭉쳐 나온 이름
  /// ("박병훈 서울특별시 은평구 통일로 65길 26, 7층"). 1차 배정에서 이름 칸이
  /// 빈 경우에만 시도한다.
  mergedWithAddress,

  /// **빈자리 재검증**에서 건짐 — 직함 칸에 섞여 들어간 이름을 떼어냄
  /// ("김효성 연구소장 GIT" → 이름 김효성 / 직함 연구소장 GIT).
  splitFromTitle,

  /// 확신 경로가 실패했을 때, 짧은 영문 조각보다 **한글 이름 토큰을 먼저**
  /// 골랐다("한글이름 옆이나 아래 영문이름이 있는 경우").
  hangulTokenPreferred,

  /// **빈자리 재검증**의 마지막 단계 — 원문 줄 전체를 다시 훑어 건짐.
  rawLineRecheck,

  /// 이름을 전혀 못 뽑음.
  none,
}

/// 회사명을 어떤 경로로 뽑았는지.
enum OcrCompanySource {
  /// 회사 접미사 키워드가 걸림("(주)", "Inc." 등).
  keyword,

  /// 키워드가 없어 남은 줄 중에서 골라냄(부서명/슬로건/로고 잡음 회피).
  leftoverPick,

  /// 회사명을 못 뽑음.
  none,
}

/// 명함 파싱이 "어떻게" 됐는지에 대한 형태 정보 — **내용(이름/전화/이메일/
/// 주소 원문)은 담지 않는다.** 개인정보를 남기지 않으면서 인식 품질을
/// 측정하기 위한 신호다.
///
/// 왜 이렇게 하나: 이 앱은 제3자(명함 주인)의 개인정보를 다루므로, 인식
/// 품질을 개선하려고 원문을 로그·집계에 남기면 그 자체가 유출 경로가 된다
/// (backlog 추가 72에서 평문 노출을 이미 겪었다). 그래서 "채워졌는가/어떤
/// 규칙으로 뽑았는가/줄이 몇 개인가"처럼 값이 없는 형태만 남긴다. 지오코딩
/// 실패 형태 로깅과 같은 원칙이다.
class OcrParseShape {
  /// 위치 재정렬 후 줄 수(내용 아님).
  final int lineCount;

  /// 인식된 전체 텍스트 길이(내용 아님 — "얼마나 읽혔나"의 대략치).
  final int rawLength;

  final bool nameFilled;
  final bool companyFilled;
  final bool titleFilled;
  final bool mobileFilled;
  final bool officeFilled;
  final bool emailFilled;
  final bool addressFilled;
  final bool addressDetailFilled;
  final bool postalFilled;

  final OcrNameSource nameSource;
  final OcrCompanySource companySource;

  const OcrParseShape({
    required this.lineCount,
    required this.rawLength,
    required this.nameFilled,
    required this.companyFilled,
    required this.titleFilled,
    required this.mobileFilled,
    required this.officeFilled,
    required this.emailFilled,
    required this.addressFilled,
    required this.addressDetailFilled,
    required this.postalFilled,
    required this.nameSource,
    required this.companySource,
  });
}

class OcrScanResult {
  final String rawText;
  final String name;
  final String company;
  final String title;
  // 부서 — 직함과 별개 칸이다(2026-08-19 사용자 확정, 추가 321).
  //
  // ⚠️ **새로 찾아 나서지 않는다.** 부서를 명함 전체에서 따로 찾으려 하면
  // 회사명 자리를 뺏는다 — 이 파일이 이미 겪은 자리다(`Global Sales Division`,
  // :483 주석). 대신 **직함 칸에 섞여 들어온 부서 토큰만 떼어낸다.** 이름을
  // 직함에서 떼어내는 기존 처리와 같은 모양이고, 같은 자리에서 돈다.
  final String department;
  final String phone;
  final String officePhone;
  // 팩스 번호. 파서는 예전에도 팩스 줄을 **알아보기는** 했지만, 사무실 전화로
  // 잘못 들어가는 것을 막으려고 **버리기만** 했다. 그래서 명함 데이터에는
  // 팩스 칸이 있는데도(ContactModel.fax) 촬영으로는 **절대 채워지지 않았다**
  // — 손으로 입력할 때만 채워졌다. 이제 알아본 값을 여기에 담는다.
  final String fax;
  final String email;
  // 홈페이지. 예전에는 직함 칸을 더럽히지 않으려고 **걷어내 버렸다**
  // (`www.edenpat.com 파트너 변리사`처럼 한 줄로 붙어 읽히는 명함이 흔하다).
  // 버리는 대신 이 칸으로 보낸다.
  final String website;
  final String address;
  // 층/호수/동 같은 상세주소 — 명함에서 기본 주소와 다른 줄에 따로 인식되는
  // 경우가 많아서(addressRegExp가 한 줄 단위로만 매칭됨) 별도 필드로 분리해
  // 잡아낸다. 안 잡히면 빈 문자열.
  final String addressDetail;
  // 우편번호(5자리) — 주소 줄 앞에 "06193 서울특별시..."처럼 붙어 있는
  // 경우가 흔해서 별도로 뽑아낸다. 안 잡히면 빈 문자열.
  final String postalCode;
  final List<String> tags;
  final String? avatarUrl;
  final String? imagePath;

  /// 스캔된 원문 줄 목록 (터치 퀵 매핑 UI 지원용)
  final List<String> rawLines;

  /// [rawLines]와 **같은 순서**로, 각 줄이 명함 위 어디에 있었는지(R-05).
  ///
  /// ⚠️ **비어 있을 수 있다.** 테스트 통로나 좌표를 모르는 경로로 만든
  /// 결과에는 안 담긴다. 쓰는 쪽은 길이가 [rawLines]와 같은지 먼저 본다 —
  /// 다르면 좌표 판단을 건너뛴다.
  ///
  /// 왜 남기나: 파서를 고쳐도 **다시 재려면 스캔을 다시 돌려야** 하는데,
  /// 좌표가 결과에 안 남으면 재스캔을 해도 좌표 규칙을 검증할 수 없다.
  /// 일괄 스캔 TSV가 이 값을 함께 내보낸다(추가 317).
  final List<OcrLineBox> rawLineBoxes;

  /// 이 결과가 "어떻게" 만들어졌는지에 대한 형태 정보(내용 없음). 인식 품질
  /// 측정용이라 앱 화면에는 안 쓴다. 테스트에서 만든 결과 등에는 없을 수 있어
  /// nullable.
  final OcrParseShape? parseShape;

  const OcrScanResult({
    required this.rawText,
    this.rawLines = const [],
    this.rawLineBoxes = const [],
    required this.name,
    required this.company,
    required this.title,
    // ⚠️ 기본값을 둔다 — 나중에 추가된 칸이라 이미 있는 호출부·검사 코드가
    // 통째로 깨지지 않게 한다(위 fax·directPhone과 같은 이유).
    this.department = '',
    required this.phone,
    required this.officePhone,
    // ⚠️ 기본값을 둔다 — 이 두 칸은 나중에 추가된 것이라, 이미 있는 호출부와
    // 검사 코드가 통째로 깨지지 않게 한다.
    this.fax = '',
    required this.email,
    this.website = '',
    required this.address,
    this.addressDetail = '',
    this.postalCode = '',
    required this.tags,
    this.avatarUrl,
    this.imagePath,
    this.parseShape,
  });

  /// **이메일만** 갈아 끼운 사본. 라틴 2차 패스가 쓴다(추가 336).
  ///
  /// ⚠️ 일반 `copyWith`를 만들지 않은 것은 일부러다. 칸이 열일곱인데 통째로
  /// 여는 문을 내면 *"여기서 한 칸만 바꾸자"*가 늘고, 그러면 파싱 결과가
  /// 어디서 바뀌었는지 좇기 어려워진다. **바꿔도 되는 자리를 하나로 좁힌다.**
  OcrScanResult withEmail(String value) => OcrScanResult(
    rawText: rawText,
    rawLines: rawLines,
    rawLineBoxes: rawLineBoxes,
    name: name,
    company: company,
    title: title,
    department: department,
    phone: phone,
    officePhone: officePhone,
    fax: fax,
    email: value,
    website: website,
    address: address,
    addressDetail: addressDetail,
    postalCode: postalCode,
    tags: tags,
    avatarUrl: avatarUrl,
    imagePath: imagePath,
    parseShape: parseShape,
  );
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

  /// 갤러리에서 명함 이미지를 **여러 장** 고른다(관리자 일괄 스캔용).
  ///
  /// 인식 규칙을 고칠 때마다 한 장씩 눈으로 확인하면 "전체적으로 좋아졌는지"를
  /// 알 수 없다 — 실제로 한 장을 고치면 다른 장이 깨지는 일이 반복됐다
  /// (backlog 추가 180). 여러 장을 한 번에 돌려 표로 보기 위한 진입점이다.
  ///
  /// `pickImage`와 같은 이유로 해상도·품질을 줄이지 않는다.
  static Future<List<XFile>> pickImagesFromGallery() {
    return _picker.pickMultiImage(imageQuality: 100);
  }

  /// 갤러리에서 **앞·뒷면 최대 2장**을 한 번에 고른다(P2-②).
  ///
  /// `image_picker` 플러그인 소스(`image_picker-1.2.3/lib/image_picker.dart`)를
  /// 실측한 결과: `pickMultiImage(limit: n)`은 `MultiImagePickerOptions`로
  /// 네이티브(iOS PHPicker·Android Photo Picker)에 상한을 넘겨 **그 이상은
  /// 아예 선택되지 않게 막는다** — 앱이 나중에 앞부분만 자르는 방식이 아니다.
  ///
  /// ⚠️ **반환 순서가 "탭한 순서"라는 보장은 플랫폼 문서 어디에도 없다.**
  /// iOS PHPicker는 통상 선택 순서를 유지하지만, 이 앱이 요청하는
  /// 구성(selectionLimit만 지정)에서 순서가 뒤집히는 사례가 보고돼 있고,
  /// Android 쪽 보장은 더 약하다. 그래서 이 함수의 반환값을 **"추정
  /// 앞/뒷면"으로만 쓰고**, 화면에는 반드시 "앞·뒷면 순서 바꾸기"를 함께
  /// 둔다 — 순서가 실제로 어긋나도 사용자가 바로잡을 수 있게.
  static Future<List<XFile>> pickUpToTwoImagesFromGallery() {
    return _picker.pickMultiImage(imageQuality: 100, limit: 2);
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
      // ML Kit이 예외 없이 끝없이 대기만 하는 경우가 있어(촬영 화면이
      // "AI 텍스트 추출 중..."에서 멈추는 문제로 실기기에서 확인됨) 타임아웃을
      // 걸어 일정 시간 안에 안 끝나면 실패로 처리한다.
      final recognizedText = await recognizer
          .processImage(inputImage)
          .timeout(const Duration(seconds: 20));
      var orderedLines = _extractOrderedLines(recognizedText);
      // 토큰 측정은 **줄을 뽑은 그 인식 결과**에서 나와야 한다. 아래 2차 풀
      // 스캔으로 갈아타면 이것도 같이 갈아탄다 — 안 그러면 줄과 토큰이 서로
      // 다른 스캔에서 온 값이 되어 대조가 조용히 어긋난다.
      var sourceText = recognizedText;

      // Dual-Pass OCR: 마진 크롭으로 텍스트가 극히 일부만 읽혔거나 잘린 경우
      // (인식된 총 길이 < 8), 원본 이미지 전체로 2차 풀 스캔을 시도한다.
      final totalLen = orderedLines.fold<int>(
        0,
        (sum, l) => sum + l.text.length,
      );
      if (totalLen < 8) {
        debugPrint('OCR 1차 크롭 결과 부족($totalLen자) -> 2차 풀 스캔 자동 실행');
        final rawInput = InputImage.fromFilePath(imageFile.path);
        final rawRecognized = await recognizer
            .processImage(rawInput)
            .timeout(const Duration(seconds: 15));
        final rawOrdered = _extractOrderedLines(rawRecognized);
        if (rawOrdered.fold<int>(0, (sum, l) => sum + l.text.length) >
            totalLen) {
          orderedLines = rawOrdered;
          sourceText = rawRecognized;
        }
      }

      var result = _parse(orderedLines, imageFile.path);

      // 측정 전용 기록(추가 405). 기본 빌드에서는 상수가 false라 이 블록이
      // 통째로 죽는다 — 릴리스에 영향이 없다.
      if (ocrMeasureDumpEnabled) {
        await appendMeasureRow(
          directory: await measureDumpDirectory(),
          row: formatMeasureRow(
            imageName: imageFile.name,
            lines: [
              for (final l in orderedLines) (text: l.text, height: l.height),
            ],
            nameSource: result.parseShape?.nameSource.name ?? '없음',
            parsedName: result.name.trim(),
            tokens: measureTokens(sourceText),
          ),
        );
      }

      // 이메일이 안 잡혔으면 **라틴 인식기로 한 번 더** 읽는다(추가 336).
      if (result.email.trim().isEmpty) {
        final retried = await _retryEmailWithLatin(imageFile);
        if (retried != null) result = result.withEmail(retried);
      }
      return result;
    } finally {
      await recognizer.close();
    }
  }

  /// 이메일만 **라틴 인식기로 다시 읽는다.**
  ///
  /// ## 왜 이것만 따로 (추가 336)
  ///
  /// 이메일 오류를 하나씩 열어 보니 **파서는 찾는 데 사실상 완벽했다** — 틀린
  /// 6건 중 못 고른 것과 조각만 맞은 것이 **0건**이었다. 남은 건 OCR이 글자를
  /// 잘못 읽은 것뿐이고, 이메일은 **전부 라틴 문자**라 한국어 모델이 불리하다.
  ///
  /// ```
  /// card_10  원문에 `@o…,kr`   ← 점을 쉼표로 읽었다
  /// ```
  ///
  /// 라틴 모델은 **두 플랫폼에 이미 들어 있다**(iOS는 Podfile의 전이 의존성,
  /// Android는 플러그인이 기본 포함). 새 팟도 새 gradle 의존성도 필요 없다.
  ///
  /// ## ⚠️ 비었을 때만 돈다
  ///
  /// 값이 이미 있으면 **손대지 않는다.** 라틴 결과가 달라도 **어느 쪽이 맞는지
  /// 가릴 근거가 없어서**, 채택하면 맞던 것을 망칠 수 있다. 실제로 `12…@` ↔
  /// `Yg…@`처럼 **정규식은 통과하는데 틀린** 장이 둘 있는데, 그 유형은 일부러
  /// 겨냥하지 않는다.
  ///
  /// 그래서 이 함수는 **잃을 것이 없다** — 원래 빈 칸에만 값을 넣는다.
  ///
  /// ## 실패는 조용히 넘어간다
  ///
  /// 2차 인식이 실패해도 1차 결과는 멀쩡하다. 여기서 예외를 올리면 **되던
  /// 스캔이 통째로 깨진다.**
  static Future<String?> _retryEmailWithLatin(XFile imageFile) async {
    final latin = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await latin
          .processImage(InputImage.fromFilePath(imageFile.path))
          .timeout(const Duration(seconds: 15));
      // 1차와 **같은 규칙**으로 본다 — 자가 다르면 비교가 안 된다.
      final re = RegExp(
        r'[a-zA-Z0-9._%+-]+\s*@\s*[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
      );
      for (final line in _extractOrderedLines(recognized)) {
        final m = re.firstMatch(line.text);
        if (m != null) {
          final raw = m.group(0)!.replaceAll(RegExp(r'\s+'), '');
          return _stripEmailLabelPrefix(raw);
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await latin.close();
    }
  }

  /// ML Kit이 반환하는 `RecognizedText.text`는 내부 휴리스틱으로 줄 순서를
  /// 정하는데, 명함처럼 로고/QR과 텍스트가 좌우로 나뉜 2단 레이아웃에서는 이
  /// 순서가 뒤섞이기 쉽다(왼쪽 단 중간 줄 다음에 오른쪽 단 줄이 끼어드는 식).
  /// 각 줄의 실제 화면 좌표(boundingBox)를 기준으로 위→아래, 같은 줄 안에서는
  /// 왼→오 순으로 다시 정렬해 실제 명함을 읽는 순서에 가깝게 재구성한다.
  /// **합치기 전의 낱말 상자**를 그대로 모은다 — 측정 전용(추가 409).
  ///
  /// `_extractOrderedLines`는 좌우로 나란한 줄을 한 행으로 합치고 **높이를
  /// 그중 가장 큰 것으로** 잡는다. 이름과 회사가 나란히 인쇄된 명함에서는
  /// 회사까지 이름만큼 큰 것으로 기록되므로, 글자 크기로 이름을 고르려면
  /// **합치기 전 값**이 있어야 한다.
  ///
  /// ⚠️ **파싱에는 쓰지 않는다.** 이 함수가 만든 값은 측정 파일로만 나간다.
  /// 규칙을 만들지 여부는 재고 나서 정한다.
  ///
  /// 순서는 위→아래, 같은 높이면 왼→오다. 대조하는 쪽이 행 묶음을 스스로
  /// 다시 만들고 **낱말 사이 틈까지 잴 수 있도록** 좌표와 너비를 같이 남긴다.
  @visibleForTesting
  static List<
    ({String text, double height, double top, double left, double width})
  >
  measureTokens(RecognizedText recognizedText) {
    final tokens =
        <
          ({
            String text,
            double height,
            double top,
            double left,
            double width,
          })
        >[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        for (final el in line.elements) {
          final text = el.text.trim();
          if (text.isEmpty) continue;
          tokens.add((
            text: text,
            height: el.boundingBox.height,
            top: el.boundingBox.top.toDouble(),
            left: el.boundingBox.left.toDouble(),
            // ⚠️ 너비가 있어야 **낱말 사이 틈**을 잴 수 있다(추가 412).
            // 틈 = 다음 낱말의 왼쪽 − (이 낱말의 왼쪽 + 너비). v2에는 이
            // 칸이 없어 자간 넓은 이름과 별개 낱말을 못 갈랐다(추가 411).
            width: el.boundingBox.width,
          ));
        }
      }
    }
    tokens.sort((a, b) {
      final byTop = a.top.compareTo(b.top);
      return byTop != 0 ? byTop : a.left.compareTo(b.left);
    });
    return tokens;
  }

  static List<OcrLineBox> _extractOrderedLines(RecognizedText recognizedText) {
    final allLines = <TextLine>[];
    for (final block in recognizedText.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.isEmpty) return [];

    allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    final avgHeight =
        allLines.map((l) => l.boundingBox.height).reduce((a, b) => a + b) /
        allLines.length;
    final rowTolerance = avgHeight * 0.6;

    final rows = <List<TextLine>>[];
    for (final line in allLines) {
      if (rows.isNotEmpty) {
        final rowTop = rows.last
            .map((l) => l.boundingBox.top)
            .reduce((a, b) => a < b ? a : b);
        if ((line.boundingBox.top - rowTop).abs() <= rowTolerance) {
          rows.last.add(line);
          continue;
        }
      }
      rows.add([line]);
    }

    // 각 줄의 텍스트와 함께 글자 높이(boundingBox.height)를 넘긴다 — 이름은
    // 명함에서 대개 가장 크게 인쇄되므로, 규칙으로 이름을 확신하지 못했을 때
    // 글자 크기를 폴백 근거로 쓴다(_parse). 한 행에 여러 줄이 좌우로 묶였으면
    // 그 행의 대표 높이는 가장 큰 글자로 잡는다.
    return rows
        .map((row) {
          row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
          final text = row
              .map((l) => l.text.trim())
              .where((t) => t.isNotEmpty)
              .join(' ');
          final height = row
              .map((l) => l.boundingBox.height)
              .reduce((a, b) => a > b ? a : b);
          // 한 행에 좌우로 여러 줄이 묶였으면 **행 전체를 감싸는 상자**를 준다.
          // 왼쪽 끝에서 오른쪽 끝까지가 그 행이 차지한 자리다.
          final top = row
              .map((l) => l.boundingBox.top.toDouble())
              .reduce((a, b) => a < b ? a : b);
          final left = row
              .map((l) => l.boundingBox.left.toDouble())
              .reduce((a, b) => a < b ? a : b);
          final right = row
              .map((l) => l.boundingBox.right.toDouble())
              .reduce((a, b) => a > b ? a : b);
          return (
            text: text,
            height: height,
            top: top,
            left: left,
            width: right - left,
          );
        })
        .where((l) => l.text.isNotEmpty)
        .toList();
  }

  static const _titleKeywords = [
    '대표이사',
    '대표',
    '이사',
    '상무',
    '전무',
    '부사장',
    '부장',
    '차장',
    '과장',
    '대리',
    '사원',
    '팀장',
    '실장',
    '본부장',
    '지점장',
    '원장',
    '소장',
    '매니저',
    '연구원',
    '교수',
    // 2026-08-07: 실제 명함 샘플(SK텔레콤/LG스포츠/장애인기업종합지원센터 등)
    // 로 확인된 직급 표현 — 대기업·공공기관에서 흔한데 기존 목록엔 없었다.
    '책임',
    '수석',
    '선임',
    '주임',
    '주무관',
    '사무관',
    '서기관',
    // 2026-08-11: 다양한 명함 대응 강화(무료 규칙). 뜻이 겹칠 여지가 적은
    // 직함만 보수적으로 추가한다 — 회사명/부서명과 헷갈릴 만한 일반 단어는
    // 넣지 않는다.
    '회장',
    '부회장',
    '이사장',
    '고문',
    '부문장',
    '센터장',
    'CEO',
    'CTO',
    'CFO',
    'COO',
    'President',
    'Director',
    'Manager',
    'Founder',
    'Co-Founder',
    'VP',
    'Lead',
    // 2026-08-13: 직함 확장. ⚠️ 이 목록은 `_containsCi`로 **부분 문자열**
    // 비교된다(단어 경계 없음). 그래서 두세 글자짜리 영문 약어는 넣으면
    // 안 된다 — 'PO'를 넣었더니 "NELSON SPORTS, INC."의 "S**PO**RTS"에
    // 걸려 회사명 줄이 통째로 직함이 됐다(직함이 먼저 검사되고 continue
    // 하므로 회사명은 빈 값이 된다). 같은 이유로 'PM'(PMP), 'Head'
    // (Headquarters)도 뺐다. 단어 하나로 자립하는 긴 표기만 남긴다.
    //
    // 🚨 **그런데 반대 방향으로도 물린다 — 목록이 아니라 「보는 쪽」이 문제다.**
    //    2026-08-29에 `ceonitios`(로고 오독) 안의 `CEO`에 걸려, 로고를 걸러
    //    내려던 규칙이 *"직함 낱말이 있다"*고 보고 **안 돌았다.**
    //    ⚠️ 이 함정은 **이 주석에 이미 적혀 있었는데 그 자리에서 다시 밟았다.**
    //    주석으로는 안 막힌다 — 그래서 잠근 검사 이름을 여기 적어 둔다.
    //
    //    잠근 검사: `test/device_reported_ocr_test.dart`
    //              「🚨 직함 키워드는 **낱말 경계**로 본다」
    //    경계가 필요한 자리에서는 `_containsCi` 대신 `_containsWordCi`를 쓴다.
    'Leader',
    'Tech Lead',
    'Design Lead',
    'Principal',
    'Fellow',
    'Senior',
    'Junior',
    'Consultant',
    '전문위원',
    '자문위원',
    '연구소장',
    '파트장',
    '셀장',
    '그룹장',
  ];

  /// 자격증·인증 표기. 이 표기가 있는 줄은 **직함으로 쓰지 않는다** — 자격증은
  /// 직함이 아니고, 별도 필드로 저장하지도 않기로 했다(사용자 결정 2026-08-13).
  /// 직함 칸이 자격증으로 채워지면 정작 직함이 들어갈 자리가 없어진다.
  ///
  /// 실제 명함 예: 직함 없이 "정보시스템수석감리원 / 정보시스템감리사 /
  /// PIMS 심사원"만 나열된 경우 — '수석'이 첫 줄에 걸려 직함이 됐다.
  ///
  /// ⚠️ 여기에도 짧은 약어는 넣지 않는다(`_containsCi`가 부분 문자열이다).
  /// '기사'는 "전기기사"(자격증)뿐 아니라 "운전기사"(직업)에도 걸리고,
  /// '노무사'·'세무사'·'회계사'는 **그 사람의 직함 자체**인 경우가 많아 뺐다.
  static const _qualificationMarkers = ['감리원', '감리사', '심사원', '기술사', '지도사'];

  /// **회사에만 붙는 표기.** `연구소`·`그룹`·`센터` 같은 약한 낱말과 달리
  /// 부서 이름에는 안 쓰인다.
  static final _strongCompanyMarker = RegExp(
    r'\(주\)|\(유\)|㈜|주\)|주식회사|유한회사|사단법인|재단법인|'
    r'(?<![A-Za-z])(Inc|Corp|Corporation|Ltd|LLC)(?![A-Za-z])',
    caseSensitive: false,
  );

  /// **시·도 이름이 진짜 주소의 시작인지.** 뒤에 공백·숫자·쉼표가 오거나
  /// `특별시`·`광역시`·`도`·`시`·`군`·`구` 가 붙는다. `서울관광재단` 의 `관` 은
  /// 그중 어느 것도 아니다.
  static final _realProvinceStart = RegExp(
    r'(서울|경기|인천|부산|대구|광주|대전|울산|세종|강원|충청북도|충청남도|'
    r'충북|충남|전라북도|전라남도|전북|전남|경상북도|경상남도|경북|경남|제주)'
    r'(?=[\s\d,]|특별시|광역시|특별자치시|특별자치도|도|시|군|구|$)',
  );

  /// 시·도 이름이 시작되는 자리 — 회사·부서 이름이 시·도 이름으로 시작할 때
  /// **뒤쪽의 진짜 주소부터 다시 맞춰 보려고** 쓴다.
  static final _provinceHead = RegExp(
    r'(서울|경기|인천|부산|대구|광주|대전|울산|세종|강원|충청북도|충청남도|'
    r'충북|충남|전라북도|전라남도|전북|전남|경상북도|경상남도|경북|경남|제주)',
  );

  static const _companyKeywords = [
    '주식회사',
    '(주)',
    // ⚠️ **OCR이 여는 괄호를 자주 놓친다**(2026-08-20 실측, 추가 340).
    // `주)드림시큐리티`가 회사 후보로 인식조차 안 돼, 회사 칸은 다음 줄
    // (`보안기술연구소`)을 집고 그 줄은 직함으로 갔다 — **한 장에서 오류가
    // 둘** 났다. 닫는 괄호만 남은 표기를 함께 본다.
    //
    // 여는 괄호가 없는 `주)`는 회사 표기 말고 쓰일 일이 사실상 없다.
    '주)',
    '재)',
    '㈜',
    'Corp',
    'Corporation',
    'Inc.',
    'Inc',
    'Co.,',
    'Co.',
    'Ltd',
    '그룹',
    'Group',
    '컴퍼니',
    'Company',
    // 2026-08-07: 실제 명함 샘플(장애인기업종합지원센터 등)로 확인된
    // 비영리·공공 법인 표기 — 영리법인 접미사 위주였던 목록에 추가.
    '(재)',
    '재단법인',
    '사단법인',
    '유한회사',
    '협동조합',
    // 2026-08-11: 공공기관 명함에서 흔한 기관 접미사 — 다른 단어와 겹칠
    // 여지가 거의 없는 것만 추가(공사/공단/진흥원). "연구원"은 직함 키워드와
    // 겹쳐서 넣지 않는다.
    '공사',
    '공단',
    '진흥원',
    // 🚨 **공공기관 이름 꼬리가 통째로 빠져 있었다**(2026-08-30, 190장 실측).
    //
    // `서울관광재단` 은 어느 키워드에도 안 걸려 **회사 후보로 검토조차 안 됐다.**
    // 그 결과 회사 칸이 **빈 채로** 나왔다 — 190장 중 회사를 못 찾은 17장에서
    // **일곱 장이 이 모양**이었고(서울관광재단 6 · 한국사회보장정보원 1),
    // 원문에는 이름이 **그대로 찍혀 있었다.**
    //
    // ⚠️ **낱말을 고를 때 「원」·「회」처럼 한 글자짜리는 넣지 않는다.** 부서
    //    이름(`기획조정실`)이나 직함(`위원`)에 걸린다. **두 글자 이상이면서
    //    기관 이름 끝에만 붙는 것**만 넣는다.
    '재단',
    '정보원',
    '연합회',
    '협회',
    '진흥회',
    '공제회',
    // 2026-08-13: 회사 접미사 확장. 위 "연구원을 넣지 않는다"와 같은 이유로,
    // 부분 문자열로 엉뚱하게 걸리는 단어는 뺐다 — 'AI'는 이메일 줄의
    // "e-m**ai**l"에, 'Tech'는 직함 "**Tech**nical Director"에, 'Lab'은
    // "Co**lab**oration"에 걸린다. 'Global'은 실제로 부서명 "Global Sales
    // Division"을 회사명 자리로 끌어와 테스트가 깨졌다(부서명이 회사명을
    // 뺏는 문제는 아래 _departmentSuffixes 주석의 실사용 버그와 같은 계열).
    // 한글 표기('테크'·'바이오'·'글로벌')는 겹칠 여지가 없어 그대로 둔다.
    // 2026-08-13: 회사명 줄이 직함 키워드를 품고 있어 통째로 직함이 되던
    // 사례를 막기 위해 함께 넣는다(위 직함 판정에서 회사 키워드가 걸린 줄은
    // 건너뛴다). '대리점'은 '대리'를, '사무소'는 앞에 붙는 말에 따라 '사원'
    // 등을 품는다 — 이 목록에 있으면 회사명 자리로 정확히 들어간다.
    '대리점',
    '사무소',
    '영업소',
    'Labs',
    'Studio',
    '스튜디오',
    '연구소',
    '센터',
    '홀딩스',
    'Holdings',
    'Ventures',
    '벤처스',
    'Partners',
    '파트너스',
    'Solution',
    'Solutions',
    '솔루션',
    '테크',
    'Systems',
    '시스템즈',
    'Bio',
    '바이오',
    '글로벌',
    // 2026-08-17: 103장 전수 측정에서 **회사 60%**로 가장 낮게 나왔고, 틀린
    // 39건 중 26건이 *"OCR은 제대로 읽었는데 파서가 못 고른 것"*이었다
    // (추가 280). 그중 한 덩어리가 **기관 접미사가 목록에 없어서** 생겼다.
    //
    // 접미사가 있으면 `_trimCompanyAroundKeyword`가 그 토큰만 남겨 준다 —
    // 슬로건이 뒤에 길게 붙은 줄에서 기관명만 뽑아낸다.
    //
    //   `SSiS 한국사회보장정보원 국민 맞춤형 복지를 실현하는 디지털 플랫폼 전문기관`
    //     → `한국사회보장정보원`
    //
    // ⚠️ 위 '연구원을 넣지 않는다'와 같은 기준으로 골랐다 — **다른 단어에
    // 부분 문자열로 걸릴 여지가 거의 없는 것만.** '원'·'회' 같은 한 글자나
    // '지원'(지원팀)처럼 흔한 조각은 넣지 않는다.
    '협회',
    '학회',
    '정보원',
  ];

  // 회사명에 위 키워드가 하나도 안 걸릴 때(예: "Sovargen", "SSiS
  // 한국사회보장정보원"처럼 접미사 없는 브랜드명/영문명) leftover 맨 앞
  // 줄을 무조건 회사명으로 쓰면, 부서명이나 슬로건 같은 줄이 대신 들어가는
  // 문제가 실제 명함 3장(이정현·최서연·이상헌, Sovargen/SSIS)에서
  // 확인됐다 — "경영기획실", "국민 맞춤형 복지를 실현하는..." 같은 줄이
  // 회사명 자리를 차지했다. 부서명 흔한 접미사로 끝나는 줄만 후순위로
  // 미룬다("팀"/"실"/"국"/"처" 같은 짧은 접미사는 정상적인 회사명 끝
  // 글자와도 우연히 겹칠 수 있어 긴 접미사부터 확인).
  /// 정부 부처 이름 — **부서 칸에 들어가면 안 된다**(2026-08-29, 실측).
  ///
  /// 명함에 인증·수상 배지로 찍혀 있다(`③산업통상자원부`,
  /// `G 중소벤처기업부`). 「…부」로 끝나 부서처럼 보이지만 그 사람의 소속이
  /// 아니다.
  static const _ministryNames = [
    '기획재정부', '교육부', '과학기술정보통신부', '외교부', '통일부',
    '법무부', '국방부', '행정안전부', '문화체육관광부', '농림축산식품부',
    '산업통상자원부', '보건복지부', '환경부', '고용노동부', '여성가족부',
    '국토교통부', '해양수산부', '중소벤처기업부',
  ];

  static const _departmentSuffixes = [
    '사업본부',
    '기획실',
    '관리부',
    '지원부',
    '지원실',
    '사업부',
    // 2026-08-19(추가 323): 실측에서 `DX사업본부 공공시스템/전략컨설팅부문`이
    // 회사 자리를 차지했다. 목록에 '부문'이 없어서 후순위로 안 밀렸다.
    '부문',
    '부서',
    '본부',
    '센터',
    '팀',
    '실',
    '국',
    '처',
  ];

  /// 흔한 성씨의 **로마자 표기**. 한 성씨를 여러 가지로 쓰기 때문에 목록이다
  /// (`이` → Lee·Yi·Rhee·Li).
  ///
  /// ⚠️ **표준이 없다.** 그래서 이 표만으로 판단하지 않는다 — 같은 줄에 **한글
  /// 이름 모양 낱말이 있을 때만** 본다. `Go`·`No`·`Won`·`Min`처럼 영어 단어와
  /// 겹치는 표기가 있어서, 그 조건이 없으면 엉뚱한 줄이 이름이 된다.
  ///
  /// ⚠️ **애매한 성씨는 넣지 않는다.** 넣어서 틀리는 것이 안 넣어서 못 얻는
  /// 것보다 나쁘다 — 이 저장소가 이름 규칙에서 여러 번 확인한 방향이다.
  static const _surnameRomanizations = <String, List<String>>{
    '김': ['kim', 'gim'], '이': ['lee', 'yi', 'rhee', 'li'],
    '박': ['park', 'bak', 'pak'], '최': ['choi', 'choe'],
    '정': ['jung', 'jeong', 'chung'], '강': ['kang', 'gang'],
    '조': ['cho', 'jo'], '윤': ['yoon', 'yun'], '장': ['jang', 'chang'],
    '임': ['lim', 'im'], '한': ['han'], '오': ['oh'],
    '서': ['seo', 'suh'], '신': ['shin'], '권': ['kwon'], '황': ['hwang'],
    '안': ['ahn'], '송': ['song'], '류': ['ryu', 'lyu'],
    '전': ['jeon', 'chun'], '홍': ['hong'], '고': ['ko', 'koh'],
    '문': ['moon', 'mun'], '양': ['yang'], '손': ['son', 'sohn'],
    '배': ['bae'], '백': ['baek', 'paek'], '허': ['heo', 'hur', 'huh'],
    '유': ['yoo', 'yu'], '남': ['nam'], '심': ['shim'], '노': ['noh', 'roh'],
    '하': ['ha'], '곽': ['kwak'], '성': ['sung', 'seong'], '차': ['cha'],
    '주': ['joo'], '우': ['woo'], '구': ['koo'], '민': ['min'],
    '표': ['pyo'], '방': ['bang'], '변': ['byun'], '함': ['ham'],
    '염': ['yeom'], '추': ['chu', 'choo'], '석': ['seok'], '설': ['seol'],
    '진': ['jin'], '지': ['jee'], '엄': ['eom'], '채': ['chae'],
    '현': ['hyun'], '금': ['keum'], '국': ['kook'],
  };

  static final _latinWordRegExp = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  static final _koreanNameRegExp = RegExp(r'^[가-힣]{2,4}$');
  static final _singleHangulRegExp = RegExp(r'^[가-힣]$');
  static final _hangulOnlyRegExp = RegExp(r'^[가-힣]+$');
  static final _whitespaceSplitRegExp = RegExp(r'[\s　]+');

  /// 사람 이름이 될 수 없는 끝맺음(조사·연결어미). 홍보 문구가 잘린 조각을
  /// 이름에서 걸러내는 데 쓴다.
  ///
  /// ⚠️ 실제 이름으로 쓰일 수 있는 말은 넣지 않는다 — 예를 들어 '이나'는
  /// "김이나"처럼 사람 이름에 실제로 쓰여서 뺐다. 애매하면 넣지 않는 쪽이
  /// 안전하다. 잘못 넣으면 멀쩡한 이름이 사라진다.
  static const _nameParticleEndings = [
    '에게',
    '에서',
    '으로',
    '에는',
    '까지',
    '부터',
    '하는',
    '되는',
    '있는',
    '통해',
    '통한',
    '위해',
    '위한',
    '대해',
    '관한',
    // 2026-08-14: 직함 칸에서 이름을 떼어내는 재검증을 넣으면서 필요해졌다.
    // 홍보 문구 조각("최고의", "제공하는", "신뢰할 수 있는")이 한글 2~4자라
    // 이름 규칙에 그대로 걸린다. 사람 이름이 이 어미로 끝나는 일은 없다.
    '하는',
    '되는',
    '있는',
    '의',
    // 조사로 끝나는 문구 조각("성공과", "만족을"). 사람 이름이 이 글자로
    // 끝나는 일은 없다.
    '과',
    '와',
    '을',
    '를',
  ];

  static bool _endsWithParticle(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    return _nameParticleEndings.any(trimmed.endsWith);
  }

  /// 사람 이름일 수 없는 일반명사. 명함 상단 홍보 문구가 OCR에서 잘리면 이런
  /// 낱말이 한글 2~4자 이름 규칙에 그대로 걸린다 — 실기기에서 "…최고의 ICT
  /// 전문 **기업**"의 마지막 조각이 이름 칸에 들어갔다(2026-08-13).
  ///
  /// ⚠️ **완전히 일치할 때만** 거른다. 부분 문자열로 비교하면 추가 178·180에서
  /// 겪은 함정을 그대로 반복한다("기업"으로 거르면 "기업은행" 같은 회사명까지
  /// 걸린다). 이 목록은 이름 칸에만 쓰이고 회사명·직함 판정에는 관여하지 않는다.
  static const _nonNameWords = {
    '기업',
    '전문',
    '고객',
    '서비스',
    '최고',
    '성공',
    '만족',
    '제공',
    '사업',
    '정보',
    '시스템',
    '솔루션',
    '주소',
    '전화',
    '팩스',
    '이메일',
    '홈페이지',
    '본사',
    '지사',
    '문의',
    '상담',
  };

  static bool _isNonNameWord(String name) =>
      _nonNameWords.contains(name.trim());

  /// 이름 자리에 **넣어서는 안 되는 값**인지. 조사·어미로 끝나거나 일반명사면
  /// 사람 이름이 아니다.
  ///
  /// 이 검사를 **배정하는 그 순간에** 해야 한다는 것이 2026-08-14 실측에서
  /// 드러났다. 예전에는 줄을 다 훑은 뒤에야 걸렀는데, 그러면 슬로건 줄의
  /// 마지막 낱말("…ICT 전문 **기업**")이 먼저 이름 자리를 차지하고 → 나중에
  /// 지워지고 → **정작 진짜 이름은 다시 볼 기회가 없어** 빈 값이 됐다
  /// (card_56 `이희규`가 원문에 멀쩡히 있는데도 빈 값으로 나왔다).
  /// 자리를 차지하기 전에 거르면 순회가 계속되어 뒤쪽 줄에서 이름을 찾는다.
  /// 약한 폴백에서 고른 값이 **한글이면 비운다**(사용자 결정 2026-08-22, ㉮안).
  ///
  /// ## 왜 한글만인가
  ///
  /// 이 자리는 규칙이 전부 실패해 확신하지 못하는 구간이다. 실측에서 **여기서
  /// 고른 한글 값은 한 번도 맞지 않았다.**
  ///
  /// ```
  /// ML Kit(기기, 96장)   약한 경로 12건
  ///                      한글이 든 값을 넣음  4건 → 0 맞음
  ///                      영문만 넣음         5건 → 표본에 정답이 없어 판정 불가
  ///                      이미 빈 값          3건
  /// ```
  ///
  /// ⚠️ **영문은 건드리지 않는다.** 처음에는 약한 폴백 전체를 비우려 했는데,
  /// 그러면 *"영문 전용 이름/회사명 + 영문 직함"*, *"회사명과 무관한 영문
  /// 이름은 그대로 이름이다"* 같은 **실제 테스터 제보로 만들어진 테스트 11건이
  /// 깨졌다**(2026-08-13·08-20). 영문 이름은 이 경로로 정상적으로 들어온다.
  ///
  /// 📌 **잰 곳만 비운다.** 표본 95장에 영문 전용 이름이 **0건**이라 영문 쪽은
  /// 애초에 채점되지 않았다 — 안 잰 것을 지우면 안 된다.
  ///
  /// 명함 앱에서 이름이 틀린 채 저장되면 나중에 그 사람을 못 찾고 **사용자는
  /// 틀린 줄도 모른다.** 빈 칸은 눈에 띄지만 틀린 값은 안 띈다.
  static String _blankIfUnsureHangul(String candidate) =>
      _hasHangul(candidate) ? '' : candidate;

  static bool _isRejectedName(String name) =>
      _endsWithParticle(name) || _isNonNameWord(name);

  /// 한국인 성씨. **가장 약한 폴백(빈자리 재검증 3단계)에서만** 쓴다.
  ///
  /// 왜 필요한가: 슬로건·부서명 조각은 "한글 2~3자"라는 모양만으로는 이름과
  /// 구별되지 않는다(`인터넷`·`모바일`·`성공과`). 낱말을 하나씩 금지 목록에
  /// 넣는 방식은 추가 182에서 이미 실패했다 — 하나 막으면 다음 것이 그 자리를
  /// 채운다. **이름의 첫 글자가 성씨인가**는 그런 뒤쫓기가 아닌 원리적인
  /// 신호다.
  ///
  /// ⚠️ 여기 없는 드문 성씨를 가진 사람은 이 폴백에서 빠진다 — 그때는 이름을
  /// 비워 두고 사용자가 채운다(추가 183 "확신하지 못하면 비운다"). 확신
  /// 경로(한글 이름 규칙·직함 분리)는 이 목록을 쓰지 않으므로 영향이 없다.
  static const _commonSurnames = {
    '김', '이', '박', '최', '정', '강', '조', '윤', '장', '임',
    '한', '오', '서', '신', '권', '황', '안', '송', '류', '전',
    '홍', '고', '문', '양', '손', '배', '백', '허', '유', '남',
    '심', '노', '하', '곽', '성', '차', '주', '우', '구', '민',
    '진', '지', '엄', '채', '원', '천', '방', '공', '현', '함',
    '변', '염', '여', '추', '도', '소', '석', '선', '설', '마',
    '길', '연', '위', '표', '명', '기', '반', '왕', '금', '옥',
    '육', '맹', '제', '탁', '국', '어', '은', '편', '용',
    // ⚠️ 드문 성씨 중 **일반명사의 첫 글자와 겹치는 것**은 일부러 뺐다 —
    // 모(모바일)·초(초대)·빈(빈칸)·감(감사)·호(호텔)·두(두바이)·피(피드백).
    // 실측에서 `모바일`이 이름 칸에 들어갔다. 그 성씨를 가진 사람은 이
    // 폴백에서 빠지고 이름이 비워지지만, 잘못된 값이 들어가는 것보다 낫다.
  };

  /// 두 글자 성씨. 첫 글자만 보면 놓친다(`남궁현`의 `남`은 목록에 있지만,
  /// `황보`·`제갈`·`선우`는 첫 글자가 흔한 성씨가 아닌 경우가 있다).
  static const _compoundSurnames = {
    '남궁',
    '황보',
    '선우',
    '제갈',
    '사공',
    '서문',
    '독고',
    '동방',
    '어금',
  };

  /// 이 토큰이 **성씨로 시작하는가**. 위 목록의 용도 설명 참고.
  static bool _startsWithSurname(String token) =>
      _compoundSurnames.any(token.startsWith) ||
      (token.isNotEmpty && _commonSurnames.contains(token[0]));

  /// 한글 이름 후보가 **실제 사람 이름 모양인가** — 성 1자 + 이름 2자
  /// (두 글자 성씨는 4자).
  ///
  /// 한글이 아닌 값에는 판단하지 않고 `true`를 돌려준다(영문 이름은 다른
  /// 근거로 가린다).
  ///
  /// 2026-08-14 실측에서 필요해졌다: 직함 키워드로 이름을 갈라내는 규칙이
  /// `디지털 커뮤니케이션 파트 / 책임`에서 `디지털`을 이름으로 뽑아, 첫 줄에
  /// 있던 진짜 이름 `홍승권`을 밀어냈다(card_08). 부서명·분야명도 한글
  /// 2~4자라 이름 규칙만으로는 구별되지 않는다.
  static bool _hangulNameLooksReal(String value) {
    if (!_koreanNameRegExp.hasMatch(value)) return true;
    if (_professionSuffixRegExp.hasMatch(value)) return false;
    final isCompound = _compoundSurnames.any(value.startsWith);
    return value.length == (isCompound ? 4 : 3) && _startsWithSurname(value);
  }

  /// `…사`로 끝나는 직업명(`변리사`·`도배사`·`세무사`). 성씨로 시작하고 3자라
  /// 이름 규칙을 그대로 통과한다 — `파트너 변리사 김세진`에서 `변리사`가 이름
  /// 칸에 들어갔다(card_26, 정답은 `김세진`).
  ///
  /// 한국 이름이 `사`로 끝나는 일은 드물어, 그 대가로 얻는 것이 더 크다.
  static final _professionSuffixRegExp = RegExp(r'사$');

  /// 한 덩어리로 읽힌 문자열에서 **사람 이름으로 보이는 한글 토큰 하나**를
  /// 뽑는다. 없으면 null.
  ///
  /// "빈자리 재검증"에서만 쓴다 — 이름 칸이 비어 있을 때 직함 칸을 다시 훑는
  /// 용도다. 확신 경로가 아니므로 기준을 빡빡하게 잡는다.
  ///
  /// - 순수 한글 토큰만 본다(영문 이름은 여기서 다루지 않는다 — 회사 로고·
  ///   부서명과 구별할 근거가 약하다).
  /// - **정확히 3자**여야 한다(두 글자 성씨는 4자). 한국 이름은 성 1자 + 이름
  ///   2자가 압도적이다. 2자를 허용했더니 서술 문구의 첫 낱말이 그대로
  ///   들어왔고(`설계, 제작 및 납품` → `설계`), 4자를 허용했더니 잘못 붙은
  ///   조각이 들어왔다(`주희정대` ← "주희정 대표").
  /// - **성씨로 시작**해야 한다 — `인터넷`·`모바일`처럼 다른 검사를 다
  ///   통과하는 낱말을 거른다(`_commonSurnames` 주석 참고).
  /// - 직함·회사 키워드가 걸린 토큰은 뺀다(`연구소장`·`상무`·`이사`).
  ///   ⚠️ 이 때문에 `이사랑` 같은 실제 이름도 함께 걸린다. 빈 값이 틀린
  ///   값보다 낫다는 원칙(추가 183)에 따라 감수한다.
  /// - 슬로건 조각(`최고의`·`제공하는`)은 `_isRejectedName`이 거른다.
  /// - 지명은 뺀다(`영등포구`·`성수역`) — 이름 규칙에 잘 걸린다.
  static final _placeSuffixRegExp = RegExp(r'(시|도|구|군|읍|면|동|리|로|길|역|층|호|사)$');

  /// 숫자 없는 상세주소(건물명)를 알아보는 접미사. 주소 바로 다음 줄이 이
  /// 접미사로 끝나면 상세주소로 본다("SK T-타워", card_03). 조직명과 겹치는
  /// 접미사(센터·관·타운 등)는 이름·회사명을 삼킬 수 있어 넣지 않는다.
  static final _buildingNameRegExp = RegExp(r'(타워|빌딩|빌|플라자|프라자|스퀘어|캐슬|팰리스)$');

  /// 주소로 읽히는 구간만 지운 나머지. 이름 후보를 찾을 때 쓴다 —
  /// 지명이 이름 규칙에 잘 걸려서 주소 구간은 봐서는 안 되지만, 줄 전체를
  /// 버리면 같은 줄에 있는 이름까지 잃는다.
  /// **확정된 주소 문자열을 먼저** 걷어내고, 그래도 주소로 읽히면 그때
  /// 정규식으로 지운다.
  ///
  /// 정규식만 쓰면 안 되는 이유: 명함 한 장이 한 줄로 뭉쳐 인식되면 주소
  /// 정규식이 줄 끝까지 통째로 먹어서, 주소 뒤에 있던 이름·회사명까지 같이
  /// 지워진다(card_18에서 `손연기`가 그렇게 사라졌다). 파싱이 이미 잘라낸
  /// 주소는 정확한 경계를 알고 있으므로 그것을 먼저 쓴다.
  static String _withoutAddressSpans(
    String line,
    RegExp addressRegExp,
    RegExp roadAddressNoProvinceRegExp, {
    String? address,
    String? addressDetail,
  }) {
    var out = line;
    for (final known in [address, addressDetail]) {
      if (known != null && known.isNotEmpty) out = out.replaceAll(known, ' ');
    }
    if (addressRegExp.hasMatch(out) ||
        roadAddressNoProvinceRegExp.hasMatch(out)) {
      out = out
          .replaceAll(addressRegExp, ' ')
          .replaceAll(roadAddressNoProvinceRegExp, ' ');
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _extractPersonNameToken(String source) {
    final tokens = source
        .split(RegExp(r'[\s./|,·\-()]+'))
        .where((t) => t.isNotEmpty);
    for (final token in tokens) {
      if (!_koreanNameRegExp.hasMatch(token)) continue;
      final isCompound = _compoundSurnames.any(token.startsWith);
      if (token.length != (isCompound ? 4 : 3)) continue;
      if (!_startsWithSurname(token)) continue;
      if (_placeSuffixRegExp.hasMatch(token)) continue;
      if (_isRejectedName(token)) continue;
      if (_titleKeywords.any((k) => _containsCi(token, k))) continue;
      if (_companyKeywords.any((k) => _containsCi(token, k))) continue;
      if (!_looksLikePersonName(token)) continue;
      return token;
    }
    return null;
  }

  /// 이 줄이 **사람 이름 모양**인지. 약한 폴백(규칙으로 확신하지 못한 구간)에서
  /// 후보를 거르는 데만 쓴다 — 확신 경로로 잡힌 이름은 이 검사를 거치지 않는다.
  ///
  /// 통과 기준은 "이름이라면 이럴 리 없다"는 것들만 본다. 이름을 알아맞히려는
  /// 게 아니라 **명백히 이름이 아닌 것을 떨어뜨리는** 용도다.
  ///
  /// 실측에서 이름 칸에 들어갔던 것들(추가 181·182): `duke@etribe.co.kr`,
  /// `704, SK V1 TOWER, 25, Yeonmujang 5ga-gil`, `I'm a Voyager of value`,
  /// `설계, 제작 및 납품 E-mail.`, `Head of R&D Dept. Ko Byoung Ho`.
  static bool _looksLikePersonName(String line) {
    final s = line.trim();
    if (s.isEmpty || s.length > 25) return false;
    // 이메일·URL은 이름이 아니다.
    if (s.contains('@') ||
        RegExp(r'(https?://|www\.)', caseSensitive: false).hasMatch(s)) {
      return false;
    }
    // 이름에는 쉼표가 없다. 주소·서술형 문장을 떨어뜨린다.
    if (s.contains(',')) return false;
    // 숫자가 둘 이상이면 이름이 아니다(주소·번호 조각).
    if (RegExp(r'\d').allMatches(s).length >= 2) return false;
    // 연락처 라벨이 남아 있으면 이름이 아니다.
    if (_contactLabelPattern.hasMatch(s)) return false;

    if (_hasHangul(s)) {
      // 한글 이름은 음절 사이를 띄우는 경우까지 감안해 공백을 뺀 길이로 본다.
      // 복성(황보·남궁)과 5자 이름까지 허용한다.
      final compact = s.replaceAll(RegExp(r'\s'), '');
      return compact.length >= 2 && compact.length <= 5;
    }
    // 영문 이름은 단어 2~4개 정도다. "I'm a Voyager of value"(6단어)나
    // "Head of R&D Dept. Ko Byoung Ho"(7단어)는 여기서 떨어진다.
    final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 4) return false;

    // 🚨 **조직·부서 낱말이 들어 있으면 사람 이름이 아니다**(2026-08-29,
    //    52장 실측). `Innovation Team`·`Marketing Division`이 **「영문 낱말
    //    2~4개」라는 조건만으로 통과**해 이름 칸에 들어갔다.
    //
    // ⚠️ **빈 칸이 낫다.** 이름 칸에 부서명이 들어가면 **채워진 것처럼 보여**
    //    이용자가 못 알아챈다 — *"가짜 데이터를 만들지 않는다"*와 같은 자리다.
    if (words.any(
      (w) => _orgWords.contains(
        w.toLowerCase().replaceAll(RegExp(r"[.'-]"), ''),
      ),
    )) {
      return false;
    }

    // 🚨 **소문자로 시작하는 영문 구절은 슬로건이다.** 실측에서
    //    `more than the most`가 이름 칸에 들어갔다. 사람 이름은 낱말마다
    //    대문자로 시작한다.
    if (words.length >= 3 && words.every((w) => RegExp(r'^[a-z]').hasMatch(w))) {
      return false;
    }

    return words.every((w) => RegExp(r"^[A-Za-z][A-Za-z.'-]*$").hasMatch(w));
  }

  /// 자간을 벌려 인쇄한 구간의 공백을 붙인다.
  ///
  /// 로고체로 `(주) 에 이 치 씨 엔 씨`처럼 **글자마다 공백**을 넣은 명함이
  /// 흔한데, 그대로 두면 회사명 칸에 공백이 섞인 채 저장된다(2026-08-14
  /// 실기기 확인, 추가 186). 이름 쪽에는 이미 공백을 떼는 규칙이 있었지만
  /// (`최 태 웅` → `최태웅`) 회사명에는 없어서 생긴 차이다.
  ///
  /// ⚠️ **공백을 전부 없애면 안 된다.** `NELSON SPORTS, INC.`가
  /// `NELSONSPORTS,INC.`가 되고 `David Kim`도 붙는다. 그래서 **1글자 토큰이
  /// 3개 이상 잇달아 나오는 구간만** 붙인다 — `커넥션 센스`(2글자 이상)나
  /// 문장 속에 낀 한 글자(`및`)는 건드리지 않는다.
  /// 한 줄에 **한글명과 영문명이 나란히 인쇄된 것**에서 뒤에 붙은 영문을 뗀다
  /// (`케이스랩 K.ACE LAB` → `케이스랩`, 추가 424·430).
  ///
  /// ## 왜 파싱 **맨 앞**인가
  ///
  /// 고른 뒤에 값에서 떼는 방법도 재 봤는데 **+1장뿐이었다.** 파서가 그 줄을
  /// **애초에 안 고르기** 때문이다 — `케이스랩 K.ACE LAB`은 회사명 모양으로
  /// 안 보여 다른 줄에 밀린다. 영문을 먼저 떼어 `케이스랩`으로 만들면 그제야
  /// 골라진다. 같은 규칙을 여기 두면 **+4장**이다.
  ///
  /// ## ⚠️ 손대지 않는 줄이 규칙의 절반이다
  ///
  /// 실측(96장 전 필드 전후 대조)에서 **직함 줄을 안 빼면 4장이 깨졌다** —
  /// `Business Development` 같은 영문 직함이 한글과 한 줄에 있을 때 같이
  /// 떨어져 나간다. 직함 키워드가 걸린 줄을 건너뛰자 **깨짐 0**이 됐다.
  ///
  /// ⚠️ **괄호는 안에 한글이 없을 때만 뗀다.** 이 조건이 없으면
  /// `(주)컴플러스`가 `컴플러스`가 된다 — 추가 424에서 정답지를 고칠 때
  /// 실제로 낸 버그이고, 적용 직전에 잡았다.
  ///
  /// ⚠️ **정답지를 가른 규칙과 같아야 한다.** 다르면 채점기와 파서가 서로
  /// 다른 답을 옳다고 본다.
  static String _stripLatinParallel(String line) {
    var s = line.trim();
    if (s.isEmpty || !_hasHangul(s)) return line; // 영문 전용 회사명 보존
    // 연락처·주소·주소류가 든 줄은 건드리지 않는다.
    if (s.contains('@') || RegExp(r'\d{3,}').hasMatch(s)) return line;
    if (RegExp(r'(https?://|www\.)', caseSensitive: false).hasMatch(s)) {
      return line;
    }
    // ⚠️ 직함 줄 제외 — 위 주석 참고. 이 한 줄이 깨짐 4를 0으로 만든다.
    if (_titleKeywords.any((k) => _containsCi(s, k))) return line;

    String prev = '';
    while (prev != s) {
      prev = s;
      final paren = RegExp(r'[\(（]([^\)）]*)[\)）]\s*$').firstMatch(s);
      if (paren != null && !_hasHangul(paren.group(1)!)) {
        s = s.substring(0, paren.start).trim();
        continue;
      }
      final tail = RegExp(
        r"(?:^|\s)([A-Za-z][A-Za-z0-9.,&'\-]*(?:\s+[A-Za-z][A-Za-z0-9.,&'\-]*)*)\s*$",
      ).firstMatch(s);
      if (tail != null && !_hasHangul(tail.group(1)!)) {
        final cut = s.lastIndexOf(tail.group(1)!);
        s = (cut > 0 ? s.substring(0, cut) : '').trim();
        continue;
      }
    }
    // 다 떼고 나면 남는 게 없는 경우 — 원문을 그대로 둔다.
    if (s.isEmpty) return line;
    // ⚠️ **남은 한글이 사람 이름 모양이면 병기가 아니었다.**
    // `이정현 DA Sovargen`은 한글명+영문명이 아니라 **이름과 회사가 한 줄로
    // 뭉친 것**이고, 여기서 영문을 떼면 **회사를 통째로 잃는다.**
    // 자동 테스트 3건(card_64·card_108·Sovargen)이 이것을 잡았다 — 96장
    // 명함 대조에서는 깨짐이 0이었는데도 그랬다. **표본에 없는 모양이었다.**
    if (_looksLikeKoreanPersonNameShape(s)) return line;
    return s;
  }

  /// 남은 한글에 **사람 이름 모양의 낱말이 있는가** — 영문 병기 떼기를
  /// 멈출지 판단하는 데만 쓴다(추가 430). 이름 판정 자체는
  /// `_hangulNameLooksReal`이 한다.
  ///
  /// ⚠️ **줄 전체가 아니라 낱말 단위로 본다.** `장 장동일 (Daniel)`에서
  /// `(Daniel)`은 회사 병기가 아니라 **그 사람의 영문 이름**이고, 떼면 이름
  /// 판정이 흔들린다(card_64). 줄 전체만 보면 `장 장동일`이 공백 때문에
  /// 이름 모양을 벗어나 이 함정을 못 잡는다.
  static bool _looksLikeKoreanPersonNameShape(String s) {
    for (final tok in s.trim().split(_whitespaceSplitRegExp)) {
      if (_koreanNameRegExp.hasMatch(tok) && _startsWithSurname(tok)) {
        return true;
      }
    }
    return false;
  }

  /// 줄 전체가 괄호 하나이고, 그 안이 **주소 조각**인가 (추가 428).
  ///
  /// 법정동(`역삼동`·`성수동2가`)이나 건물명 접미사가 들어 있을 때만 참이다.
  /// ⚠️ `(Daniel)`·`(Marketing Company)` 같은 괄호를 상세주소에 붙이지 않기
  /// 위한 조건이다 — 괄호라고 다 주소가 아니다.
  static bool _looksLikeAddressParenLine(String line) {
    final t = line.trim();
    final m = RegExp(r'^[\(（]([^\)）]+)[\)）]$').firstMatch(t);
    if (m == null) return false;
    final inner = m.group(1)!;
    if (!_hasHangul(inner)) return false;
    // 법정동·가·리로 끝나는 토큰이 있거나, 건물명 접미사가 있으면 주소로 본다.
    if (RegExp(r'(동|가|리)\d*\s*(,|$)').hasMatch(inner)) return true;
    return _buildingNameRegExp.hasMatch(inner);
  }

  /// 그 줄의 로마자가 **한글 이름 낱말의 성씨 표기**와 맞으면 그 낱말을
  /// 돌려준다 (`이선경 Sun-Kyoung Lee` → `이선경`, 추가 429).
  ///
  /// ## 왜 필요한가
  ///
  /// 실측(96장): 이름을 못 맞힌 20장 중 **낱말 하나로 멀쩡히 서 있는데 못
  /// 고른 것이 5장**이었고, **다섯 장 전부** 한글 이름 옆에 로마자가 같은 줄에
  /// 있었다. 그중 넷이 **그 사람 이름의 로마자 표기**다 — 한국 명함에서 아주
  /// 흔한 모양인데 파서가 그 줄을 이름 줄로 확신하지 못해 다른 줄에 밀렸다.
  ///
  /// ## ⚠️ 로고 줄이 저절로 걸러지는 것이 이 신호의 값이다
  ///
  /// 나머지 하나는 `Ma soft`(M2SOFT 로고 오독)였는데, **성씨 표기와 안 맞아
  /// 저절로 빠진다.** 크기·위치로는 못 가르던 것을 글자가 가른다.
  static String? _nameByRomanizedSurname(String line) {
    if (!RegExp(r'[A-Za-z]').hasMatch(line)) return null;
    final latin = _latinWordRegExp
        .allMatches(line)
        .map((m) => m.group(0)!.toLowerCase().replaceAll(RegExp(r"[-']"), ''))
        .toSet();
    if (latin.isEmpty) return null;
    for (final tok in line.split(_whitespaceSplitRegExp)) {
      final t = tok.trim();
      if (!_koreanNameRegExp.hasMatch(t)) continue;
      if (_isRejectedName(t) || !_hangulNameLooksReal(t)) continue;
      final forms = _surnameRomanizations[t[0]];
      if (forms == null) continue;
      // ⚠️ **정확히 같을 때만** 인정한다. 부분 일치를 허용하면 `한`(han)이
      // `Handong`·`Chanho` 같은 말에 걸린다.
      if (forms.any(latin.contains)) return t;
    }
    return null;
  }

  static String _collapseCharSpacing(String line) {
    // 전각 공백(U+3000)도 명함에서 쓰인다 — 같은 공백으로 취급한다.
    final tokens = line.split(RegExp(r'[ \u3000]+'));
    if (tokens.length < 3) return line;

    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      if (tokens[i].isEmpty) {
        i++;
        continue;
      }
      var j = i;
      while (j < tokens.length && tokens[j].runes.length == 1) {
        j++;
      }
      if (j - i >= 3) {
        out.add(tokens.sublist(i, j).join());
        i = j;
      } else {
        out.add(tokens[i]);
        i++;
      }
    }
    return out.join(' ');
  }

  /// 전화번호 줄에 붙은 **라벨**의 종류.
  ///
  /// 번호 패턴만 보면 `H.P 070-…`(휴대폰 라벨인데 070)은 사무실로 가고,
  /// `TEL. 010-…`(소상공인 명함에 흔한 대표전화)은 휴대폰으로 간다. 뒤 경우가
  /// 특히 나쁘다 — 같은 명함에 진짜 휴대폰이 따로 있으면 **먼저 잡힌 대표전화가
  /// 휴대폰 칸을 차지하고 진짜 번호는 버려진다**(2026-08-14 재현, 테스터 E-03).
  ///
  /// 명함에 적힌 라벨은 **작성자가 직접 밝힌 정보**라 패턴 추정보다 정확하다.
  static const _mobileLabelPattern =
      r'\b(H\.?P|M\.?P|C\.?P|MOBILE|CELL)\b|\bH\.|\bM\.|휴대폰|휴대전화|핸드폰';
  static const _officeLabelPattern = r'\b(TEL|PHONE|OFFICE)\b|\bT\.|대표전화|전화';

  /// 한 줄에 **한 종류의 라벨만** 있을 때 그 종류를 돌려준다. 두 종류가 섞여
  /// 있으면(`M.010-… T.02-…`) 어느 번호가 어느 라벨인지 이 방식으로는 못
  /// 가리므로 null을 돌려 기존 패턴 판정에 맡긴다.
  ///
  /// ⚠️ 휴대폰 라벨을 **먼저 걷어낸 뒤** 사무실 라벨을 본다. `휴대전화` 안에
  /// `전화`가 들어 있어서, 순서를 바꾸면 한 줄이 두 종류로 잡힌다.
  static bool? _isMobileLabelLine(String line) {
    final upper = line.toUpperCase();
    final mobileRe = RegExp(_mobileLabelPattern, caseSensitive: false);
    final hasMobile = mobileRe.hasMatch(upper);
    final withoutMobile = upper.replaceAll(mobileRe, ' ');
    final hasOffice = RegExp(
      _officeLabelPattern,
      caseSensitive: false,
    ).hasMatch(withoutMobile);
    if (hasMobile && !hasOffice) return true;
    if (hasOffice && !hasMobile) return false;
    return null;
  }

  /// 뭉친 줄에서 **회사 키워드 주변만** 잘라낸다.
  ///
  /// OCR이 여러 줄을 하나로 붙이면 그 안에 회사 키워드가 있어 **줄 전체가
  /// 회사명**이 된다. 103장 실측에서 남은 회사명 오분류 7장이 전부 이 형태였고,
  /// 그중 4장은 **줄 안에 정답이 들어 있었다**(추가 195):
  ///
  /// - `… (주)온에이드 ONADInc Hello!` → `(주)온에이드`
  /// - `Global GTM & M&A Advisor 모멘텀메이커 주식회사` → `모멘텀메이커 주식회사`
  /// - `NELSON SPORTS, INC. 1644-1708 www.nelson.co.kr ARCTERYX` → `NELSON SPORTS, INC.`
  ///
  /// 규칙은 두 가지뿐이다.
  /// 1. 키워드가 **다른 글자와 붙어 있으면** 그 토큰이 곧 회사명이다
  ///    (`크림하우스(주)`, `(주)온에이드`).
  /// 2. 키워드가 **단독 토큰이면** 앞 토큰을 하나 붙인다. 그 앞 토큰이 쉼표로
  ///    끝나면(`SPORTS,`) 이름이 이어지는 중이므로 하나 더 붙인다.
  ///
  /// ⚠️ **짧은 줄은 건드리지 않는다.** 정상적으로 인식된 회사명까지 잘라내면
  /// 손해가 크다 — 뭉친 줄(25자 초과·토큰 4개 이상)에만 적용한다.
  /// [always]를 주면 "짧은 줄은 건드리지 않는다" 안전장치를 건너뛴다.
  ///
  /// 그 안전장치는 **줄 전체가 회사명일 수도 있는** 경우를 지키기 위한 것이다.
  /// 그런데 주소를 걷어내고 남은 조각(`(주)고든 08808`)은 애초에 줄 전체가
  /// 아니고 우편번호 같은 부스러기가 섞여 있어서, 그대로 두면 회사 칸에
  /// 숫자가 딸려 들어간다(2026-08-14 실측 card_31·129).
  static String _trimCompanyAroundKeyword(
    String line,
    String keyword, {
    bool always = false,
  }) {
    final trimmed = line.trim();
    if (!always && trimmed.length <= 25) return trimmed;
    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (!always && tokens.length < 4) return trimmed;
    if (tokens.isEmpty) return trimmed;

    final idx = tokens.indexWhere((t) => _containsCi(t, keyword));
    if (idx < 0) return trimmed;

    String lettersOf(String v) => v.replaceAll(RegExp(r'[^A-Za-z가-힣]'), '');
    if (lettersOf(tokens[idx]).length > lettersOf(keyword).length) {
      return tokens[idx];
    }

    var start = idx > 0 ? idx - 1 : idx;
    if (start > 0 && tokens[start].endsWith(',')) start -= 1;
    return tokens.sublist(start, idx + 1).join(' ');
  }

  /// 휴대폰 번호 앞이 **잘려 나간 것**을 되살린다.
  ///
  /// `M. 107757 1036` → `M. 01077571036` (실측 card_66).
  ///
  /// 실물을 열어 보고서야 원인을 알았다. 명함 표기는 `M. +82 10(7757 1036)`인데
  /// **`82`에 볼펜으로 동그라미와 괄호가 그려져 있어** OCR이 `+8`을 흘렸다.
  /// 즉 "맨 앞 0이 떨어졌다"가 아니라 **국가번호 표기의 앞부분이 날아간 것**이다.
  /// 숫자만 보고 세운 가설이 틀렸던 사례다 — 결과값은 맞았지만 근거가 달랐다.
  ///
  /// 어느 쪽이든 되살리는 규칙은 같다: **한국 전화번호 중 `1`로 시작하는
  /// 10자리는 존재하지 않으므로** 해석이 `0`을 붙이는 것 하나뿐이다.
  ///
  /// ⚠️ 휴대폰 라벨(`M`·`H.P`·`모바일`)이 있는 줄에서만 손댄다. 번호를 앱이
  /// 고쳐 쓰는 것은 잘못하면 모르는 사람에게 전화가 가는 일이라(추가 196),
  /// 근거가 분명할 때만 한다. `1588`·`1644` 같은 대표번호는 8자리라 안 걸린다.
  ///
  /// 같은 명함의 유선번호(`T. 231631 2131)` ← `+82 31(631 2131)`, 정답
  /// `031-631-2131`)는 **일부러 손대지 않는다.** 앞 글자가 몇 개 날아갔는지
  /// 숫자만으로는 알 수 없어 추측이 되고, 유선은 대역 규칙도 느슨하다.
  static String _restoreBrokenPhones(String line) {
    if (_isMobileLabelLine(line) != true) return line;
    return line.replaceAllMapped(
      RegExp(r'(?<!\d)10[-.\s]?\d{4}[-.\s]?\d{4}(?!\d)'),
      (m) => '0${m.group(0)}',
    );
  }

  /// 전화번호가 **두 줄로 갈라져** 인식된 것을 잇는다.
  ///
  /// `… 010 4548 부장 스포츠기획팀 박지웅` + 다음 줄 `1893` → `010-4548-1893`
  /// (실측 card_20). 명함 레이아웃상 번호 뒷자리가 다음 줄로 넘어가 인식되는
  /// 경우가 있다.
  ///
  /// ⚠️ 조건을 좁게 잡는다: 앞 줄에 **01X + 4자리로 끝나는 미완성 번호**가 있고
  /// (뒤에 숫자가 더 없어야 한다), 뒤 줄이 **숫자 4자리만** 있는 줄이어야 한다.
  /// 없는 번호를 만들어 내지 않기 위해서다 — 잇는 숫자는 둘 다 원문에 있다.
  static List<OcrLineBox> _joinSplitPhoneNumbers(List<OcrLineBox> lineData) {
    final incomplete = RegExp(r'01[016789][-.\s]?\d{4}(?![\d\s.\-]*\d)');
    final onlyFourDigits = RegExp(r'^\s*(\d{4})\s*$');
    final out = [...lineData];
    for (var i = 0; i < out.length; i++) {
      final m = incomplete.firstMatch(out[i].text);
      if (m == null) continue;
      // 바로 다음 두 줄까지만 본다 — 멀리 떨어진 숫자를 끌어오면 남의 번호를
      // 붙일 위험이 있다.
      for (var j = i + 1; j < out.length && j <= i + 2; j++) {
        final tail = onlyFourDigits.firstMatch(out[j].text);
        if (tail == null) continue;
        final joined = out[i].text.replaceRange(
          m.start,
          m.end,
          '${m.group(0)!.replaceAll(RegExp(r'\D'), '')}${tail.group(1)}',
        );
        // 좌표는 **합쳐진 쪽(i)의 것을 그대로 둔다.** 번호가 두 줄로 갈렸을
        // 뿐 자리는 앞줄의 자리다. j는 비우므로 아래에서 걸러진다.
        out[i] = (
          text: joined,
          height: out[i].height,
          top: out[i].top,
          left: out[i].left,
          width: out[i].width,
        );
        out[j] = (
          text: '',
          height: out[j].height,
          top: out[j].top,
          left: out[j].left,
          width: out[j].width,
        );
        break;
      }
    }
    return out.where((l) => l.text.trim().isNotEmpty).toList();
  }

  /// 국가번호(+82) 표기를 국내 표기로 바꾼다.
  ///
  /// `+82-10-8977-9661` → `010-8977-9661`, `82.2.6077.9901` → `02-6077-9901`.
  /// 국제 표기는 국가번호 뒤에서 **앞자리 0을 뗀 형태**라, 되돌리려면 0을
  /// 다시 붙이면 된다.
  static String? _domesticFromIntl(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (!digits.startsWith('82')) return null;
    // `(0)`을 병기한 표기(`+82 (0)32-…`)는 숫자만 뽑으면 이미 0이 붙어 있다.
    // 그때 0을 또 붙이면 `00327…`이 된다.
    final rest = digits.substring(2);
    if (rest.startsWith('0')) {
      if (rest.length < 9 || rest.length > 11) return null;
      return _normalizePhone(rest);
    }
    if (rest.length < 8 || rest.length > 10) return null;
    return _normalizePhone('0$rest');
  }

  /// 줄에서 이메일과 URL을 걷어낸다. 키워드 판정 전에 쓴다 — 도메인 문자열이
  /// 회사 키워드에 우연히 걸리는 것을 막기 위해서다(`elancer.**co**.kr` ⊂ `Co.`).
  static String _stripContacts(String line) => line
      .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+'), ' ')
      .replaceAll(
        RegExp(r'(https?://|www\.)[^\s]+', caseSensitive: false),
        ' ',
      );

  /// 연락처 라벨(TEL/FAX/E-mail 등)과 번호·주소를 걷어내면 **글자가 거의 남지
  /// 않는 줄**인지. 그런 줄은 어느 칸에도 들어갈 값이 아니다.
  ///
  /// 왜 필요한가: 전화번호·이메일은 앞 단계에서 뽑아 가는데, 그 줄에 남은
  /// 라벨 조각(`TEL. FAX.`)은 그대로 leftover로 흘러가 맨 앞이면 이름이나
  /// 회사명이 된다. 67장 실측에서 실제로 3장이 이렇게 망가졌다(추가 181).
  ///
  /// ⚠️ **단어 경계로만 지운다.** 부분 문자열로 지우면 "SK **tel**ecom"의 로고가
  /// 잘려 나가는 식으로 멀쩡한 회사명을 망가뜨린다 — 추가 178·180에서 반복해
  /// 겪은 함정이라 여기서는 처음부터 경계를 건다. 한 글자 라벨(T·F·M·E)은
  /// **뒤에 마침표가 붙은 형태만** 라벨로 본다.
  static final _contactLabelPattern = RegExp(
    r'\b(TEL|FAX|PHONE|MOBILE|E-?MAIL|DIRECT|DIR|HP|CP)\b|\b[TFMEHC]\.|'
    r'전화|팩스|휴대폰|휴대전화|이메일|직통|대표전화',
    caseSensitive: false,
  );

  static bool _isContactLabelResidue(String line) {
    var s = line;
    // 이메일 → URL → 숫자 순으로 걷어낸다(이메일이 URL 규칙에 먼저 걸리지
    // 않도록 순서가 중요하다).
    s = s.replaceAll(RegExp(r'[\w.+-]+@[\w.-]+'), ' ');
    s = s.replaceAll(
      RegExp(r'(https?://|www\.)[^\s]+', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\d'), ' ');
    s = s.replaceAll(_contactLabelPattern, ' ');
    final letters = s.replaceAll(RegExp(r'[^가-힣A-Za-z]'), '');
    return letters.length < 2;
  }

  /// 이메일 정규식이 뽑아낸 값이 완전한 이메일 형태인지(라벨을 떼어낸 뒤
  /// 재검증할 때 쓴다).
  static final _fullEmailPattern = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// "E-mail:"/"E-mail."/"Email " 같은 **단어형** 라벨. 대소문자를 가리지
  /// 않는다 — 로컬파트가 통째로 이 단어("email")로 시작할 확률은 사실상 없다.
  static final _emailLabelPrefixWordPattern = RegExp(
    r'^e-?mail[.:\s]*',
    caseSensitive: false,
  );

  /// "E." / "E " / "E:" 같은 **한 글자** 라벨. 대문자 `E`일 때만 본다.
  static final _emailLabelPrefixLetterPattern = RegExp(r'^E[.:\s]+');

  /// 이메일 로컬파트 앞에 라벨 잔재가 그대로 붙어 오는 경우를 걷어낸다.
  /// 실측(신규 등록 96건, 2026-08-20 — `docs/planning/backlog.md` 참고)에서
  /// `E.wcho@lgcns.com`처럼 명함의 "E." 라벨이 로컬파트에 그대로 붙어 저장된
  /// 사례가 4건 나왔다 — 라벨의 마침표가 이메일 로컬파트 허용 문자(`.`)와
  /// 같아서 이메일 정규식이 라벨까지 통째로 삼킨 것이다.
  ///
  /// ⚠️ **대문자 `E` + 구분자(마침표/콜론/공백)가 있을 때만** 걷어낸다.
  /// `Ejuyeon@sto.or.kr`처럼 구분자 없이 붙은 경우도 같은 데이터에 실재하지만,
  /// 라벨인지 실제 아이디 앞글자인지 규칙만으로 가릴 수 없어 그대로 둔다 —
  /// 오탐이 더 위험하다(CLAUDE.md 4절, "조건을 넓게 잡았다가 회귀 난 전례").
  ///
  /// ⚠️ 소문자 `e`는 보지 않는다 — 명함 라벨은 인쇄가 대문자인 반면(`E.`),
  /// 실제 이메일 로컬파트는 소문자 이니셜식 표기가 흔하다(`e.kim@…`,
  /// `eric.maeng@…`, `eomysj@…` — 셋 다 같은 96건 표본에 실재). 대소문자를
  /// 신호로 쓰면 라벨과 정상 아이디를 가를 수 있는데, 소문자까지 같이 보면
  /// 그 신호가 사라진다.
  ///
  /// 걷어낸 뒤 남는 부분이 **그 자체로 완전한 이메일**일 때만 값을 바꾼다 —
  /// 아니면 라벨처럼 보였을 뿐 실제로는 다른 문자열일 수 있다.
  static String _stripEmailLabelPrefix(String value) {
    for (final pattern in [
      _emailLabelPrefixWordPattern,
      _emailLabelPrefixLetterPattern,
    ]) {
      final match = pattern.firstMatch(value);
      if (match == null) continue;
      final rest = value.substring(match.end);
      if (_fullEmailPattern.hasMatch(rest)) return rest;
    }
    return value;
  }

  /// [index]가 걸쳐 있는 **공백으로 나뉜 토막**을 돌려준다.
  ///
  /// 정규식이 쉼표에서 멈춰 **잘린 이메일**을 물어 왔을 때, 그 자리의 **온전한
  /// 토막**을 꺼내 되살리기 위해 쓴다.
  static String? _tokenAround(String line, int index) {
    if (index < 0 || index >= line.length) return null;
    var start = index;
    while (start > 0 && !RegExp(r'\s').hasMatch(line[start - 1])) {
      start--;
    }
    var end = index;
    while (end < line.length && !RegExp(r'\s').hasMatch(line[end])) {
      end++;
    }
    final token = line.substring(start, end);
    return token.isEmpty ? null : token;
  }

  /// **마침표를 쉼표로 읽은 이메일을 되살린다**(2026-08-29, 사용자 제보).
  ///
  /// ## 무엇이 문제였나
  ///
  /// 이메일 정규식은 `…@도메인.최상위`처럼 **마침표**를 요구한다. 그런데
  /// 인식기가 **`.` 을 `,` 로 읽으면**(`hong@company,co,kr`) 정규식에 아예 안
  /// 걸리고, 그러면 **이메일 칸이 빈 채로 저장된다.**
  ///
  /// 🚨 **「잘못 잘린」 것이 아니라 「없는 것으로 취급」된 것**이라 화면에도
  /// 아무 흔적이 안 남는다 — 이용자는 인식기가 그 줄을 못 봤다고 생각한다.
  ///
  /// ✅ **실물(2026-08-29)**: globe2030님이 같은 명함을 **아이폰·폴드 양쪽에**
  /// 넣었는데 **둘 다** 이메일을 못 읽어 수기로 넣으셨다. **기기 차이가 아니라
  /// 인식기 공통**이라는 뜻이다.
  ///
  /// ## 되살리는 규칙
  ///
  /// **영숫자 사이에 낀 쉼표만** 마침표로 바꾼다. 그렇게 바꾼 결과가 **그 자체로
  /// 완전한 이메일일 때만** 값으로 쓴다.
  ///
  /// ```
  /// hong@company,co,kr   →  hong@company.co.kr     되살린다
  /// hong,gil@x,com       →  hong.gil@x.com         되살린다
  /// a@b.com, 02-1234     →  뒤 쉼표는 영숫자 사이가 아니라 안 건드린다
  /// ```
  ///
  /// ⚠️ **끝에 붙은 쉼표·마침표는 지운 뒤 본다** — `a@b.com,`처럼 문장부호로
  /// 붙는 경우가 흔한데, 그걸 마침표로 바꾸면 `a@b.com.`이 되어 되레 깨진다.
  ///
  /// 되살릴 수 없으면 `null`. **짐작해서 채우지 않는다.**
  @visibleForTesting
  static String? repairCommaEmail(String token) {
    final trimmed = token.trim().replaceAll(RegExp(r'[.,;:]+$'), '');
    if (!trimmed.contains('@')) return null;
    if (_fullEmailPattern.hasMatch(trimmed)) return null; // 이미 멀쩡하다
    final repaired = trimmed.replaceAllMapped(
      RegExp(r'(?<=[A-Za-z0-9]),(?=[A-Za-z0-9])'),
      (_) => '.',
    );
    if (repaired == trimmed) return null;
    return _fullEmailPattern.hasMatch(repaired) ? repaired : null;
  }

  /// 한글(음절 또는 자모)이 하나라도 들어 있는지. 로고 판별에서 한글 후보를
  /// 건드리지 않기 위해 쓴다.
  static bool _hasHangul(String s) => RegExp(r'[가-힣ㄱ-ㆎ]').hasMatch(s);

  static bool _containsCi(String haystack, String needle) =>
      haystack.toUpperCase().contains(needle.toUpperCase());

  /// "실장 곽용환"(키워드 먼저), "이정섭 부장"(이름 먼저), "윤 덕 현
  /// 컨설팅 및 딜리버리 팀장"(이름이 한 글자씩 띄어져 있고 직함은 길게
  /// 서술형)까지 — 직함 키워드가 걸린 줄에 이름이 같이 붙어 있는 실제
  /// 명함 사례들을 토큰 단위로 분리한다. 못 찾으면 null.
  ///
  /// [matchedKeyword]와 정확히 같은 토큰은 이름 후보 판별에서 제외한다 —
  /// "대표", "이사", "실장"처럼 직함 키워드 자체가 한글 2~4자라 이름
  /// 정규식에도 우연히 걸리는 경우가 있다("대표 김 정 웅"에서 "대표"가
  /// 이름으로 오인되는 문제, 실제 명함 샘플로 확인됨). 직함 텍스트를 다시
  /// 조립할 땐 이름으로 소비되지 않은 원래 토큰을 순서대로 이어붙여서,
  /// 키워드 외의 서술형 텍스트("컨설팅 및 딜리버리")도 살아남게 한다.
  static ({String name, String title})? _splitNameFromTitleLine(
    String line,
    String matchedKeyword,
  ) {
    final tokens = line
        .split(_whitespaceSplitRegExp)
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length < 2) return null;

    final candidateIndexes = [
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i] != matchedKeyword) i,
    ];
    if (candidateIndexes.isEmpty) return null;

    String titleExcluding(Set<int> nameIndexes) {
      final rest = [
        for (var i = 0; i < tokens.length; i++)
          if (!nameIndexes.contains(i)) tokens[i],
      ];
      return rest.isEmpty ? matchedKeyword : rest.join(' ');
    }

    // "전무이사"처럼 직함 키워드가 다른 글자와 붙어 하나의 토큰을 이루면
    // ("전무이사 김철수"에서 매칭된 키워드는 "이사"), 그 토큰 자체가
    // 우연히 한글 2~4자라 이름 모양과 구분이 안 된다 — 매칭된 키워드를
    // 부분 문자열로 포함하는 토큰은 이름 후보에서 제외해 오배정을 막는다.
    bool looksLikeLeftoverTitleFragment(String token) =>
        token.contains(matchedKeyword);

    // 이름이 **한 줄 안에서 갈라져** 나오는 경우를 먼저 본다 — 부서·직함이
    // 이름과 같은 줄에 인쇄된 명함에서 OCR이 이름 중간을 띄어 읽는다
    // (card_128 `수석 정현 규` — 실제 이름은 `정현규`). 예전에는 첫 후보
    // 토큰(`정현`)만 보고 이름으로 써서 마지막 글자를 직함 칸에 흘렸다
    // (사용자 제보: "직함에 이름의 마지막 글자 '규'가 들어감").
    //
    // 후보 토큰 맨 앞부터 **순수 한글 토큰이 연속되는 만큼** 이어붙여 보고,
    // 그 결과가 사람 이름 모양이면(성 1자 + 이름 2자) 그 구간 전체를 쓴다.
    // 아니면 아래 기존 규칙으로 넘어간다 — `디지털 커뮤니케이션 파트`처럼
    // 부서명이 이어지는 줄은 여기서 걸러진다.
    final runIndexes = <int>{};
    final runBuffer = StringBuffer();
    for (final idx in candidateIndexes) {
      if (idx != candidateIndexes.first && !runIndexes.contains(idx - 1)) break;
      final token = tokens[idx];
      if (looksLikeLeftoverTitleFragment(token)) break;
      if (!_hangulOnlyRegExp.hasMatch(token)) break;
      runBuffer.write(token);
      runIndexes.add(idx);
    }
    if (runIndexes.length >= 2 &&
        _koreanNameRegExp.hasMatch(runBuffer.toString()) &&
        _hangulNameLooksReal(runBuffer.toString())) {
      return (name: runBuffer.toString(), title: titleExcluding(runIndexes));
    }

    final firstIdx = candidateIndexes.first;
    if (!looksLikeLeftoverTitleFragment(tokens[firstIdx]) &&
        _koreanNameRegExp.hasMatch(tokens[firstIdx])) {
      return (name: tokens[firstIdx], title: titleExcluding({firstIdx}));
    }

    // "윤 덕 현"처럼 한 글자씩 띄어 쓴 이름 — 후보 토큰 맨 앞부터 순수
    // 한글 한 글자짜리가 연속되는 만큼 이어붙인다.
    final consumed = <int>{};
    final buffer = StringBuffer();
    for (final idx in candidateIndexes) {
      if (tokens[idx].length == 1 &&
          _singleHangulRegExp.hasMatch(tokens[idx])) {
        buffer.write(tokens[idx]);
        consumed.add(idx);
      } else {
        break;
      }
    }
    if (consumed.length >= 2 && buffer.length >= 2 && buffer.length <= 4) {
      return (name: buffer.toString(), title: titleExcluding(consumed));
    }

    final lastIdx = candidateIndexes.last;
    if (!looksLikeLeftoverTitleFragment(tokens[lastIdx]) &&
        _koreanNameRegExp.hasMatch(tokens[lastIdx])) {
      return (name: tokens[lastIdx], title: titleExcluding({lastIdx}));
    }
    return null;
  }

  /// **조직 단위**를 가리키는 영문 낱말 — 회사명이 아니라 부서다.
  ///
  /// ⚠️ [_orgWords]보다 **좁다.** 저쪽은 사람 이름을 가리는 목록이라
  /// `Solutions`·`Systems`·`Technologies`가 들어 있는데, **그런 낱말은 회사
  /// 이름에 흔하다**(`ABC Solutions Inc`). 회사명을 가릴 때 그 목록을 쓰면
  /// **멀쩡한 회사명이 부서로 밀린다.**
  static const _orgUnitWords = {
    'team', 'division', 'department', 'dept', 'unit', 'section',
    'headquarters', 'branch',
  };

  static bool _looksLikeDeptOrTagline(String line) {
    final trimmed = line.trim();
    // 🚨 `Global Sales Division`처럼 **영문 조직 단위**로 끝나는 줄은 부서다
    //    (2026-08-29). 예전에는 그 줄이 **이름 칸에 들어가는 바람에** 회사명
    //    자리를 안 뺏었을 뿐이고, 이름 규칙을 고치자 회사명으로 흘러갔다.
    final hasOrgUnitWord = trimmed
        .split(RegExp(r'\s+'))
        .any((w) => _orgUnitWords.contains(w.toLowerCase().replaceAll(RegExp(r"[.'-]"), '')));
    final endsWithDeptSuffix =
        hasOrgUnitWord || _departmentSuffixes.any(trimmed.endsWith);
    // 슬로건/캐치프레이즈는 문장 형태라 공백으로 나눈 단어 수가 많은
    // 편이다("국민 맞춤형 복지를 실현하는 디지털 플랫폼 전문기관" = 7단어).
    // 회사명은 보통 짧아서 이 기준으로 어느 정도 구분된다.
    final wordCount = trimmed.split(RegExp(r'\s+')).length;
    return endsWithDeptSuffix || wordCount >= 4;
  }

  /// 로고 그래픽을 ML Kit이 짧은 알파벳 조각("DA", "A" 등)으로 잘못 읽는
  /// 경우가 실제 명함(Sovargen)에서 확인됐다. 같은 카드를 다시 스캔해도
  /// OCR이 줄을 나누는 방식이 매번 똑같지 않아서(실기기에서 확인 —
  /// "이정현 DA Sovargen"이 한 줄로 붙을 때도, "DA"와 "Sovargen"이 서로
  /// 다른 줄로 인식될 때도 있었다) 줄 결합 형태에 기대지 않고, 아주 짧은
  /// (2자 이하) 후보는 로고 잡음일 가능성이 높다고 보고 후순위로 미룬다.
  static bool _looksLikeLogoNoise(String line) => line.trim().length <= 2;

  /// 이 줄의 전화번호가 팩스 번호로 보이는가. "fax"/"팩스" 라벨이 있고, 같은
  /// 줄에 전화("tel"/"전화"/"phone") 라벨이 함께 있지는 않을 때만 팩스로
  /// 판단한다 — 한 줄에 대표전화와 팩스가 같이 있으면(드묾) 기존처럼 앞선
  /// 번호를 사무실 전화로 쓴다.
  /// 구분자 — 라벨과 번호 사이에 흔히 끼는 것들.
  static final _labelGapRegExp = RegExp(r'[\s.:()\-]');
  static final _letterRegExp = RegExp(r'[A-Za-z가-힣]');

  /// 번호 바로 앞에 **팩스 라벨**이 붙은 구간을 모은다.
  ///
  /// ⚠️ [_looksLikeFaxLine]은 **줄 전체**로 판단해서, `Tel 02-… Fax 070-…`처럼
  /// **한 줄에 전화와 팩스가 같이 있으면 통째로 꺼진다**(tel이 있으면 false).
  /// 103장에서 팩스를 놓친 16장이 **전부** 그 모양이었다(추가 282) — 줄 판단
  /// 하나로는 못 잡는다. 그래서 번호마다 제 라벨을 본다.
  static List<(int, int)> _faxLabeledRanges(
    String lookup,
    RegExp numberRegExp,
  ) {
    final out = <(int, int)>[];
    for (final m in numberRegExp.allMatches(lookup)) {
      if (_hasFaxLabelBefore(lookup, m.start)) out.add((m.start, m.end));
    }
    return out;
  }

  /// [start] 바로 앞이 팩스 라벨인가.
  static bool _hasFaxLabelBefore(String s, int start) {
    var i = start - 1;
    while (i >= 0 && _labelGapRegExp.hasMatch(s[i])) {
      i--;
    }
    if (i < 0) return false;
    final head = s.substring(0, i + 1);
    if (head.toLowerCase().endsWith('fax')) return true;
    if (head.endsWith('팩스')) return true;
    // 한 글자 `F`. 실측에서 **가장 흔한 모양**이다(놓친 16장 중 9장).
    //
    // ⚠️ 앞이 글자면 그건 낱말의 끝이지 라벨이 아니다 — `…of 02-…`처럼.
    // 이 저장소가 부분 문자열로 반복해 데인 자리라(추가 178·180·182·183)
    // 처음부터 경계를 건다.
    if (head.toLowerCase().endsWith('f')) {
      final prev = i - 1;
      return prev < 0 || !_letterRegExp.hasMatch(s[prev]);
    }
    return false;
  }

  static bool _looksLikeFaxLine(String line) {
    final lower = line.toLowerCase();
    final hasFax = lower.contains('fax') || line.contains('팩스');
    if (!hasFax) return false;
    final hasTel =
        lower.contains('tel') || lower.contains('phone') || line.contains('전화');
    return !hasTel;
  }

  /// leftover에서 회사명으로 쓸 줄을 고른다 — 부서명/슬로건, 로고 잡음처럼
  /// 보이는 줄은 다른 후보가 있으면 건너뛴다. 더 나은 후보가 전혀 없으면
  /// (안 뽑는 것보단 나으므로) 그래도 맨 앞 줄을 쓴다.
  static String? _pickCompanyFromLeftover(List<String> leftover) {
    if (leftover.isEmpty) return null;
    // P0③(테스터 B 제보, 2026-08-20) 재현: "회사명 입력란에 영문 이름이
    // 잘못 입력됨". leftover에 사람 영문 이름(Title Case)이 회사 영문명보다
    // 먼저 오면, 순서 때문에 이름이 회사명 자리를 차지했다. 아래 두
    // 우선순위 각각에 "사람 이름 모양이 아니면"을 먼저 시도하고, 그래도
    // 못 찾으면 원래 조건으로 되돌아간다 — 접미사 없는 진짜 회사명은 사람
    // 이름과 형태가 같아 구별이 안 되므로, 다른 후보가 없으면 그대로 쓴다.
    // 🚨 **같은 문자열이 두 번 인쇄돼 있으면 사람 이름이 아니라 로고다**
    //    (2026-08-30, 기기 줄 실측).
    //
    // ```
    // 0: LEWIS EXPERT        ← 크게 두 번 박혀 있다
    // 1: LEWIS EXPERT
    // 3: E.PD Kwak Yonghwan  ← 사람 이름은 한 번뿐이다
    // ```
    //
    // 📌 **#691 이 낸 회귀를 여기서 막는다.** 그 PR 은 `전영환 YOUNGWHAN CHUN`
    //    의 영문 이름을 회사 후보에서 미루려고 *「모든 낱말 3자 이상 + 하나가
    //    5자 이상」* 으로 선을 그었는데, `LEWIS`(5)·`EXPERT`(6) 가 그대로
    //    걸렸다. **선이 굵었다.**
    //
    // ⚠️ **선을 다시 긋는 대신 다른 근거를 하나 더 본다.** 길이로는 회사
    //    약자와 사람 이름을 못 가르지만, **되풀이**는 가른다 — 명함은 로고를
    //    두 번 박아도 이름은 한 번만 적는다.
    // ⚠️ **잇달아 되풀이될 때만 본다.** 표본 198장에서 되풀이가 있는 장은
    //    **4장뿐**인데, 그중 하나(`IMG_4540`)는 **명함 여러 장이 한 사진에 든
    //    것**이라 `문정순 이사`·`안해인` 같은 **사람 이름도 두 번** 나온다.
    //    로고는 위아래로 붙여 박고, 그렇게 떨어져 나오는 되풀이는 다른 명함의
    //    글자다. 그래서 **바로 이웃한 줄**일 때만 로고로 본다.
    final repeated = <String>{};
    for (var i = 1; i < leftover.length; i++) {
      final a = leftover[i - 1].trim();
      final b = leftover[i].trim();
      if (a.isNotEmpty && a == b) repeated.add(a);
    }
    bool notPersonName(String l) =>
        repeated.contains(l.trim()) || !_looksLikeEnglishPersonName(l);

    // 🚨 **`A | B`처럼 조직을 나란히 적은 줄은 회사 이름이 아니다**
    //    (2026-08-29, 실측). 후원사·계열사를 한 줄에 적은 것이지 그 사람의
    //    소속 하나를 가리키지 않는다.
    //
    // ✅ 실물: `FC서울프로축구단 | GS칼텍스서울kiXx배구단`이 회사 칸에
    //    들어갔다. **같은 명함 8번째 줄에 `GS 스포츠`가 있었다.**
    //
    // ⚠️ **버리지 않고 뒤로 민다** — 다른 후보가 없으면 이것이라도 쓴다.
    bool notPairedOrgs(String l) => !RegExp(r'\S\s*[|｜]\s*\S').hasMatch(l);

    // 🚨 **부서 모양인 줄은 회사가 아니다**(2026-08-30, 두 자 대조 실측).
    //
    // ```
    // MNO마케팅그룹 로밍마케팅팀        →  회사 칸   (정답 SK텔레콤)
    // 기업부설연구소                    →  회사 칸   (정답 (주)그린아이티코리아)
    // DT Optimization사업부 경영관리…   →  회사 칸   (정답 LG CNS)
    // ```
    //
    // 오늘 부서 쪽에서 잰 모양들(조직 계층 꼬리·업무 이름 끝·영문 조직 단위)을
    // **회사 후보 거르기에도** 쓴다.
    //
    // ⚠️ **법인 표기가 있으면 회사다** — `주식회사 디엠지그룹` 은 「그룹」으로
    //    끝나도 회사다(어제 [추가 591] 에서 반대 방향으로 겪은 자리다).
    //
    // 📌 **버리지 않고 뒤로 민다.** 다른 후보가 없으면 이것이라도 쓴다 —
    //    `notPersonName`·`notPairedOrgs` 와 같은 방식이다.
    bool notDeptShape(String l) {
      final t = l.trim();
      if (t.isEmpty || t.length > 40) return true;
      if (RegExp(r'\(주\)|\(유\)|㈜|주식회사|유한회사|사단법인|재단법인|'
              r'Inc\.|Corp|Ltd')
          .hasMatch(t)) {
        return true; // 법인 표기가 있으면 회사다
      }
      final hangulTail = RegExp(
        r'(팀|부|실|과|처|국|센터|본부|그룹|파트|연구소|부문|사업부|담당|'
        r'마케팅|영업|기획|개발|지원|운영|관리|전략)$',
      ).hasMatch(t);
      final latinTail = RegExp(
        r'(?<![A-Za-z])(Center|Centre|Group|Team|Division|Dept|Department|'
        r'Lab|Unit|Office)$',
        caseSensitive: false,
      ).hasMatch(t);
      return !(hangulTail || latinTail);
    }

    // 🚨 **고르기는 점수가 아니라 순서다**(2026-08-30, 자국 심어 실측).
    //
    // 아래 사슬은 `indexWhere` 라서 **줄 순서상 먼저 나온 것**을 집는다. 명함은
    // 로고를 맨 위에 박으므로, **영문 로고가 한글 회사명보다 늘 먼저 온다.**
    //
    // ```
    // card_123   후보 «SAMSUNG» «에스원»        →  SAMSUNG (정답 에스원)
    // ```
    //
    // ⚠️ **「한글을 먼저 본다」로 뒤집으면 안 된다** — 정답이 영문인 명함이
    //    실제로 있다(`Sovargen`·`ELANCER`·`911 COMPUTER`·`MILOTTIZ 현대백화점
    //    천호점`). 그래서 **버리지 않고 뒤로 민다** — `notPersonName`·
    //    `notPairedOrgs` 와 같은 방식이다.
    //
    // 📌 **뒤로 미는 것이 안전한 이유는 사슬이 이미 그물이기 때문이다.** 한글
    //    후보가 없으면 1순위가 통째로 비고, **2순위가 예전 그대로 집는다.**
    //    즉 **대안이 있을 때만** 순서가 바뀐다.
    bool notBareEnglishLogo(String l) {
      final t = l.trim();
      if (RegExp(r'[가-힣]').hasMatch(t)) return true; // 한글이 있으면 로고가 아니다
      // **두 번 박힌 것은 로고이면서 회사명이다**(`LEWIS EXPERT`, 추가 601).
      if (repeated.contains(t)) return true;
      // **낱말이 둘 이상이면 밀지 않는다.** 재 보니 여기가 급소였다 —
      // `LG CNS`·`TWINS LG`·`LEWIS EXPERT` 는 **진짜 영문 회사명**인데
      // 함께 밀려 네 장을 잃었다.
      // 낱말 사이에 쉼표·마침표가 낀 순수 영문은 로고 잡음이다
      // (`Souloreoul, FC SEOUL` — 실제로는 `Soul of Seoul` 로고다).
      if (RegExp(r'[A-Za-z][,.]\s').hasMatch(t)) return false;
      if (t.split(RegExp(r'\s+')).length != 1) return true;
      // 한 낱말이면서 **전부 대문자**일 때만 로고로 본다(`SAMSUNG`).
      return !RegExp(r'^[A-Z][A-Z0-9.&-]{2,}$').hasMatch(t);
    }

    // 1순위: 부서명·슬로건도 로고 잡음도 아니고, 회사명 모양인 줄
    // (+사람 이름 모양이 아닌 것을 먼저 본다).
    var idx = leftover.indexWhere(
      (l) =>
          !_looksLikeDeptOrTagline(l) &&
          !_looksLikeLogoNoise(l) &&
          _looksLikeCompanyName(l) &&
          notPersonName(l) &&
          notPairedOrgs(l) &&
          notBareEnglishLogo(l) &&
          notDeptShape(l),
    );
    if (idx == -1) {
      idx = leftover.indexWhere(
        (l) =>
            !_looksLikeDeptOrTagline(l) &&
            !_looksLikeLogoNoise(l) &&
            _looksLikeCompanyName(l) &&
            notPersonName(l) &&
            notDeptShape(l),
      );
    }
    if (idx == -1) {
      idx = leftover.indexWhere(
        (l) =>
            !_looksLikeDeptOrTagline(l) &&
            !_looksLikeLogoNoise(l) &&
            _looksLikeCompanyName(l) &&
            notDeptShape(l),
      );
    }
    // 2순위: 로고 잡음 조건만 완화한다(짧은 영문 브랜드명이 여기 걸린다).
    if (idx == -1) {
      idx = leftover.indexWhere(
        (l) =>
            !_looksLikeDeptOrTagline(l) &&
            _looksLikeCompanyName(l) &&
            notPersonName(l) &&
            notDeptShape(l),
      );
    }
    // ⚠️ **여기서부터는 부서 모양을 안 본다** — 조건을 통과하는 줄이 하나도
    //    없으면 **부서처럼 보이는 줄이라도** 쓴다. 회사 칸을 비우는 것보다
    //    낫다(`무지개청소년센터` 처럼 조직 이름으로 끝나는 **진짜 회사명**이
    //    실제로 있다).
    if (idx == -1) {
      idx = leftover.indexWhere(
        (l) => !_looksLikeDeptOrTagline(l) && _looksLikeCompanyName(l),
      );
    }
    // 못 찾으면 **비운다**(사용자 결정 2026-08-14). 예전에는 조건을 통과하는
    // 줄이 없으면 맨 앞 줄을 그냥 썼는데, 그래서 쓰레기를 하나 걸러낼 때마다
    // 다음 쓰레기가 회사명 자리를 채웠다(추가 182).
    if (idx == -1) return null;
    return leftover.removeAt(idx);
  }

  /// 직함 키워드도, 이름에서 갈라낸 나머지도 없을 때 쓰는 **가장 약한**
  /// 직함 폴백. leftover 맨 앞 줄을 검증 없이 그대로 썼던 것을 좁힌다
  /// (테스터 제보 2026-08-20, 뒷면에 회사 영문명만 있는 명함).
  ///
  /// ## 왜 "순수 영문이면 무조건 버린다"가 아니라 "전부 대문자만" 버리나
  ///
  /// 이 자리는 직함 키워드(`_titleKeywords`)로도, 이름-직함 분리로도 못
  /// 찾았을 때 오는 **마지막 자리**다. `_titleKeywords`에는 `CEO`·`Director`·
  /// `Manager`처럼 흔한 영문 직함이 이미 들어 있고, 그 매칭은 줄 전체를 보는
  /// `_containsCi`(부분 문자열, 대소문자 무시 — ⚠️ **경계가 필요하면
  /// `_containsWordCi`를 쓴다**, `test/device_reported_ocr_test.dart` 참고)라서
  /// **그 단어를 포함하는 영문
  /// 직함은 이미 titleLine으로 잡히고 이 폴백까지 내려오지 않는다**(`Sales
  /// Manager`가 실제로 그렇다). 그래서 이 폴백에 도달하는 순수 영문 줄은
  /// 두 갈래로 갈린다 — ① 키워드 목록에 없는 **정상 영문 직함**(`Business
  /// Development`, `Product Owner`, `Account Executive` 같은 것 — 목록을
  /// 아무리 넓혀도 다 못 담는다), ② 회사 영문명·브랜드 로고 잔재(`LG CNS`,
  /// `PRIME LOGISTICS`, `SOVARGEN`). **"순수 영문이면 무조건 버린다"는 ①까지
  /// 같이 버렸다** — 처음 버전이 그랬고, 정답지로 재보니 직함 미검출이
  /// 6→12건으로 두 배가 됐다(배포 전 발견, 병합 안 됨).
  ///
  /// 실측으로 갈리는 지점은 **표기 형태**다. 회사 영문명·로고는 명함에서
  /// 거의 항상 **전부 대문자**(로고체 표기)로 인쇄되고, 사람이 쓰는 영문
  /// 직함은 Title Case(`Business Development`)로 인쇄된다. 상세주소 잡음
  /// 제거(`_stripBrandNoiseFromAddressDetail`)가 이미 같은 신호(순수 로마자
  /// + 전부 대문자)로 회귀 없이(78% 그대로) 걸러낸 전례가 있다 — 그 판정을
  /// 여기로 옮겼다.
  ///
  /// ⚠️ **완벽하지 않다.** 실제로 전부 대문자로 인쇄된 영문 직함(`SALES
  /// MANAGER`처럼)이 있다면 이 필터에 걸린다. 다만 그런 직함은 대부분 키워드
  /// (`Manager`)를 포함해 이미 위 titleLine 경로가 먼저 잡으므로, 이 폴백까지
  /// 내려오는 "전부 대문자 + 키워드 없음" 조합은 실측상 거의 전부 회사·브랜드
  /// 잔재였다.
  ///
  /// ⚠️ **한글이 하나라도 있으면 그대로 쓴다** — 기존 동작을 바꾸지 않는다.
  /// 이 필터는 "순수 영문" 한 갈래만, 그중에서도 "전부 대문자"만 좁힌다.
  static String _pickWeakTitleFallback(List<String> leftover) {
    if (leftover.isEmpty) return '';
    final first = leftover.first;
    if (_hasHangul(first)) return leftover.removeAt(0);
    final letters = first.replaceAll(RegExp(r'[^A-Za-z]'), '');
    // 영문 글자가 하나도 없으면(숫자·기호뿐) 판단할 형태 신호가 없다 — 기존
    // 동작대로 버린다(전화번호 잔재 등이 직함이 되는 것을 막는다).
    if (letters.isEmpty) return '';
    if (letters == letters.toUpperCase()) return '';
    return leftover.removeAt(0);
  }

  /// 영문 줄이 **사람 이름 Title Case**로 보이는가(`Kim Do Young`) — 회사
  /// 영문명(`LG CNS`, 전부 대문자)과 구별하는 유일한 형태 신호. 한글이
  /// 섞이거나 단어 수가 2~4개 범위를 벗어나면 아니다.
  ///
  /// ⚠️ **한 단어는 보지 않는다.** `Fax.`·`Manager`처럼 Title Case인 라벨
  /// 잔재가 흔한데, 이런 한 단어짜리까지 "사람 이름"으로 보면 진짜 회사명
  /// 후보(`Fax.`가 card_107에서 우연히 회사 칸 정답으로 남아 있는 경우)가
  /// 밀려난다 — 103장 채점에서 실제로 -1을 냈다. 사람의 성명은 성+이름이
  /// 최소 두 조각이라는 원리적인 신호로 좁혔다.
  ///
  /// ⚠️ 접미사 없는 진짜 회사명이 Title Case로 인쇄되면(드묾) 이 검사에도
  /// 걸린다 — 텍스트 형태만으로는 회사 영문명과 사람 영문 이름을 완전히
  /// 못 가른다(2026-08-20 실측 결론). 그래서 이 값은 **후보가 여럿일 때
  /// 우선순위를 정하는 데만** 쓴다. 후보가 하나뿐이면 이 값과 무관하게
  /// 그대로 쓴다.
  /// 조직·부서를 가리키는 영문 낱말. **하나라도 들어 있으면 사람 이름이
  /// 아니다**(2026-08-29, 52장 실측).
  ///
  /// 🚨 `Innovation Team`·`Marketing Division`이 **「대문자로 시작하는 두
  /// 낱말」이라는 조건만으로 사람 이름으로 통과**해 이름 칸에 들어갔다.
  ///
  /// ⚠️ **빈 칸이 낫다.** 이름 칸에 부서명이 들어가면 **채워진 것처럼 보여**
  /// 이용자가 못 알아챈다 — 이 저장소의 *"가짜 데이터를 만들지 않는다"*와
  /// 같은 자리다.
  static const _orgWords = {
    'team', 'teams', 'division', 'department', 'dept', 'group', 'center',
    'centre', 'office', 'unit', 'lab', 'labs', 'institute', 'solution',
    'solutions', 'marketing', 'sales', 'innovation', 'consulting',
    'partners', 'technologies', 'systems', 'service', 'services',
    'management', 'research', 'development', 'studio', 'holdings',
    'ventures', 'capital', 'company', 'corporation',
  };

  static bool _looksLikeEnglishPersonName(String line) {
    if (_hasHangul(line)) return false;
    final words = line
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 2 || words.length > 4) return false;
    if (words.any(
      (w) => _orgWords.contains(
        w.toLowerCase().replaceAll(RegExp(r"[.'-]"), ''),
      ),
    )) {
      return false;
    }
    if (words.every((w) => RegExp(r"^[A-Z][a-z.'-]*$").hasMatch(w))) return true;

    // 🚨 **전부 대문자로 인쇄한 영문 이름**(2026-08-29, 기기 제보).
    //
    // ```
    // 명함 줄   전영환 YOUNGWHAN CHUN
    // 회사 칸   YOUNGWHAN CHUN          ← 같은 줄의 영문 이름이 회사가 됐다
    // ```
    //
    // ⚠️ **`LG CNS` 를 사람 이름으로 읽으면 안 된다.** 갈림길은 **낱말 길이**다
    //    — 회사 약자는 짧고(`LG`·`CNS`·`SK`), 사람 이름은 길다
    //    (`YOUNGWHAN`·`CHUN`). 그래서 **모든 낱말이 3자 이상이고 그중 하나가
    //    5자 이상**일 때만 사람 이름으로 본다.
    //
    // 📌 이 판정은 **버리는 것이 아니라 미루는 것**이다. 다른 후보가 없으면
    //    그대로 회사로 쓴다 — 위 주석의 원칙 그대로다.
    if (words.every((w) => RegExp(r'^[A-Z][A-Z.-]{2,}$').hasMatch(w)) &&
        words.any((w) => w.replaceAll(RegExp(r'[^A-Z]'), '').length >= 5)) {
      return true;
    }
    return false;
  }

  /// 회사명으로 정한 값에서 **앞뒤에 붙은 군더더기**를 뗀다.
  ///
  /// 103장 전수 측정(추가 280)에서 회사 오류의 한 덩어리가 *"회사명은 맞게
  /// 골랐는데 앞뒤에 뭐가 붙어 있는 것"*이었다. 고르기를 다시 하는 것보다
  /// 훨씬 안전하다 — **이미 고른 값에서 빼기만 하므로, 못 고르던 것이
  /// 갑자기 다른 값으로 바뀌지 않는다.**
  static String _tidyCompany(String company) => _restoreCorpParen(
    _joinBrokenCompanySpaces(
      _stripCompanyTitleTail(
        _stripCompanyLogoPrefix(_stripOrphanContactLabel(company)),
      ),
    ),
  );

  /// 띄어쓰기 붙이기만 따로 부른다 — 지키기로 한 것(법인 표기·`(주) 잇팩`)을
  /// 검사로 고정하기 위해서다. 명함을 지어내면 다른 규칙에 가려 안 보인다.
  @visibleForTesting
  static String joinBrokenCompanySpacesForTesting(String company) =>
      _joinBrokenCompanySpaces(company);

  /// **회사명 안에서 벌어진 띄어쓰기를 붙인다**(2026-08-30, 추가 614).
  ///
  /// 부서 쪽의 `_tidyDepartment` 와 같은 모양인데, 회사 칸에는 없었다.
  ///
  /// ```
  /// 라움소프 트     →  라움소프트     (card_104)
  /// 라움 소 프트    →  라움소프트     (card_114)
  /// ```
  ///
  /// ⚠️ **한 글자 조각일 때만 붙인다.** 온전한 낱말 사이의 띄어쓰기는 명함에
  /// 그렇게 인쇄된 것이다 — `주식회사 디엠지그룹` 을 붙이면 틀린다. 그리고
  /// 정답지가 **띄어쓰기까지 그대로 요구하는 장이 있다**(`(주) 잇팩`).
  static String _joinBrokenCompanySpaces(String company) {
    final s = company.trim();
    if (!_hasHangul(s)) return s;
    // 법인 표기가 섞여 있으면 손대지 않는다 — 거기 띄어쓰기는 뜻이 있다.
    if (RegExp(r'\(주\)|\(유\)|㈜|주식회사|유한회사|사단법인|재단법인').hasMatch(s)) {
      return s;
    }
    // ⚠️ **정규식 되풀이로는 안 된다.** `라움 소 프트` 는 가운데가 한 글자라
    //    앞뒤 어느 쪽으로 붙여도 다음 짝이 안 걸린다. **낱말 단위**로 본다.
    final parts = s.split(RegExp(r'\s+'));
    final out = <String>[];
    // 📌 **한 글자를 붙였으면 그다음 조각도 붙인다.** 낱말 하나가 두 군데서
    //    끊긴 것이라(`라움 소 프트`), 한 번만 붙이면 `라움소 프트` 로 남는다.
    var justJoined = false;
    for (final part in parts) {
      final lone = part.length == 1 && RegExp(r'^[가-힣]$').hasMatch(part);
      final followsBreak = justJoined && RegExp(r'^[가-힣]').hasMatch(part);
      if ((lone || followsBreak) && out.isNotEmpty) {
        out[out.length - 1] = '${out.last}$part';
        justJoined = lone;
      } else {
        out.add(part);
        justJoined = false;
      }
    }
    final joined = out.join(' ');
    // **영문 머리와 한글 사이의 공백**도 붙인다 — `SK 텔레콤` → `SK텔레콤`.
    // 브랜드 접두는 회사명의 일부이고, 명함에는 붙여 인쇄돼 있다.
    return joined.replaceFirstMapped(
      RegExp(r'^([A-Za-z]{2,3})\s+([가-힣])'),
      (m) => '${m[1]}${m[2]}',
    );
  }


  /// 부서 값에서 **벌어진 끝 음절**을 붙인다 (2026-08-30, 기기 채점 실측).
  ///
  /// ```
  /// 매니지드운영본부 매니지드운영 팀  →  …매니지드운영팀
  /// ```
  ///
  /// ⚠️ **한 글자짜리 꼬리만** 붙인다. `사업 1팀` 의 `1팀` 은 두 글자라 그대로
  /// 둔다 — 명함에 그렇게 인쇄돼 있다.
  ///
  /// ## 🚨 여기서 **하지 않는 것** — 재고 물렸다
  ///
  /// 처음에는 *"맨 앞에 붙은 영문 한 낱말을 뗀다"* 도 넣었다. 옆 칸의 영문
  /// 이름(`Soon`)이 같은 줄로 읽힌 것을 치우려던 것이다. **재 보니 부서가
  /// 65% → 57% 로 떨어졌다.**
  ///
  /// ```
  /// ICT 사업본부        →  사업본부         ← 멀쩡한 부서를 깎았다
  /// AI 아키텍처팀        →  아키텍처팀
  /// Digital Business본부 →  Business본부
  /// ```
  ///
  /// **영문 낱말이 부서 이름의 일부인 경우가 훨씬 많다.** 이름 조각 한둘을
  /// 얻으려다 다섯을 잃는다. 그래서 넣지 않는다.
  static String _tidyDepartment(String department) {
    final s = department.trim();
    if (s.isEmpty) return s;
    return s
        .replaceFirstMapped(
          RegExp(r'(\S)\s+(팀|부|실|과|처|국)$'),
          (m) => '${m[1]}${m[2]}',
        )
        .trim();
  }

  /// 회사명에 딸려 온 **주인 잃은 연락처 라벨**을 뗀다 (2026-08-29, 기기 제보).
  ///
  /// ## 증상
  ///
  /// globe2030님이 폴드에서 명함 한 장을 스캔하고 *"회사명에 fax가 딸려
  /// 들어가네"* 라고 알려 주셨다.
  ///
  /// ```
  /// 명함 줄   RAUM   fax 031-###-####
  /// 회사 칸   RAUM fax          ← 번호는 뗐는데 라벨이 남았다
  /// ```
  ///
  /// ## 원인
  ///
  /// 전화·팩스 번호는 앞 단계에서 뽑아 가는데, **그 자리에 있던 라벨은 줄에
  /// 남는다.** `_isContactLabelResidue` 가 그런 줄을 버리기는 하지만 그건
  /// **글자가 거의 안 남는 줄**만이다 — `RAUM fax` 는 `RAUM` 이 남아 살아남고,
  /// 라벨을 단 채로 회사 칸까지 간다.
  ///
  /// 🚨 **맥에서는 안 보이던 결함이다.** 맥 Vision 은 `RAUM` 과 `fax …` 를
  /// 다른 줄로 가르는데 기기 ML Kit 은 한 줄로 묶는다. **줄 나눔이 다르면
  /// 다른 결함이 나온다** — 실기기로 되재야 하는 이유가 이것이다.
  ///
  /// ## ⚠️ 조건이 규칙의 절반이다
  ///
  /// 라벨을 그냥 지우면 **멀쩡한 회사명이 잘린다.** 추가 178·180 에서 반복해
  /// 겪은 함정이다(`SK telecom` 의 `tel`). 그래서 둘 중 하나일 때만 뗀다.
  ///
  /// - **끝에 붙어 있다** — `RAUM fax`
  /// - **번호가 빠져나간 자국(공백 두 칸 이상)이 있다** — `tel  fax  RAUM`
  ///
  /// 📌 `Tel Aviv Trading` 처럼 라벨이 **말 가운데 정상적으로 든** 이름은 둘 중
  /// 어느 조건에도 안 걸린다. 떼고 나서 글자가 2자 미만이면 원래 값을 돌려준다.
  static String _stripOrphanContactLabel(String company) {
    final hasGap = RegExp(r'\s{2,}').hasMatch(company);
    final tailLabel = RegExp(
      r'[\s|]+(TEL|FAX|PHONE|MOBILE|E-?MAIL|DIRECT|DIR|HP|CP)[.:]?$',
      caseSensitive: false,
    );
    var s = company;
    var prev = '';
    while (prev != s) {
      prev = s;
      s = s.replaceFirst(tailLabel, '');
    }
    if (hasGap) s = s.replaceAll(_contactLabelPattern, ' ');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    final letters = s.replaceAll(RegExp(r'[^가-힣A-Za-z]'), '');
    return letters.length >= 2 ? s : company;
  }

  /// OCR이 놓친 **여는 괄호를 되살린다** (`주)어디` → `(주)어디`, 추가 340).
  ///
  /// ⚠️ 자리를 바로잡는 것만으로는 부족했다. 실측에서 회사 줄을 제대로 고르고도
  /// **`(` 하나 때문에 계속 틀렸다고 세어졌다.** 고르기와 표기는 따로 손봐야 한다.
  ///
  /// **줄 맨 앞에서만** 고친다 — 문장 가운데 `주)`는 다른 뜻일 수 있다.
  static String _restoreCorpParen(String company) {
    final t = company.trim();
    for (final m in const ['주)', '재)', '유)', '사)']) {
      if (t.startsWith(m)) return '($t';
    }
    return company;
  }

  /// 회사명 앞에 남은 **짝 없는 닫는 괄호**를 뗀다
  /// (`)유에이엠코리아텍(주)` → `유에이엠코리아텍(주)`).
  ///
  /// ## ⚠️ 로고 글자는 **일부러 안 뗀다** — 재 보고 물린 것이다
  ///
  /// 처음에는 `GO 선호라이팅 (주)` → `선호라이팅 (주)`처럼 앞의 로고 토큰도
  /// 뗐다. `SK telecom`의 `SK`를 지우지 않으려고 *"뒤쪽에 회사 접미사가 있을
  /// 때만"*이라는 안전장치까지 걸었다. 그런데 103장으로 재 보니 **3장을 얻고
  /// 9장을 잃었다**(회사 64% → 60%).
  ///
  /// 원인은 파서가 아니라 **정답지였다. 로고를 회사명에 넣을지가 장마다
  /// 다르다.**
  ///
  /// ```
  /// card_23 · card_38   "SSiS 한국사회보장정보원"   ← 로고 포함
  /// card_125            "한국사회보장정보원"        ← 같은 기관인데 로고 제외
  /// KYWA 한국청소년활동진흥원(4장) · kmong (주) 크몽(2장) · DMP Company
  /// ```
  ///
  /// ⚠️ **어느 쪽으로 만들어도 한쪽은 틀린다.** 규칙을 더 정교하게 짜서 풀
  /// 문제가 아니라, **정답지에서 로고를 어떻게 적을지 먼저 정해야** 하는
  /// 문제였다.
  ///
  /// ## ✅ 사용자 확정 (2026-08-17) — **인쇄된 그대로 넣는다**
  ///
  /// 그래서 이 함수는 **로고 글자를 떼지 않는다.** 위 검사 둘이 그것을
  /// 고정한다. ⚠️ **다시 떼도록 고치지 말 것.**
  ///
  /// 정답지도 그 규칙으로 맞췄다. 어긋난 행은 **하나뿐이었다**(card_125).
  ///
  /// 📌 사진 석 장을 직접 보고 알게 된 것 — 사용자가 실제로 적용해 온 기준은
  /// *"인쇄된 그대로"*보다 정확하다. **글자로 인쇄된 이름은 넣고, 그림 로고를
  /// OCR이 글자로 잘못 읽은 것은 안 넣는다.**
  ///
  /// ```
  /// card_13   `sto` 그림 로고 → OCR이 "std"로 읽음 → 정답 `서울관광재단`
  /// card_65   `sh`  그림 로고 → OCR이 "GO"로  읽음 → 정답 `선호라이팅 (주)`
  /// card_125  `SSiS` 글자 이름                     → 정답에 포함
  /// ```
  ///
  /// ⚠️ **파서는 이 둘을 구분할 수 없다.** 그림 로고를 잘못 읽은 것이나 진짜
  /// 이름이나, 파서에는 똑같은 글자로 도착한다. 그러니 "떼기"로는 풀 수 없다.
  /// 남은 오류(`GO`·`std`를 회사명으로 **골라 버리는** 경우)는 떼기가 아니라
  /// **고르는 순서** 쪽 문제다.
  ///
  /// ---
  ///
  /// ## 🔻 2026-08-18 — **조건을 붙여 되살렸다** (사용자 확정, 추가 318)
  ///
  /// ⚠️ **위 "다시 떼도록 고치지 말 것"을 지우지 않는다.** 그때의 판단은
  /// 그때 근거로는 옳았다. 바뀐 것은 **근거**다.
  ///
  /// | | 2026-08-17 | 2026-08-18 |
  /// |---|---|---|
  /// | 정답지 | **장마다 로고 표기가 달랐다** | **99장 검수 완료, 통일됐다** |
  /// | 조건 | *"뒤에 회사 접미사가 있을 때"* | **접두 1~2자 + 뒤에 한글** |
  /// | 결과 | 3장 얻고 **9장 잃음** | **6장 얻고 0장 잃음**(56.6% → 62.6%) |
  ///
  /// 위 주석이 *"파서는 이 둘을 구분할 수 없다"*고 단정했는데, **구분되는
  /// 근사 신호가 있었다.** 99장으로 재 보니 이렇게 갈렸다:
  ///
  /// ```
  /// 떼야 하는 것   E(1자) · GO(2자)          → 뒤가 한글   (그림 로고 오독)
  /// 두어야 하는 것 DMP · KYWA · SSiS(3~4자)              (글자로 인쇄된 이름)
  ///              SK(2자)                    → 뒤가 영문 telecom
  /// ```
  ///
  /// **길이 상한(2자)과 "뒤에 한글" 조건이 그때는 없었다.** 그래서 `KYWA`까지
  /// 뗐고 9장을 잃었다.
  ///
  /// ⚠️ **이 둘은 안전장치이지 장식이 아니다.** 상한을 3자로 넓히면 `DMP`·
  /// `SSiS`·`KYWA`가 걸리고, "뒤에 한글"을 빼면 `SK telecom`이 걸린다.
  /// **넓히기 전에 반드시 다시 재라** — 근거는 `ocr_truth.tsv`(검수 99장)다.
  ///
  /// 🚨 **위 문단은 2026-08-30에 실제로 다시 쟀다(추가 612). 아래를 먼저 읽어라.**
  /// 상한은 **풀었고**, 대신 **뒤가 공공기관 이름일 때만** 뗀다. 위 경고가
  /// 걱정한 `DMP`·`SK telecom` 은 그 조건에 안 걸려서 그대로 남는다.
  ///
  /// 📌 그리고 이 규칙은 **로고를 "떼는" 것이 아니라 OCR 오독을 걷어내는
  /// 것**이다. 사용자 원칙(*"인쇄된 그대로"*)은 그대로다 — 그림 로고가 글자로
  /// 잘못 읽힌 것은 애초에 인쇄된 글자가 아니다.
  ///
  /// ⚠️ **완벽하지 않다. 실기기에서 헛디딘 자리가 둘 있다**(card_210·216):
  ///
  /// ```
  /// [DT Optimization사업부 경영관리사] → [Optimization사업부 경영관리사업]
  /// ```
  ///
  /// `DT`는 회사(LG CNS)의 조직 이름 접두인데 **뒤에 한글이 섞여 있어** 걸렸다.
  /// 둘 다 **원래도 틀린 값**이라 점수는 안 움직였지만(정답은 `LG CNS`),
  /// **조건이 잡아내지 못하는 모양이 있다는 증거**다. 표본이 늘면 이런 자리가
  /// 손해로 바뀔 수 있으니, 재측정 때 **얻고 잃는 것을 항상 함께 보라.**
  /// 로고 떼기만 따로 부른다(2026-08-30, 추가 612).
  ///
  /// 📌 **명함 전체를 만들어 넣으면 이 규칙이 실제로 무엇을 하는지 안 보인다.**
  /// `GS 스포츠` 는 회사 키워드가 없어 **회사 후보로 뽑히지도 않아서**, 검사가
  /// 통과하든 실패하든 로고 규칙과는 상관이 없었다. 지켜야 할 것(브랜드 접두)을
  /// 고정하려면 이 함수를 바로 불러야 한다.
  @visibleForTesting
  static String stripCompanyLogoPrefixForTesting(String company) =>
      _stripCompanyLogoPrefix(company);

  /// **윗줄이 회사로 고른 그 줄인지** 본다(2026-08-30, 추가 612).
  ///
  /// 🚨 **글자 완전일치로 보다가 조용히 빗나갔다.** 아래 부서 규칙에는
  /// *"회사로 고른 줄은 절대 안 붙인다"* 는 방어가 `above != company` 로 들어
  /// 있었는데, **회사 칸은 그 줄을 그대로 쓰지 않는다** — 로고를 떼고 꼬리를
  /// 다듬어서 담는다. 그래서 같은 줄인데도 글자가 달라 방어가 새 나갔다.
  ///
  /// ```
  /// 줄        KSPO국민체육진흥공단
  /// 회사 칸   국민체육진흥공단        ← 로고를 뗐다
  /// 결과      부서 = 「KSPO국민체육진흥공단 가치센터팀」  ← 회사가 부서로 딸려 왔다
  /// ```
  ///
  /// 📌 **증상은 부서 칸에서 보였고 원인은 회사 칸에 있었다.** 두 장을 잃고서
  /// 자국을 심어 보니, 부서는 처음부터 `가치센터팀` 으로 옳게 집혀 있었고
  /// **그 뒤에 윗줄이 붙는 자리**가 범인이었다.
  ///
  /// 그래서 **띄어쓰기를 지우고 감싸는 관계까지** 본다. 다른 조직인
  /// `서울컨벤션뷰로`(회사는 `서울관광재단`)는 어느 쪽으로도 안 걸린다.
  static bool _isSameOrg(String line, String company) {
    if (company.isEmpty || line.isEmpty) return false;
    final a = line.replaceAll(RegExp(r'\s'), '');
    final b = company.replaceAll(RegExp(r'\s'), '');
    if (a.isEmpty || b.isEmpty) return false;
    return a == b || a.endsWith(b) || b.contains(a);
  }

  static String _stripCompanyLogoPrefix(String company) {
    final trimmed = company.trim().replaceFirst(RegExp(r'^[)\]}·|]+\s*'), '');

    // 🚨 **190장 자에서 위 주석이 말한 「다시 잴 때」가 왔다**(2026-08-30, 추가 612).
    //
    // 위에서 `KYWA`·`SSiS` 를 **일부러 남겼다** — 99장 자에서는 그것이 옳았다.
    // 그런데 표본이 190장으로 넓어지자 **같은 모양이 여섯 장** 나왔고, 정답지는
    // 전부 **떼라**고 했다.
    //
    // ```
    // KYWA 한국청소년활동진흥원  →  한국청소년활동진흥원
    // KSPO국민체육진흥공단       →  국민체육진흥공단      (띄어쓰기가 없다)
    // SSiS 한국사회보장정보원    →  한국사회보장정보원
    // ```
    //
    // ⭐ **가르는 신호는 「앞이 몇 자냐」가 아니라 「뒤가 무엇이냐」였다.**
    // 뒤가 **공공기관 이름 꼬리**로 끝나면 그 이름 자체가 온전한 회사명이고,
    // 앞의 영문은 로고다. 이 조건이면 길이 상한을 풀어도 안전하다 —
    // `GS 스포츠`·`SK 텔레콤`·`AXA 손해보험` 은 꼬리가 안 걸린다.
    //
    // ⚠️ **꼬리에 「보험」·「은행」·「전자」를 넣으면 안 된다.** 그것들은 앞의
    //    영문이 **회사명의 일부**인 자리다(`AXA손해보험`·`NH농협손해보험`).
    //    넣은 것은 **기관 이름 끝에만 붙는 것**뿐이다.
    final mInst = RegExp(
      r'^([A-Za-z][A-Za-z&.\-]{1,5})\s*([가-힣][가-힣0-9]*'
      r'(?:진흥원|정보원|진흥공단|공단|공사|재단|연합회|협회|진흥회|공제회))',
    ).firstMatch(trimmed);
    if (mInst != null) {
      return trimmed.substring(mInst.group(1)!.length).trim();
    }

    // **같은 로고가 두 번 찍힌다**(`LG LG CNS` → `LG CNS`).
    //
    // 아래 「앞 글자가 뒤에서 되풀이된다」 규칙이 이미 있는데, 그 규칙은 **뒤가
    // 한글일 때만** 닿는다(`SK SK 텔레콤`). 회사명이 영문이면 그 앞에서 막혔다.
    //
    // ⚠️ **되풀이는 낱말 단위로 본다.** 그냥 앞자리만 보면 `CO Cosmetics` 의
    //    `Cosmetics` 도 걸린다 — 뒤에 공백이나 끝이 와야 로고 중복이다.
    final mDup = RegExp(
      r'^([A-Za-z]{2,4})\s+(\1(?:\s|$).*)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (mDup != null) return mDup.group(2)!.trim();

    final m = RegExp(r'^([A-Za-z]{1,2})\s+(.{2,})$').firstMatch(trimmed);
    if (m == null) return trimmed;
    final head = m.group(1)!;
    final rest = m.group(2)!.trim();
    // 뒤가 한글이어야 한다. 영문 회사명(`SK telecom`)의 앞 토큰은 이름이다.
    if (!RegExp(r'[가-힣]').hasMatch(rest)) return trimmed;

    // 🚨 **두 글자 브랜드는 회사명의 일부다**(2026-08-29, globe2030님 제보).
    //
    // 예전에는 앞의 영문 1~2글자를 무조건 뗐다. 그래서 국내 대기업 이름이
    // 통째로 잘렸다 — **`GS 스포츠` → `스포츠`, `SK 텔레콤` → `텔레콤`,
    // `LG 전자` → `전자`.** 붙여 쓴 `GS스포츠`는 멀쩡했다.
    //
    // ✅ **100장으로 재 봤다**(`ocr_measure_mlkit_v2_2026-08-23.tsv`):
    // 그냥 끄면 **3장이 바뀌는데 하나는 나빠졌다** — `SK SK 텔레콤`처럼
    // **로고와 회사명이 둘 다 SK**인 줄에서 기존 규칙이 중복을 걷어내고
    // 있었다. 그래서 **끄지 않고 갈랐다.**
    //
    // ```
    // SK SK 텔레콤   앞 글자가 뒤에서 되풀이된다  → 뗀다(중복 로고)
    // GS 스포츠      되풀이되지 않는다            → 둔다(브랜드)
    // O 알로이스     한 글자                      → 뗀다(로고 오인식)
    // ```
    if (head.length < 2) return rest; // 한 글자는 로고 오인식으로 본다

    // 앞 글자가 뒤에서 되풀이된다 — 로고와 회사명이 같은 경우(`SK SK 텔레콤`).
    if (rest.toUpperCase().startsWith(head.toUpperCase())) return rest;

    // 회사 접미사가 있고 **접미사 말고도 이름이 남으면** 앞 글자는 로고다
    // (`GO 선호라이팅 (주)` → `선호라이팅 (주)`). 접미사밖에 없으면 앞 글자가
    // 회사명 자체다(`SK 주식회사`).
    // ⚠️ 접미사는 **괄호 형태나 온전한 낱말**만 본다. 예전 초안에서
    //    `(주|재|유|사)`를 맨글자로 찾았더니 **「주식회사」의 글자까지 지워**
    //    `SK 주식회사`가 `주식회사`로 잘렸다.
    final core = rest
        .replaceAll(RegExp(r'[(（]\s*(주|재|유|사)\s*[)）]'), '')
        .replaceAll(
          RegExp(r'주식회사|유한회사|재단법인|사단법인|㈜|Inc\.?|Co\.?|Ltd\.?', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[\s.,]'), '');
    final hasSuffix = core.length != rest.replaceAll(RegExp(r'[\s.,]'), '').length;
    if (hasSuffix && core.length >= 2) return rest;

    return trimmed;
  }

  /// **직함 끝에 붙어 온 이름을 떼어낸다**(2026-08-29, 94장 실측).
  ///
  /// ```
  /// 종괄매니저 김지 홍    →  직함 「종괄매니저」 · 이름 「김지홍」
  /// 파트너 변리사 김세진  →  직함 「파트너 변리사」 · 이름 「김세진」
  /// ```
  ///
  /// 🚨 명함이 **직함과 이름을 한 줄에** 찍고, 게다가 **이름의 자간을 벌려**
  /// 인쇄하면 인식기가 `김지`·`홍`으로 쪼갠다. 그 줄에 직함 키워드가 있어
  /// **줄 전체가 직함 칸으로 먹혔고**, 이름은 영영 못 찾았다.
  ///
  /// ⚠️ **직함 키워드가 앞쪽에 있어야** 뗀다. `수석 연구원`처럼 뒤 토막이
  /// 직함의 일부인 경우를 지키기 위해서다.
  static ({String title, String? name}) _splitTrailingName(String title) {
    final t = title
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (t.length < 2) return (title: title, name: null);
    if (!t.every((x) => RegExp(r'^[가-힣]+$').hasMatch(x))) {
      return (title: title, name: null);
    }
    for (var start = t.length - 1; start >= 1; start--) {
      final tail = t.sublist(start).join();
      if (tail.length < 2 || tail.length > 4) continue;
      if (!_koreanNameRegExp.hasMatch(tail)) continue;
      if (_isRejectedName(tail)) continue;
      if (!_hangulNameLooksReal(tail)) continue;
      // 🚨 **뒤 토막이 직함·부서 낱말이면 떼면 안 된다.** 초안이
      //    `수석 연구원`을 직함 `수석` + 이름 `연구원`으로 쪼갰다.
      //    테스트가 잡았다.
      if (_titleKeywords.any((k) => _containsCi(tail, k))) continue;
      if (_departmentSuffixes.any(tail.endsWith)) continue;
      if (RegExp(r'(부|팀|실|과|처|국|센터|본부|그룹|파트)$').hasMatch(tail)) {
        continue;
      }
      final headTokens = t.sublist(0, start);
      final head = headTokens.join();
      if (!_titleKeywords.any((k) => _containsCi(head, k))) continue;
      return (title: headTokens.join(' '), name: tail);
    }
    return (title: title, name: null);
  }

  /// **직함이 아닌 것을 직함 칸에서 걷어낸다**(2026-08-29, 94장 실측).
  ///
  /// ## 무엇이 들어와 있었나
  ///
  /// ```
  /// Yang, Se Yeol · Sim, Jeongwoo          영문 이름(성, 이름)
  /// 파트너 변리사 김세진 · Rim Sallem 림살렘   이름이 딸려 옴
  /// ###, Itaewon-ro, Yongsan-gu            주소
  /// 이주배경청소년지원재단.                   기관 이름
  /// ```
  ///
  /// 🚨 **빈 칸이 낫다.** 직함 칸이 채워져 있으면 이용자는 **맞게 읽혔다고
  /// 생각하고 넘어간다** — 이름 칸에서와 같은 판단이다.
  ///
  /// ⚠️ **멀쩡한 영문 직함은 건드리지 않는다** — `Deputy general manager`,
  /// `Team Leader`, `선임 Architect`는 그대로 둔다. 길이로 자르면 이것들이
  /// 죽는다.
  /// `_containsCi` 의 **낱말 경계판**.
  ///
  /// 부분 문자열로 보면 `ceonitios` 가 `CEO` 에 걸리고 `Development` 가 `Dev`
  /// 에 걸린다. 직함 키워드 매칭 전반을 바꾸면 지금 잘 되는 것이 흔들리므로,
  /// **경계가 필요한 자리에서만** 이것을 쓴다.
  static bool _containsWordCi(String haystack, String needle) => RegExp(
    '(?<![A-Za-z])${RegExp.escape(needle)}(?![A-Za-z])',
    caseSensitive: false,
  ).hasMatch(haystack);

  static bool _isNotTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return false;

    // 주소 — 도로명 영문 표기나 쉼표가 둘 이상 든 줄.
    if (RegExp(r'-(ro|gil|gu|dong|si)\b', caseSensitive: false).hasMatch(t)) {
      return true;
    }
    if (','.allMatches(t).length >= 2) return true;

    // 영문 이름 표기 `Yang, Se Yeol` — 쉼표 하나 + 낱말이 전부 대문자 시작.
    if (t.contains(',') && !_hasHangul(t)) {
      final words = t
          .replaceAll(',', ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.length >= 2 &&
          words.length <= 4 &&
          words.every((w) => RegExp(r"^[A-Z][a-z.'-]*$").hasMatch(w))) {
        return true;
      }
    }

    // 🚨 **쉼표로 끊긴 순수 영문 줄은 직함이 아니라 슬로건이다**(2026-08-29,
    //    실측). 명함 위쪽 슬로건이 직함 칸에 들어갔다 —
    //    `Soulor deoud, FC SEDUL`(「Soul of Seoul, FC SEOUL」의 오독).
    //
    // ⚠️ **조건을 「순수 영문에 직함 낱말이 없으면」으로 잡았다가 되물렸다.**
    //    그러면 `Business Development`·`Brand Experience`처럼 **키워드 목록에
    //    없는 정상 영문 직함**까지 지운다 — 이 저장소에는 그것을 지키는 검사가
    //    이미 있고(「키워드 목록에 없는 정상 영문 직함(Title Case)은 막지
    //    않는다」), 그 검사가 잡아냈다.
    //
    // 📌 남은 갈림길은 **쉼표**다. 직함은 한 덩어리로 인쇄되고, 쉼표로 끊기는
    //    영문 줄은 슬로건이거나 회사명이 뒤에 붙은 것이다. 위쪽에서 이미
    //    쉼표 2개 이상과 `Lastname, Firstname`을 걸러 왔는데, 이 줄은 쉼표가
    //    하나뿐이라 그 사이로 빠져나왔다.
    if (!_hasHangul(t) &&
        t.contains(',') &&
        !_titleKeywords.any((k) => _containsCi(t, k))) {
      return true;
    }

    // 🚨 **로고 글씨가 직함 칸에 든다**(2026-08-29, 기기 제보).
    //    `GI T ceonitios` · `GIT Clenikloeo` — 회사 로고를 OCR이 반쯤 읽은 것이다.
    //
    // 갈림길은 **전부 대문자인 토막**이다. 로고는 약자를 대문자로 박아 두고
    // (`GIT`·`GI T`), 사람이 쓰는 영문 직함은 그러지 않는다
    // (`Business Development`·`Brand Experience`).
    //
    // ⚠️ 직함 낱말이 하나라도 있으면 손대지 않는다 — `IT Manager`·`CEO Office`
    //    처럼 대문자 약자로 시작하는 **정상 직함**이 있다.
    //
    // 🚨 **여기서는 낱말 경계로 본다.** `_containsCi` 는 부분 문자열이라
    //    `ceonitios` 안의 `ceo` 에 걸린다 — 초안이 실제로 그래서 안 돌았고,
    //    이 파일이 :1897 주석에 이미 적어 둔 함정이었다.
    if (!_hasHangul(t) && !_titleKeywords.any((k) => _containsWordCi(t, k))) {
      final words = t
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final hasAllCapsToken = words.any(
        (w) =>
            RegExp(r'^[A-Z]{2,}$').hasMatch(w) ||
            RegExp(r'^[A-Z]$').hasMatch(w),
      );
      if (words.length >= 2 && hasAllCapsToken) return true;
    }

    // 기관·회사 이름이 통째로 들어온 경우.
    //
    // ⚠️ **「연구원」은 넣으면 안 된다.** 기관 접미사이면서 동시에 직함이다 —
    //    초안에 넣었더니 **`책임연구원`·`수석연구원`이 지워졌다**(94장
    //    측정에서 잡았다). 기관 하나를 놓치는 것이 흔한 직함 둘을 잃는
    //    것보다 낫다.
    final bare = t.replaceAll(RegExp(r'[.\s·•]'), '');
    if (RegExp(r'(재단|법인|협회|조합|공단|공사|주식회사)$').hasMatch(bare)) {
      return true;
    }

    return false;
  }

  /// **`/`·`|` 로 묶여 들어온 직함을 가른다**(2026-08-29, 52장 실측).
  ///
  /// ## 무엇이 문제였나
  ///
  /// 명함은 `직함 / 부서`나 `직함 / 영문직함`처럼 인쇄되는 일이 흔한데,
  /// **그 줄을 통째로 직함 칸에 넣고 있었다.**
  ///
  /// ```
  /// 부사장 / R&D Center
  /// 부장 / 정보안전부 / Department Manager
  /// 대표 ceo / HEE-JUNG J##
  /// ```
  ///
  /// ✅ **실측(52장, globe2030님 명함)**: 직함 칸은 **100% 채워졌는데 19장이
  /// 이상**했고, **그중 10장이 이 모양**이었다. 🚨 **채움률로는 안 보이는
  /// 결함**이다 — 이 저장소가 예전에 빠졌던 함정(추가 198)과 같다.
  ///
  /// 📌 그리고 **부서 칸은 21%만 차 있었다** — 잘려 나간 조각 상당수가
  /// 부서였다.
  ///
  /// ## 규칙
  ///
  /// ```
  /// 직함 키워드가 있는 첫 조각      → 직함
  /// 부서처럼 보이는 조각            → 부서(비어 있을 때만)
  /// 나머지                         → 버린다
  /// ```
  ///
  /// ⚠️ **직함 키워드가 아무 조각에도 없으면 손대지 않는다.** 가르다가
  /// 멀쩡한 값을 잃는 쪽이 더 나쁘다.
  static ({String title, String? department}) _splitTitleSegments(
    String rawTitle,
  ) {
    // 🚨 **영문 명함은 마침표를 칸막이로 쓴다**(2026-08-30, 실측).
    //    `BX Center. Business Manager` · `UX Group. Executive Leader`.
    //    ⚠️ **조직 꼬리 바로 뒤의 마침표만** 칸막이로 본다 — 그냥 `.` 을
    //       가르면 약어(`Ph.D`)와 문장이 다 쪼개진다.
    final title = rawTitle.replaceFirstMapped(
      RegExp(
        r'(?<![A-Za-z])(Center|Centre|Group|Team|Division|Dept|Department|'
        r'Lab|Unit|Office)\.\s+',
        caseSensitive: false,
      ),
      (m) => '${m[1]} | ',
    );
    if (!RegExp(r'[/|]').hasMatch(title)) return (title: title, department: null);
    final parts = title
        .split(RegExp(r'\s*[/|]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return (title: title, department: null);

    final titleParts = parts
        .where((p) => _titleKeywords.any((k) => _containsCi(p, k)))
        .toList();
    if (titleParts.isEmpty) return (title: title, department: null);

    // 🚨 **한글 직함이 둘 이상이면 가르지 않는다** — `이사|본부장`처럼 직급과
    //    직책을 나란히 찍은 명함이다. 하나만 남기면 **한쪽을 잃는다.**
    //
    // 🚨 **이 주석은 2026-08-30에 뒤집혔다 — 아래 문장은 낡은 것이다.**
    //    ~~영문은 다르다 — `대표이사 / CEO`는 같은 직함의 두 표기이므로
    //    한글 쪽만 남긴다.~~
    //
    //    **명함에는 그렇게 인쇄돼 있지 않다.** `card_02` 실물은 이름 아래 한
    //    줄로 `대표이사 | CEO` 이고, 정답지도 통째로 적고 있다. 지금은 **부서를
    //    못 얻으면 원래 직함을 그대로 돌려준다**(이 함수 끝의 `depts.isEmpty`).
    //    아래 검사(한글 직함 둘 이상)는 그대로 살아 있다 — `이사|본부장`처럼
    //    직급과 직책을 나란히 찍은 명함을 지킨다.
    if (titleParts.where((p) => RegExp(r'[가-힣]').hasMatch(p)).length >= 2) {
      return (title: title, department: null);
    }

    final head = titleParts.first;

    // ⚠️ 부서 판정을 **이 자리에서만** 넓힌다. `_departmentSuffixes`는 줄
    //    전체를 가릴 때 쓰는 목록이라 `정보안전부`·`영업부`·`기술지원팀`처럼
    //    흔한 부서명이 안 걸린다. 여기서는 **이미 「직함 / …」으로 묶여 온
    //    조각**이라 부서일 가능성이 훨씬 높다.
    //
    // ✅ 실측(52장): 넓히기 전에는 부서가 11 → 12장밖에 안 늘었다. 버려진
    //    조각 대부분이 이 모양이었다.
    bool deptLike(String p) =>
        p.length >= 2 &&
        (_departmentSuffixes.any(p.endsWith) ||
            RegExp(r'(부|팀|실|과|처|국|센터|본부|그룹|파트)$').hasMatch(p)) &&
        !_titleKeywords.any((k) => _containsCi(p, k));

    // 🚨 **두 단계로 인쇄된 부서를 한 조각만 집고 있었다**(2026-08-30, 실측).
    //
    // ```
    // 대리 / 구로지점 / 제1영업본부   →  부서 「제1영업본부」   ← 구로지점을 잃었다
    // ```
    //
    // `firstWhere` 가 **먼저 걸리는 하나만** 가져갔다. 기기 채점에서 부서가
    // 틀린 5장이 **전부 이 모양**이었다 — 회사의 조직 계층을 위에서 아래로
    // 나란히 찍은 것이라, 한 조각만 남기면 **어느 부서인지 알 수 없어진다.**
    //
    // ⚠️ **조직 꼬리를 이 자리에서만 넓힌다.** `지점`·`지사`·`부문`·`연구소`는
    //    줄 전체를 가릴 때 쓰기엔 위험한 낱말이지만, **이미 「직함 / …」으로
    //    묶여 온 조각**이라 부서일 가능성이 훨씬 높다(위 `deptLike` 와 같은
    //    이유다).
    bool orgLike(String p) =>
        p.length >= 2 &&
        p.length <= 20 &&
        !_titleKeywords.any((k) => _containsCi(p, k)) &&
        (deptLike(p) ||
            RegExp(r'(지점|지사|부문|사업부|연구소|본부|센터)$').hasMatch(p) ||
            // ⚠️ **접미사 없이 업무 이름으로 끝나는 부서**도 있다
            //    (`MICE마케팅`·`경영지원`). 실측에서 `MICE마케팅 | 주임` 이
            //    부서를 못 찾아 **통째로 직함에 남았다.**
            RegExp(
              r'(마케팅|영업|기획|개발|지원|운영|관리|전략|구매|물류|품질|'
              r'인사|총무|재무|회계|법무|홍보|교육|연구)$',
            ).hasMatch(p) ||
            // ⚠️ 영문 조직 단위(`R&D Center`·`UX Group`)도 부서다. 실측에서
            //    `부사장 / R&D Center` 가 통째로 버려졌다.
            //
            // 🚨 **`_orgUnitWords` 를 넓히지 않는다.** 그 목록은 회사 후보를
            //    거르는 데도 쓰여서, `Center`·`Group` 을 넣으면 *"… Group"*
            //    이라는 **회사명**이 부서로 끌려간다. 그래서 **이 자리에서만**
            //    꼬리를 본다.
            RegExp(
              r'(?<![A-Za-z])(Center|Centre|Group|Team|Division|Dept|'
              r'Department|Lab|Unit|Office)$',
              caseSensitive: false,
            ).hasMatch(p));

    final depts = parts.where((p) => p != head && orgLike(p)).toList();

    // 🚨 **부서를 못 얻었으면 가르지 않은 것과 같아야 한다**(2026-08-30, 실측).
    //
    // 예전에는 `head` 만 남기고 나머지를 **그냥 버렸다.** 그래서 부서가 아닌
    // 조각이 통째로 사라졌다 — 기기 채점에서 직함 회귀 셋이 전부 이 모양이다.
    //
    // ```
    // 대표이사 | CEO         →  「대표이사」        CEO 를 잃었다
    // 이사장/ President CEO  →  「이사장」          영문 표기를 잃었다
    // 대표/공인중개사         →  「대표」            자격을 잃었다
    // ```
    //
    // ⚠️ **옛 주석은 *"`대표이사 / CEO` 는 같은 직함의 두 표기이므로 한글 쪽만
    //    남긴다"* 였다 — 의도된 동작이었다.** 그런데 **명함에는 그렇게 인쇄돼
    //    있지 않다.** `card_02` 실물은 이름 아래 한 줄로 `대표이사 | CEO` 이고,
    //    `card_133` 의 `공인중개사` 는 **자격**이지 버릴 군더더기가 아니다.
    //    정답지도 통째로 적고 있다. **인쇄된 것을 그대로 담는 쪽으로 뒤집는다.**
    //
    // 📌 **가르기의 목적은 「부서를 건져 내는 것」이지 「직함을 줄이는 것」이
    //    아니다.** 건질 것이 없으면 손대지 않는다.
    // 🚨 **되돌려 줄 때 로고 잔재까지 함께 돌아왔다**(2026-08-30, 하루 대조 실측).
    //
    // 위 규칙은 「부서를 못 얻으면 손대지 않는다」인데, **손대지 않으면 로고가
    // 읽힌 조각도 그대로 남는다.**
    //
    // ```
    // 주임 |·SEÓUL·U     →  「주임 |·SEÓUL·U」   정답 「주임」
    // 차장 |:SEOUL·U     ·  과장 |:SEOUL·U  ·  본부장 | TS
    // ```
    //
    // 서울관광재단 옛 디자인의 `I·SEOUL·U` 가 직함 뒤에 붙어 들어온다. **하루를
    // 통째로 대조하기 전까지 어느 보고에도 안 나왔다** — 각 PR 이 자기 전후만
    // 봤기 때문이다.
    //
    // 📌 **가르는 신호는 「길이」가 아니라 「한글도 직함 낱말도 없는가」다.**
    //    `CEO`·`Section Manager` 는 직함 낱말을 갖고 있고, `공인중개사` 는
    //    한글이다. `SEOUL·U`·`TS` 는 둘 다 아니다.
    //
    // ⚠️ **버리는 것은 이 자리(부서를 못 얻은 줄)뿐이다.** 부서를 얻은 줄에서는
    //    아래 `otherTitles` 가 이미 직함 낱말로 거른다.
    bool looksLikeLogoNoise(String p) =>
        !RegExp(r'[가-힣]').hasMatch(p) &&
        !_titleKeywords.any((k) => _containsCi(p, k));

    if (depts.isEmpty) {
      final kept = parts.where((p) => !looksLikeLogoNoise(p)).toList();
      if (kept.isEmpty || kept.length == parts.length) {
        return (title: rawTitle, department: null);
      }
      return (title: kept.join(' / '), department: null);
    }

    // 🚨 **부서를 얻었을 때도 「직함의 나머지 반쪽」은 버리면 안 된다**
    //    (2026-08-30, 두 자 대조 실측).
    //
    // ```
    // 과장 / 정보안전부 / Section Manager
    //   →  직함 「과장」 · 부서 「정보안전부」   ← Section Manager 를 버렸다
    //   정답: 직함 「과장 / Section Manager」
    // ```
    //
    // [추가 600] 은 **부서를 못 얻었을 때**만 원래 직함을 지키도록 고쳤다.
    // 부서를 얻은 줄에서는 여전히 `head` 만 남기고 나머지를 버리고 있었다.
    //
    // 📌 **버릴 것과 남길 것을 가르는 근거는 「직함 낱말이 있는가」다.**
    //    `Section Manager` 는 직함 낱말(`Manager`)을 갖고 있으니 **직함의
    //    다른 표기**이고, `정보안전부` 는 부서다. 셋을 각자 제자리로 보낸다.
    final otherTitles = titleParts.where((p) => p != head).toList();
    final title2 = otherTitles.isEmpty
        ? head
        : ([head, ...otherTitles]).join(' / ');

    return (title: title2, department: depts.join(' / '));
  }

  /// 회사명 뒤에 붙은 **직함**을 뗀다 (`(주)제이투이 영업대표/부장` → `(주)제이투이`).
  ///
  /// 회사 접미사가 있는 줄은 `_trimCompanyAroundKeyword`를 거치는데, 그 함수는
  /// **25자 이하이거나 토큰이 4개 미만이면 자르지 않는다.** 짧은 회사명 뒤에
  /// 직함이 붙은 흔한 모양이 그 그물을 그대로 빠져나간다.
  ///
  /// ⚠️ **직함 칸은 건드리지 않는다.** 뗀 직함을 직함 칸으로 옮기고 싶지만,
  /// 그러면 이 변경이 회사뿐 아니라 직함 숫자까지 흔든다. 추가 278은 **회사
  /// 칸만** 손보기로 한 작업이다(직함은 오류의 42%가 OCR 오독이라 방법이
  /// 다르다 — 추가 280).
  static String _stripCompanyTitleTail(String company) {
    final tokens = company
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.length < 2) return company.trim();
    final idx = tokens.indexWhere(
      (t) => _titleKeywords.any((k) => _containsCi(t, k)),
    );
    // 맨 앞 토큰이 직함이면 회사명이 통째로 사라진다 — 그건 자르지 않는다.
    if (idx <= 0) return company.trim();
    final head = tokens.sublist(0, idx).join(' ');
    // ⚠️ 남는 쪽에 회사 접미사가 있어야 자른다. 없으면 회사명인지 확신할 수
    // 없고, 확신 없이 자르면 멀쩡한 값을 깎는다.
    final headHasSuffix = _companyKeywords.any((k) => _containsCi(head, k));
    return headHasSuffix ? head : company.trim();
  }

  /// 이 줄이 **회사명 모양**인지. 약한 폴백에서 후보를 거르는 데만 쓴다 —
  /// 회사 키워드로 확정된 줄은 이 검사를 거치지 않는다.
  ///
  /// 실측에서 회사명 칸에 들어갔던 것들(추가 181·182): `www.raumsoft.co.kr`,
  /// `Tel  Fax 070-7600-0812`, `.E-mail: … Fäx: Mobile : Address : 경기도 시…`,
  /// `대구 공장| 대구광역시 달서구 성서공단남로 37 …`.
  static bool _looksLikeCompanyName(String line) {
    final s = line.trim();
    if (s.isEmpty || s.length > 40) return false;
    // 이메일·URL은 회사명이 아니다(웹사이트 필드가 생기면 그쪽으로 간다).
    if (s.contains('@') ||
        RegExp(r'(https?://|www\.)', caseSensitive: false).hasMatch(s)) {
      return false;
    }
    // 숫자가 글자보다 많으면 주소·번호 줄이다.
    final digits = RegExp(r'\d').allMatches(s).length;
    final letters = s.replaceAll(RegExp(r'[^가-힣A-Za-z]'), '').length;
    if (letters < 2 || digits > letters) return false;
    return true;
  }

  /// `_parse`는 파일 내부 전용이라 다른 파일(테스트 포함)에서 직접 못
  /// 부른다 — ML Kit 인식 결과를 흉내 낸 줄 목록으로 필드 분류 규칙만
  /// 따로 검증할 수 있도록 테스트 전용 통로를 열어둔다. 실제 앱 코드에서는
  /// 쓰지 않는다.
  @visibleForTesting
  static OcrScanResult parseLinesForTesting(List<String> lines) =>
      _parse([for (final l in lines) lineBoxOf(l)], '');

  /// 글자 높이까지 넣어 파싱 규칙을 검증하는 테스트 통로 — 이름을 규칙으로
  /// 확신하지 못했을 때 글자 크기 폴백이 제대로 동작하는지 확인하는 용도.
  @visibleForTesting
  static OcrScanResult parseLinesForTestingWithHeights(
    List<({String text, double height})> lineData,
  ) => _parse([
    for (final l in lineData) lineBoxOf(l.text, height: l.height),
  ], '');

  /// 좌표까지 넣어 파싱 규칙을 검증하는 통로 — R-05(좌표 기반 분류)가 붙으면
  /// 여기로 검증한다. 위 두 통로는 좌표를 0으로 채우므로 **좌표 규칙을 못
  /// 본다.**
  @visibleForTesting
  static OcrScanResult parseLinesForTestingWithBoxes(
    List<OcrLineBox> lineData,
  ) => _parse(lineData, '');

  static OcrScanResult _parse(List<OcrLineBox> lineData, String imagePath) {
    // 자간을 벌려 인쇄한 글자를 먼저 붙인다. 모든 칸이 같은 규칙을 보게 하려고
    // 파싱 맨 앞에서 한 번만 정리한다(사용자 제안 2026-08-14).
    lineData = [
      for (final l in lineData)
        (
          text: _restoreBrokenPhones(
            _collapseCharSpacing(_stripLatinParallel(l.text)),
          ),
          height: l.height,
          top: l.top,
          left: l.left,
          width: l.width,
        ),
    ];
    lineData = _joinSplitPhoneNumbers(lineData);
    final lines = [for (final l in lineData) l.text];
    // 줄 텍스트 → 글자 높이. 같은 텍스트가 여러 번 나오면 가장 큰 값으로.
    // 이름 폴백에서 "가장 크게 인쇄된 줄"을 고르는 데 쓴다.
    final heightByText = <String, double>{};
    for (final l in lineData) {
      final prev = heightByText[l.text] ?? 0;
      if (l.height > prev) heightByText[l.text] = l.height;
    }
    // OCR이 "@" 앞뒤에 없던 공백을 끼워 넣는 경우가 실제 명함(그린아이티
    // 코리아)에서 확인됐다 — "alvinkim @greenitkr.com"처럼 공백이 있으면
    // 예전 정규식은 "@" 바로 앞에 아이디 글자가 붙어 있어야 해서 통째로
    // 매칭에 실패했다("3번을 스캔해도 매번 이메일이 안 들어옴" 재제보).
    // 공백을 허용하돼, 뽑아낸 값에서는 공백을 지우고 저장한다(아래
    // emailMatch 처리부).
    final emailRegExp = RegExp(
      r'[a-zA-Z0-9._%+-]+\s*@\s*[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    );
    // 지역번호를 괄호로 감싼 표기("(02)855-5900")가 실제 명함에서 흔해서,
    // 괄호 닫힘도 구분자로 허용한다 — 안 그러면 지역번호 뒤 ')'에서 매칭이
    // 끊겨 번호 전체를 못 찾는다.
    // 홈페이지. `http(s)://`와 `www.`로 시작하는 형태만 본다.
    //
    // ⚠️ **도메인처럼 보이는 것을 다 잡으면 안 된다.** 이메일의 뒷부분
    // (`hong@edenpat.com`)이 그대로 걸리고, 회사명에 점이 들어간 표기
    // (`A.I. 파트너스`)도 걸린다. 그래서 접두어가 확실한 것만 홈페이지로 본다.
    // 실제로 `_stripContacts`가 예전부터 이 두 형태만 걷어내 왔다.
    final websiteRegExp = RegExp(
      r'(https?://|www\.)[^\s]+',
      caseSensitive: false,
    );
    final mobileRegExp = RegExp(r'01[0-9][-.\s)]?\d{3,4}[-.\s]?\d{4}');
    // 02(서울)/031~069(지역 국번) 외에 070(인터넷전화)도 요즘 명함에 흔히
    // 쓰이는데 빠져 있었음 — 회사 전화번호가 있어도 인식이 안 되는 원인이었음.
    // ⚠️ 구분자에 **쉼표**를 넣는다. OCR이 점을 쉼표로 읽는 일이 잦다
    // (`Tel 02.3468,0020` — card_51). 예전에는 그 줄의 사무실 전화를 통째로
    // 놓쳤다.
    //
    // 그리고 **대표번호(15xx·16xx·17xx·18xx)**를 더한다. `0`으로 시작하지 않아
    // 위 규칙에 안 걸렸고, 실측 103장에서 두 장이 그것 때문에 사무실 전화가
    // 빈 값이었다(`T. 18779920` · `T1588-3112`).
    //
    // ⚠️ 앞에 숫자나 하이픈이 오면 **긴 번호의 일부**다(`010-1588-3112`).
    // 그때는 대표번호로 보지 않는다 — 이 저장소가 부분 문자열로 반복해 데인
    // 자리라(추가 178·180·182·183) 처음부터 막는다.
    // 🚨 **구분자를 한 글자만 보고 있었다**(2026-08-29, 94장 실측).
    //
    // `Fax 02) 12345678`처럼 **`)` 다음에 공백**이 오면 두 글자라 안 걸렸다.
    // 그래서 팩스가 빈 채로 저장됐다. `FAX : (02) 1234-5678`도 같다.
    //
    // 🚨 **`0505`도 빠져 있었다** — 안심번호·팩스 서비스에 흔한 대표번호다.
    //
    // ✅ **실측**: 명함에 fax 라벨이 있는 32장 중 **6장을 못 채웠는데**, 그중
    // **4장이 이 둘**이었다(나머지 2장은 번호가 아예 안 읽힌 것).
    final officeRegExp = RegExp(
      r'0(2|[3-6][0-9]|70|50[0-9])[-.\s,)]{0,2}\d{3,4}[-.\s,]?\d{4}'
      r'|(?<![\d-])1[5-8]\d{2}[-.\s,]?\d{4}',
    );
    // 국가번호(+82) 표기. 실제 명함에서 흔한데 앞의 `0`이 없어 위 두 규칙에
    // 통째로 안 걸렸다 — `+82-10-8977-9661`, `82.10.6355.6919` 둘 다 전화번호가
    // 하나도 안 잡혔다(103장 표본 card_01·card_02, backlog 추가 197).
    // 국내 표기로 바꾸면(`010-8977-9661`) 이후 분류는 그대로 쓸 수 있다.
    // `+82 (0)32-760-2037`처럼 국가번호 뒤에 **국내 접두 0을 괄호로 병기**하는
    // 국제 표기가 실제 명함에 있었다(card_05 — 이 표기 때문에 전화 세 개가
    // 전부 빈 값이었다). `(0)`을 선택 항목으로 허용한다.
    final intlPhoneRegExp = RegExp(
      r'\+?82[-.\s]?(?:\(0\))?[-.\s]?(1[0-9]|2|[3-6][0-9]|70)'
      r'[-.\s]?\d{3,4}[-.\s]?\d{4}',
    );
    // 광역시/도. 줄임말(충북)과 풀네임(충청북도)이 둘 다 명함에 쓰이는데,
    // 예전엔 줄임말만 있어서 "충청북도 청주시..."처럼 풀네임으로 쓴 주소를
    // 통째로 놓쳤다(2026-08-11 측정에서 주소가 최대 오인식 지점으로 확인됨).
    // 서울/강원/제주/세종은 풀네임이 줄임말을 접두어로 포함하므로 그대로 둔다.
    // 🚨 **주소 표시 글자는 「낱말 끝」에 있어야 한다**(2026-08-29, 실물 재현).
    //
    // 예전에는 `(로|길|동|구)`를 아무 자리에서나 봤다. 그래서 회사 이름 줄
    // **`FC서울프로축구단 | GS칼텍스서울Kixx배구단`**이 주소로 잡혔다 —
    // **「프로」의 `로`, 「축구단」의 `구`**에 걸린 것이다. 진짜 주소 줄이
    // 바로 아래 있었는데도 **먼저 걸린 쪽이 이겼다.**
    //
    // ✅ globe2030님 제보로 재현: 그 명함에서 **주소 칸에 회사 이름이** 들어가
    // 있었다. 직함·부서·휴대폰만 맞았던 이유도 같다 — 그 셋은 **키워드·숫자
    // 모양**으로 찾아 줄이 엉켜도 걸린다.
    //
    // 📌 그래서 뒤에 **공백·숫자·쉼표·마침표·괄호가 오거나 줄이 끝날 때**만
    // 주소 표시로 본다. 실제 주소는 `마포구 월드컵로 240`처럼 **뒤가 끊긴다.**
    final addressRegExp = RegExp(
      r'(서울|경기|인천|부산|대구|광주|대전|울산|세종|강원|충청북도|충청남도|충북|충남|전라북도|전라남도|전북|전남|경상북도|경상남도|경북|경남|제주)[^\n]*(로|길|동|구)(?=[\s\d,.()]|$)[^\n]*',
    );
    // 도/시 이름 없이 "강남구 테헤란로 123", "성남시 분당구 판교로 235"처럼
    // 시·군·구부터 시작하는 주소도 명함에 흔하다. 광역시/도 규칙만으로는
    // 통째로 놓쳐 사용자가 직접 입력해야 했다. 오탐을 줄이려고 "시/군/구 +
    // 로/길 + 숫자"가 한 줄에 다 있을 때만 주소로 본다(슬로건·부서명은 이
    // 조합을 거의 만들지 않는다). 광역시/도 규칙이 먼저 걸리면 그쪽을 쓰고,
    // 안 걸릴 때만 이 규칙으로 보완한다.
    final roadAddressNoProvinceRegExp = RegExp(
      r'[가-힣]+(시|군|구)\s+[^\n]*(로|길)\s*\d+[^\n]*',
    );
    // 우편번호가 주소와 다른 줄에 홀로 있는 경우("06234"만 있는 줄, 또는
    // "[06234]"/"(06234)"). 예전엔 주소 줄 앞에 붙은 5자리만 잡아서 별도
    // 줄이면 놓쳤다(측정에서 우편번호 인식률 33%로 가장 낮았다).
    final standalonePostalRegExp = RegExp(r'^[\[(]?(\d{5})[\])]?$');
    // 층/호/동호수 등 상세주소 패턴 — 명함에서 기본 주소와 같은 줄에 붙어 있기도
    //하고(예: "...테헤란로 123 5층 501호"), 별도 줄로 떨어져 있기도 하다
    // (addressRegExp는 로/길/동/구로 끝나는 줄만 보므로 "5층 501호"만 있는
    // 줄은 안 걸림 — 그대로 두면 leftover로 밀려 이름/회사명으로 잘못
    // 채워지는 문제가 있었다).
    final addressDetailRegExp = RegExp(
      r'(지하\s*\d*\s*층|\d+\s*층|B\d+F?|\d+F\b|\d+동\s*\d+\s*호|\d+\s*호)',
    );

    String? mobile;
    // 지금 [mobile]에 들어 있는 번호가 **사무실 라벨** 줄에서 왔는지.
    // 나중에 휴대폰 라벨이 붙은 다른 01X 번호가 나오면 자리를 바꾸기 위해 둔다.
    var mobileCameFromOfficeLabel = false;
    String? office;
    String? fax;
    String? website;
    String? email;
    String? address;
    String? addressDetail;
    String? postalCode;

    /// 주소와 한 줄로 뭉쳐 나온 이름 후보. 확정하지 않고 "빈자리 재검증"까지
    /// 들고 간다 — 자세한 이유는 아래 주소 처리부 주석 참조.
    String? nameHintBeforeAddress;

    /// 주소와 한 줄로 뭉쳐 나온 **회사명**. 주소 처리는 아래 회사 키워드
    /// 검사보다 먼저 돌고 그 줄을 `continue`로 끝내기 때문에, 여기서 미리
    /// 챙겨 두지 않으면 회사명이 통째로 사라진다.
    String? companyFromAddressLine;
    // 주소를 찾은 줄의 인덱스 — 콤마도 없고 같은 줄에 층/호 패턴도 없으면
    // 바로 다음 줄을 상세주소로 본다(명함에서 도로명 주소와 건물명/층수가
    // 서로 다른 줄로 나뉘는 흔한 레이아웃).
    int? addressLineIndex;
    // 주소 줄이 "…대왕판교로"처럼 로/길로 끝나고 건물번호가 아예 없이
    // 잘렸는지 표시한다 — 실제 명함(라움소프트)에서 도로명이 "…판교로"까지
    // 한 줄에 있고 건물번호("644번길 49")는 다음 줄로 넘어가는 레이아웃이
    // 확인됐다. 이 경우 이전엔 다음 줄 전체를 상세주소로 통째로 넘겨서
    // 정작 주소 자체엔 건물번호가 영영 안 들어가는 문제가 있었다.
    var addressLooksIncomplete = false;
    final remaining = <String>[];

    // 연락처를 걷어낸 나머지를 **같은 루프에 다시 넣기 위해** 복사본을 쓴다
    // (아래 `matchedContactField` 처리 참고).
    final work = [...lines];
    for (var lineIndex = 0; lineIndex < work.length; lineIndex++) {
      final line = work[lineIndex];
      // 우편번호만 홀로 있는 줄("06234", "[06234]")은 여기서 소비한다 —
      // 안 그러면 leftover로 밀려 이름/회사명 자리를 차지할 수 있다.
      final standalonePostal = standalonePostalRegExp.firstMatch(line.trim());
      if (postalCode == null && standalonePostal != null) {
        postalCode = standalonePostal.group(1);
        continue;
      }
      // "M 010-9347-5453  E cgu@exservice.co.kr"처럼 휴대폰과 이메일이 한
      // 줄에 같이 붙어 나오는 명함이 흔한데, 예전엔 이메일을 찾자마자 바로
      // 다음 줄로 넘어가서(continue) 같은 줄에 있는 휴대폰 번호를 놓쳤다
      // (실기기 스캔 결과로 확인됨 — 휴대폰 번호가 통째로 안 뽑힘). 이메일/
      // 휴대폰/사무실 전화는 서로 패턴이 겹치지 않으니 한 줄 안에서 셋 다
      // 따로 검사한다.
      var matchedContactField = false;
      // 매칭된 구간(시작,끝)을 모아뒀다가, 줄 전체가 아니라 그 부분만
      // 지우고 남는 텍스트가 있으면 버리지 않는다 — "상무(실장)
      // |MO10-6282-1922"처럼 직함이 전화번호와 한 줄에 붙어 나오면, 예전엔
      // 전화번호를 찾자마자 줄 전체를 버려서 직함이 통째로 사라졌다
      // (실제 명함으로 확인된 회귀).
      final matchedRanges = <(int, int)>[];

      final emailMatch = emailRegExp.firstMatch(line);
      if (email == null && emailMatch != null) {
        final rawEmail = emailMatch.group(0)!.replaceAll(RegExp(r'\s+'), '');
        // 🚨 **정규식이 「부분적으로」 성공한 경우를 여기서 잡는다**
        //    (2026-08-29, globe2030님 재제보).
        //
        //    `hong@company.co,kr` 처럼 **마지막 마침표만** 쉼표로 읽히면,
        //    정규식은 `hong@company.co` 까지 맞고 **쉼표에서 멈춘다.** 매칭이
        //    성공했으므로 아래 폴백이 돌지 않고, **`.kr` 이 잘린 채 저장된다.**
        //
        //    ⚠️ 앞서 넣은 복구(추가 589 이전)는 **정규식이 완전히 실패했을
        //    때만** 돌아서 이 경우를 못 잡았다 — **고친 것이 절반만 덮었다.**
        final around = _tokenAround(line, emailMatch.start);
        final repaired = around == null ? null : repairCommaEmail(around);
        final better = repaired != null && repaired.length > rawEmail.length
            ? repaired
            : rawEmail;
        email = _stripEmailLabelPrefix(better);
        if (better != rawEmail && around != null) {
          final at = line.indexOf(around);
          matchedRanges.add(
            at >= 0
                ? (at, at + around.length)
                : (emailMatch.start, emailMatch.end),
          );
        } else {
          matchedRanges.add((emailMatch.start, emailMatch.end));
        }
        matchedContactField = true;
      } else if (email == null && line.contains('@')) {
        // 🚨 정규식에 안 걸렸는데 `@`는 있다 — 인식기가 마침표를 쉼표로 읽은
        //    경우가 여기다(2026-08-29 사용자 제보). 되살릴 수 있으면 되살린다.
        for (final token in line.split(RegExp(r'\s+'))) {
          if (!token.contains('@')) continue;
          final repaired = repairCommaEmail(token);
          if (repaired == null) continue;
          email = _stripEmailLabelPrefix(repaired);
          final at = line.indexOf(token);
          if (at >= 0) matchedRanges.add((at, at + token.length));
          matchedContactField = true;
          break;
        }
      }
      // 홈페이지. ⚠️ **이메일을 먼저 처리한 뒤에 본다** — 순서가 바뀌면
      // `www` 없이 도메인만 있는 이메일 뒷부분과 겹칠 여지가 생긴다.
      //
      // ⚠️⚠️ **값만 담고 줄은 건드리지 않는다.** 여기서 구간을 지웠더니
      // 기존 검사 하나가 깨졌다 — `Www.HANBIT.CO.KR` 줄이 *"HANBIT은 로고지
      // 사람 이름이 아니다"* 라는 **근거로 쓰이고 있었고**, 줄을 걷어내자 그
      // 근거가 사라져 로고가 이름 칸에 들어갔다. 홈페이지 주소를 직함·회사
      // 칸에서 걷어내는 일은 예전부터 `_stripContacts`가 따로 하고 있으니,
      // 여기서 또 지울 이유가 없다.
      final websiteMatch = websiteRegExp.firstMatch(line);
      if (websiteMatch != null) {
        // 이메일 안에 들어 있는 도메인은 홈페이지가 아니다.
        final insideEmail =
            emailMatch != null &&
            websiteMatch.start >= emailMatch.start &&
            websiteMatch.end <= emailMatch.end;
        if (!insideEmail) {
          website ??= websiteMatch.group(0)!.replaceAll(RegExp(r'[,.;]+$'), '');
        }
      }
      // OCR이 전화번호 라벨("M "/"T ") 바로 뒤에 오는 숫자 0을 알파벳 O로
      // 잘못 읽는 경우가 실기기에서 확인됐다(예: "M 010-..." → "MO10-...").
      // 휴대폰/사무실 전화 패턴 매칭에만 쓰는 임시 정규화 버전을 따로 만들어
      // 적용한다 — 원본 line은 그대로 둬서 이메일/주소/이름 판별에는 영향을
      // 주지 않는다(글자 수가 같은 치환이라 매칭 위치는 원본과 동일하다).
      final phoneLookup = _normalizePhoneLookalikes(line);

      // ⚠️ **번호 대역이 라벨보다 확실하다.** `01X`는 통신사 휴대폰 대역이고
      // `02`·`0XX`·`070`은 유선/인터넷전화 대역이라 바뀔 수 없다. 반면 한국
      // 명함의 `T.`는 "사무실"이 아니라 그냥 "전화"의 관용 표기인 경우가 많다 —
      // 실제로 `T. 010-4729-3390` 하나만 적힌 명함이 있었다(크몽, 103장 표본).
      // 라벨을 무조건 따르게 했더니 그 휴대폰이 사무실 칸으로 갔다.
      //
      // 그래서 라벨은 **대역이 같아 구분이 안 될 때만** 쓴다 — 같은 명함에
      // `TEL. 010-…`(대표전화)과 `H.P 010-…`(휴대폰)이 함께 있는 경우다.
      // 예전에는 먼저 잡힌 대표전화가 휴대폰 칸을 차지하고 진짜 휴대폰은
      // 버려졌다(테스터 E-03).
      final isMobileLabel = _isMobileLabelLine(line);

      // 국가번호 표기를 먼저 처리한다 — 국내 표기로 바꾼 뒤 대역으로 분류한다.
      //
      // ⚠️ **한 줄에 여러 개**가 올 수 있다. 실제 명함에 전화·팩스·휴대폰이
      // `T+82 (0)32-760-2037 F+82 (0)32-760-2826 M+82 (0)10-8707-2411`처럼
      // 한 줄로 붙어 있었다(card_05). 예전에는 첫 번째만 처리하고 나머지는
      // 통째로 버렸다.
      //
      // 줄 전체로 팩스를 가리면(`_looksLikeFaxLine`) 이런 줄은 셋 다 팩스로
      // 보이므로, **각 번호 바로 앞 글자**로 가른다.
      final intlMatches = intlPhoneRegExp.allMatches(phoneLookup).toList();
      for (final m in intlMatches) {
        final domestic = _domesticFromIntl(m.group(0)!);
        if (domestic == null) continue;
        // 번호 바로 앞의 글자(공백·구두점은 건너뛴다)가 라벨이다.
        var i = m.start - 1;
        while (i >= 0 && RegExp(r'[\s.:()\-]').hasMatch(phoneLookup[i])) {
          i--;
        }
        final label = i >= 0 ? phoneLookup[i].toUpperCase() : '';
        final isFax =
            label == 'F' ||
            (intlMatches.length == 1 && _looksLikeFaxLine(line));
        matchedRanges.add((m.start, m.end));
        matchedContactField = true;
        if (isFax) {
          fax ??= domestic;
          continue;
        }
        if (domestic.startsWith('01')) {
          mobile ??= domestic;
        } else {
          office ??= domestic;
        }
      }

      final mobileMatch = intlMatches.isNotEmpty
          ? null
          : mobileRegExp.firstMatch(phoneLookup);
      if (mobileMatch != null) {
        final value = _normalizePhone(mobileMatch.group(0)!);
        if (mobile == null) {
          mobile = value;
          mobileCameFromOfficeLabel = isMobileLabel == false;
        } else if (value != mobile) {
          // 휴대폰 대역 번호가 둘째로 나왔다 — 이때만 라벨로 가른다.
          if (isMobileLabel == false && office == null) {
            office = value;
          } else if (isMobileLabel == true && mobileCameFromOfficeLabel) {
            // 먼저 잡힌 것이 사무실 라벨이었으면 자리를 바꾼다.
            office ??= mobile;
            mobile = value;
            mobileCameFromOfficeLabel = false;
          }
        }
        matchedRanges.add((mobileMatch.start, mobileMatch.end));
        matchedContactField = true;
      }
      // ⚠️ **번호마다 라벨을 따로 본다.** 줄 전체로 판단하면
      // `Tel 02-… Fax 070-…`처럼 한 줄에 둘 다 있는 명함에서 규칙이 꺼진다.
      final faxRanges = intlMatches.isNotEmpty
          ? const <(int, int)>[]
          : _faxLabeledRanges(phoneLookup, officeRegExp);
      if (faxRanges.isNotEmpty) {
        final r = faxRanges.first;
        fax ??= _normalizePhone(phoneLookup.substring(r.$1, r.$2));
        // ⚠️ 배정과 무관하게 구간은 지운다 — 안 지우면 남은 글자가 이름·회사
        // 자리로 흘러간다(추가 181에서 실제로 3장이 그렇게 망가졌다).
        matchedRanges.addAll(faxRanges);
        matchedContactField = true;
      }
      // 팩스로 가려낸 번호는 사무실 후보에서 뺀다.
      //
      // 📌 이게 없으면 **앞 번호가 깨진 줄에서 팩스가 사무실 칸을 차지한다** —
      // `T02-6360-69/LĻ F 02-6360-6930`(card_115)에서 앞 번호는 규칙에 안
      // 걸리고 뒤의 팩스가 첫 매칭이 된다. 사용자가 그 번호로 전화를 건다.
      RegExpMatch? officeMatch;
      if (intlMatches.isEmpty) {
        for (final m in officeRegExp.allMatches(phoneLookup)) {
          if (faxRanges.any((r) => r.$1 == m.start)) continue;
          officeMatch = m;
          break;
        }
      }
      if (officeMatch != null) {
        // 팩스 번호가 사무실 전화로 잘못 들어가는 문제(실제 명함에서 흔함 —
        // "fax 070-...", "팩스 02-..."). 팩스 라벨이 붙은 줄이면 사무실
        // 전화로 배정하지 않는다. 단 번호 자체는 줄에서 걷어내야 이름/회사로
        // 오분류되지 않으므로, 배정과 무관하게 매칭 구간은 지운다.
        if (_looksLikeFaxLine(line)) {
          // 팩스 줄이다 — 예전에는 배정하지 않고 **버렸다.** 이제 팩스 칸에
          // 담는다. 사무실 전화로는 여전히 넣지 않는다.
          fax ??= _normalizePhone(officeMatch.group(0)!);
        } else {
          office ??= _normalizePhone(officeMatch.group(0)!);
        }
        matchedRanges.add((officeMatch.start, officeMatch.end));
        matchedContactField = true;
      }
      if (matchedContactField) {
        // 뒤에서부터 지워야 앞쪽 구간의 인덱스가 안 밀린다.
        matchedRanges.sort((a, b) => b.$1.compareTo(a.$1));
        var remainder = line;
        for (final range in matchedRanges) {
          remainder = remainder.replaceRange(range.$1, range.$2, '');
        }
        remainder = remainder
            .replaceAll(RegExp(r'^[\s|:/,\-]+|[\s|:/,\-]+$'), '')
            .trim();
        // "M"/"T"/"F"/"E"처럼 전화·이메일 라벨로 쓰인 알파벳 한 글자가
        // 숫자 바로 앞에 공백 없이 붙어 있으면(정규식은 숫자만 매칭 구간에
        // 넣으므로) 구간을 지운 뒤에도 라벨 글자 혼자 남는다(실제 명함
        // "상무(실장) |MO10-6282-1922"에서 확인된 회귀 — title이
        // "상무(실장) |M"으로 지저분해짐). 단어 경계에 홀로 남은 경우만
        // 지운다.
        remainder = remainder.replaceAll(RegExp(r'\s*\b[MTFE]$'), '');
        remainder = remainder
            .replaceAll(RegExp(r'^[\s|:/,\-]+|[\s|:/,\-]+$'), '')
            .trim();
        if (remainder.isNotEmpty) {
          // ⚠️ 남은 부분을 **이 루프에 다시 넣는다.** 예전에는 곧바로
          // `remaining`으로 넘겨 버려서, 같은 줄에 함께 있던 **주소와 회사명이
          // 통째로 사라졌다** — 아래 주소·회사 검사는 이 루프 안에만 있기
          // 때문이다. 실측에서 연락처와 주소가 한 줄로 뭉친 명함이 여럿
          // 확인됐다(card_18·133 — 주소·회사명 모두 빈 값이었다).
          //
          // 무한 반복 걱정은 없다: 매칭 구간을 지운 뒤라 글자 수가 반드시
          // 줄어들고, 더 지울 것이 없으면 다음 검사로 내려간다.
          work[lineIndex] = remainder;
          lineIndex--;
        }
        continue;
      }

      // 광역시/도로 시작하는 주소를 먼저 보고, 없으면 "시/군/구 + 로/길 +
      // 숫자" 형태(도/시 생략 주소)로 보완한다.
      // 🚨 **부서 이름이 주소로 잡힌다**(2026-08-30, 코드에 자국을 남겨 찾음).
      //
      // ```
      // 서울컨벤션뷰로   ← 「서울」로 시작하고 「로」로 끝난다 → 주소로 인식
      // ```
      //
      // 그 줄이 **주소 칸을 차지해 버려서**, 진짜 주소 줄은 갈 곳이 없어
      // 「5층」이 들어 있다는 이유로 **상세주소에 통째로** 들어갔다.
      // **한 줄 때문에 주소·상세주소·우편번호 세 칸이 함께 틀렸다.**
      //
      // 📌 **가르는 근거는 숫자다.** 진짜 주소에는 건물번호나 우편번호가
      //    있고(`…청계천로85`·`03190`), 조직 이름에는 없다.
      // ⚠️ **시·도 이름이 진짜 주소의 시작인지도 본다.** `서울관광재단` 은
      //    `서울` 로 시작해서 거기서부터 매칭됐다 — 주소 칸에
      //    `서울관광재단 03190` 이 들어갔다. 진짜 주소는 시·도 뒤에 공백·숫자가
      //    오거나 `특별시`·`광역시`·`도`·`시`·`군`·`구` 가 붙는다.
      Match? provinceMatch = addressRegExp.firstMatch(line);
      if (provinceMatch != null &&
          _realProvinceStart.matchAsPrefix(line, provinceMatch.start) == null) {
        for (final p in _provinceHead.allMatches(line)) {
          if (_realProvinceStart.matchAsPrefix(line, p.start) == null) continue;
          final m = addressRegExp.matchAsPrefix(line, p.start);
          if (m != null) {
            provinceMatch = m;
            break;
          }
        }
        final pm = provinceMatch;
        if (pm == null ||
            _realProvinceStart.matchAsPrefix(line, pm.start) == null) {
          provinceMatch = null;
        }
      }
      // ⚠️ **숫자는 줄 전체에서 본다.** 매칭 구간만 보면 `13493 경기도 성남시
      //    분당구 대왕판교로`(우편번호가 매칭 **앞**에 있고 건물번호는 **다음
      //    줄**에 있다) 같은 줄이 통째로 떨어져 나간다 — 기존 검사가 그것을
      //    잡아 줬다.
      if (provinceMatch != null && !RegExp(r'\d').hasMatch(line)) {
        provinceMatch = null;
      }
      final addressMatch =
          provinceMatch ?? roadAddressNoProvinceRegExp.firstMatch(line);
      if (address == null && addressMatch != null) {
        // 주소 앞에 "06193 서울특별시..."처럼 우편번호(5자리)가 붙어 있으면
        // 뽑아낸다 — addressRegExp는 "서울" 등부터 매칭돼서 앞의 숫자는
        // 매칭 대상에 안 들어가므로 원래 줄에서 따로 확인해야 한다.
        // "(04933) 서울특별시..."처럼 괄호로 감싼 표기도 실제 명함(SSIS,
        // 한국사회보장정보원)에서 확인돼 괄호를 허용하도록 고쳤다 — 예전엔
        // 순수 5자리 숫자만 인정해서 괄호가 있으면 통째로 놓쳤다.
        final beforeAddress = line
            .substring(0, addressMatch.start)
            .trim()
            .replaceAll(RegExp(r'[()]'), '');
        if (postalCode == null && RegExp(r'^\d{5}$').hasMatch(beforeAddress)) {
          postalCode = beforeAddress;
        }
        // 우편번호가 주소 앞에 **다른 토큰과 섞여** 같은 줄에 있는 경우
        // (card_104: "…644번길 49, 13493 경기도 …"). 앞뒤가 숫자가 아닌
        // 정확히 5자리 독립 토큰만 받아, 전화·건물번호 조각을 우편번호로
        // 오인하지 않는다.
        if (postalCode == null) {
          final inlinePostal = RegExp(
            r'(?<!\d)\d{5}(?!\d)',
          ).firstMatch(beforeAddress);
          if (inlinePostal != null) postalCode = inlinePostal.group(0);
        }
        // 주소 앞에 남은 텍스트가 **사람 이름**인 경우가 실측 103장 중 7장에서
        // 확인됐다("박병훈 서울특별시 은평구 통일로 65길 26, 7층"). 예전에는
        // 우편번호가 아니면 통째로 버려서, 원문에 이름이 멀쩡히 있는데도 이름
        // 칸이 비었다(2026-08-14).
        //
        // ⚠️ 여기서 바로 이름으로 확정하지 않고 **힌트로만 보관**한다. 주소 앞에
        // 회사명이 오는 명함도 흔해서("한빛 서울시 강남구…"), 확정해 버리면
        // 회사명이 이름 칸에 들어간다. 아래 "빈자리 재검증"에서 회사명이
        // 정해진 뒤에, 이름 칸이 **비어 있을 때만** 쓴다.
        //
        // 괄호를 지우기 전 원문으로 검사하는 것이 중요하다 — "(주)한빛"은
        // 괄호를 지우면 "주한빛"이 되어 한글 3자 이름 규칙에 걸린다.
        final beforeAddressRaw = line.substring(0, addressMatch.start).trim();
        if (nameHintBeforeAddress == null && beforeAddressRaw.isNotEmpty) {
          final candidate = beforeAddressRaw.replaceAll(RegExp(r'\s+'), '');
          if (_koreanNameRegExp.hasMatch(candidate) &&
              !_isRejectedName(candidate)) {
            nameHintBeforeAddress = candidate;
          }
        }
        var matched = addressMatch.group(0)!.trim();
        // 주소 뒤에 **연락처 라벨이 이어지면 거기서 자른다.**
        //
        // 연락처를 걷어낸 나머지를 주소 검사에 다시 넣게 되면서(위 참고),
        // `…대왕판교로 e-mail mobile fax tel 사업1팀 대리 홍관표`처럼 라벨
        // 찌꺼기가 주소 뒤에 줄줄이 붙는 줄이 생겼다. 주소 정규식은 뒤에 뭐가
        // 오든 계속 먹기 때문에 그대로 주소 칸에 들어갔다(card_104·131).
        final labelCut = RegExp(
          r'\s(e-?mail|mobile|fax|tel|http|www\.|전화|팩스|이메일|휴대)',
          caseSensitive: false,
        ).firstMatch(matched);
        if (labelCut != null) {
          matched = matched.substring(0, labelCut.start).trim();
        }
        // 도로명 주소와 상세주소를 나누는 기준(우선순위 순):
        // 1. 콤마가 있으면 콤마 이전까지가 도로명 주소.
        // 2. 콤마가 없으면 "로/길/가 + 건물번호" 뒤에 공백과 함께 텍스트가
        //    더 있는지 본다 — 있으면 그 공백에서 나눈다(건물번호까지가
        //    도로명 주소, 그 뒤가 상세주소).
        // 3. 그 "로/길/가 + 건물번호"가 줄 끝이면(뒤에 아무 것도 없으면)
        //    이 줄 전체가 도로명 주소이고, 상세주소는 바로 다음 줄에서
        //    찾는다(아래 lineIndex == addressLineIndex + 1 로직).
        final commaIdx = matched.indexOf(',');
        if (commaIdx != -1) {
          addressDetail = matched.substring(commaIdx + 1).trim();
          matched = matched.substring(0, commaIdx).trim();
        } else {
          final roadNumberMatches = RegExp(
            r'(로|길|가)\s*\d+(?:-\d+)?',
          ).allMatches(matched).toList();
          if (roadNumberMatches.isNotEmpty) {
            final lastRoadNumber = roadNumberMatches.last;
            final afterNumber = matched.substring(lastRoadNumber.end).trim();
            if (afterNumber.isNotEmpty) {
              addressDetail = afterNumber;
              matched = matched.substring(0, lastRoadNumber.end).trim();
            }
            // afterNumber가 비어 있으면(줄 끝) 그대로 두고 다음 줄에서 찾는다.
          } else {
            // "로/길/가 + 숫자" 패턴 자체가 없는 드문 경우(예: 지번 주소)엔
            // 기존 층/호 패턴 백업으로 같은 줄 안에서 찾아본다.
            final detailInline = addressDetailRegExp.firstMatch(matched);
            if (detailInline != null) {
              addressDetail = matched.substring(detailInline.start).trim();
              matched = matched.substring(0, detailInline.start).trim();
            } else if (matched.endsWith('로') || matched.endsWith('길')) {
              // 건물번호 없이 도로명에서 줄이 끝났다 — 실제 명함(라움소프트,
              // "…대왕판교로")에서 건물번호("644번길 49")가 다음 줄로 넘어가는
              // 레이아웃이 확인됐다. 바로 아래에서 다음 줄이 숫자로 시작하면
              // 이어붙일 수 있게 표시만 해둔다.
              addressLooksIncomplete = true;
            }
          }
        }
        // 상세주소는 **층·호까지**만 남기고 뒤를 떼어낸다.
        //
        // 연락처를 걷어낸 나머지를 주소 검사에 다시 넣게 되면서, 주소 뒤에
        // 이어지던 이름·직함·회사명이 통째로 상세주소 칸에 들어가는 줄이
        // 생겼다(card_18의 상세주소가 `진양빌딩 5층 손연기 이사장/ … KYWA
        // 한국청소년활동진흥원`이었다). 떼어낸 꼬리는 버리지 않고 아래에서
        // 회사명 후보로 쓴다 — 실제로 그 안에 회사명이 있었다.
        var addressTail = '';
        if (addressDetail != null && addressDetail.isNotEmpty) {
          final floorMatches = RegExp(
            r'\d+\s*(층|호|동)',
          ).allMatches(addressDetail).toList();
          if (floorMatches.isNotEmpty) {
            var end = floorMatches.last.end;
            // 층·호 바로 뒤에 괄호로 감싼 건물명이 이어지면("2-1216호(가산동
            // 롯데아이티캐슬)") 그 괄호까지 상세주소로 본다 — 건물명은 상세주소의
            // 일부이지 떼어낼 꼬리가 아니다(card_101). 예전에는 층·호에서 잘라
            // 괄호 건물명을 통째로 버렸다.
            final paren = RegExp(
              r'^\s*\([^)]*\)',
            ).firstMatch(addressDetail.substring(end));
            if (paren != null) end += paren.end;
            if (end < addressDetail.length) {
              addressTail = addressDetail.substring(end).trim();
              addressDetail = addressDetail.substring(0, end).trim();
            }
          }
        }

        // 회사명이 주소와 **한 줄로 뭉쳐** 나오는 경우를 건진다.
        //
        // 주소 처리는 이 줄을 여기서 `continue`로 끝내기 때문에, 아래 회사
        // 키워드 검사까지 가지 못한다. 그래서 `(주)고든 08808 서울시 관악구
        // 승방1길 5, 소프트하우스 2층` 같은 줄에서 회사명이 통째로 사라졌다
        // (실측 card_31·129, 사용자 제보 "회사명 없음").
        //
        // 주소로 인식한 구간만 걷어내고 **앞뒤에 남은 텍스트**에 회사 키워드가
        // 있으면 그것을 회사명으로 쓴다. 키워드가 있을 때만 손대므로,
        // 관계없는 부스러기가 회사 칸에 들어갈 일은 없다.
        if (companyFromAddressLine == null) {
          final aroundAddress =
              '${line.substring(0, addressMatch.start)} '
                      '${line.substring(addressMatch.end)} $addressTail'
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
          final withoutContacts = _stripContacts(aroundAddress);
          final keyword = _companyKeywords.firstWhere(
            (k) => _containsCi(withoutContacts, k),
            orElse: () => '',
          );
          if (keyword.isNotEmpty) {
            final picked = _trimCompanyAroundKeyword(
              withoutContacts,
              keyword,
              always: true,
            );
            // 접미사만 덩그러니 남은 경우("주식회사")는 쓰지 않는다 — 회사명이
            // 아니라 접미사다. 실측 card_119에서 회사 칸이 `ALOYS`에서
            // `주식회사`로 나빠졌다.
            String lettersOf(String v) =>
                v.replaceAll(RegExp(r'[^A-Za-z가-힣]'), '');
            if (lettersOf(picked).length > lettersOf(keyword).length) {
              companyFromAddressLine = picked;
            }
          }
        }
        address = matched;
        addressLineIndex = lineIndex;
        continue;
      }
      // 도로명이 건물번호 없이 줄 끝에서 잘렸는데(addressLooksIncomplete),
      // 바로 다음 줄이 숫자로 시작하면 건물번호가 이어지는 것으로 보고
      // 주소에 합친다 — 상세주소 자리로 통째로 넘기면(아래 두 분기) 정작
      // 주소엔 건물번호가 영영 안 들어가는 문제가 있었다(2026-08-07 실기기
      // 확인, 원문 "…대왕판교로" / "644번길 49, 한컴타워 3층"이 두 줄로
      // 나뉘어 있었음). 합친 뒤엔 콤마/건물번호 기준으로 다시 상세주소를
      // 뽑아낸다 — 처음 주소를 나눌 때와 같은 규칙.
      if (addressLooksIncomplete &&
          addressLineIndex != null &&
          lineIndex == addressLineIndex + 1 &&
          RegExp(r'^\d').hasMatch(line.trim())) {
        var merged = '$address${line.trim()}';
        final mergedCommaIdx = merged.indexOf(',');
        if (mergedCommaIdx != -1) {
          addressDetail = merged.substring(mergedCommaIdx + 1).trim();
          merged = merged.substring(0, mergedCommaIdx).trim();
        } else {
          final mergedRoadNumberMatches = RegExp(
            r'(로|길|가)\s*\d+(?:-\d+)?',
          ).allMatches(merged).toList();
          if (mergedRoadNumberMatches.isNotEmpty) {
            final lastMerged = mergedRoadNumberMatches.last;
            final afterMerged = merged.substring(lastMerged.end).trim();
            if (afterMerged.isNotEmpty) {
              addressDetail = afterMerged;
              merged = merged.substring(0, lastMerged.end).trim();
            }
          }
        }
        address = merged;
        addressLineIndex = lineIndex;
        addressLooksIncomplete = false;
        continue;
      }
      if (addressDetail == null && addressDetailRegExp.hasMatch(line)) {
        addressDetail = line.trim();
        continue;
      }
      // 주소 줄 바로 다음 줄인데 아직 상세주소를 못 찾았다면(콤마도, 층/호
      // 패턴도 없었다는 뜻) 이 줄을 상세주소로 본다.
      //
      // ⚠️ 단 **숫자가 하나라도 있을 때만.** 예전에는 다음 줄을 무조건
      // 상세주소로 먹었는데, 명함 레이아웃상 주소 아래에 이름이나 회사명이
      // 오는 경우가 흔해서 그것들이 통째로 사라졌다 — 원문에 이름이 멀쩡히
      // 있는데도 이름 칸이 비는 원인 중 하나였다(2026-08-14 실측).
      // 실제 상세주소는 "한컴타워 3층", "B동 201호", "5층"처럼 거의 항상
      // 숫자를 포함한다. 숫자가 없으면 상세주소로 보지 않고 다른 칸 후보로
      // 넘긴다 — 못 채우는 쪽이 남의 칸을 뺏는 쪽보다 낫다.
      if (addressDetail == null &&
          addressLineIndex != null &&
          lineIndex == addressLineIndex + 1 &&
          RegExp(r'\d').hasMatch(line)) {
        addressDetail = line.trim();
        continue;
      }
      // 다음 줄이 숫자 없는 **건물명**("SK T-타워")인 경우도 상세주소로 본다.
      // 위 숫자 가드만으로는 숫자가 없는 건물명이 통째로 버려졌다(card_03).
      // 건물명 접미사(타워/빌딩/…)로 끝나는 줄만 받아 이름·회사명을 삼키지
      // 않는다 — 접미사 목록은 조직명과 겹치지 않는 것만 보수적으로 둔다.
      if (addressDetail == null &&
          addressLineIndex != null &&
          lineIndex == addressLineIndex + 1 &&
          _buildingNameRegExp.hasMatch(line.trim())) {
        addressDetail = line.trim();
        continue;
      }
      // **괄호만으로 이루어진 줄**은 상세주소에 이어 붙인다(추가 428).
      //
      // 명함은 법정동·건물명을 `(역삼동, 어반벤치빌딩)`처럼 **따로 한 줄로**
      // 인쇄하는 일이 흔하다. 위 폴백들은 전부 `addressDetail == null`일 때만
      // 도는데, 그 줄이 오기 전에 이미 `2층`이 상세주소로 잡혀 있으면 이
      // 줄은 어디에도 못 붙고 **통째로 버려졌다.**
      //
      // 실측(96장): 정답 주소·상세에 괄호가 있는 35장 중 이 모양으로 잃던
      // 것이 3장이다(추가 422·428).
      //
      // ⚠️ **괄호 안이 주소 조각일 때만** 붙인다. 괄호는 명함에서 영문 병기·
      // 직함 부연에도 쓰여서(`(Daniel)`·`(Marketing Company)`), 아무 괄호나
      // 붙이면 상세주소가 엉뚱한 말로 오염된다.
      if (addressDetail != null &&
          addressDetail.isNotEmpty &&
          _looksLikeAddressParenLine(line)) {
        final add = line.trim();
        if (!addressDetail.contains(add)) {
          addressDetail = '$addressDetail $add';
        }
        continue;
      }
      remaining.add(line);
    }

    // 직함/회사 키워드로 먼저 매칭하고, 순수 한글 2~4자 줄은 이름 후보로 잡는다.
    // 셋 다 못 찾은 나머지는 예전처럼 "남은 줄 중 앞에서부터" 순서로 채운다.
    String? titleLine;
    String? companyLine;

    /// 이름 후보를 **강·약 두 갈래로 나눠 담는다** (2026-08-14).
    ///
    /// 예전에는 변수 하나에 먼저 걸린 것을 담고 끝냈다(선착순). 그래서 명함
    /// 위쪽 슬로건 줄에서 뜯어낸 토큰이, **아래에 자기 줄로 멀쩡히 있는 진짜
    /// 이름**을 밀어냈다 — 실측에서 card_115·117(`전문가관`이 `안희원`을),
    /// card_51(`이랜서`가 `감동훈`을) 밀어낸 것이 확인됐다.
    ///
    /// - **강**: 줄 전체가 이름이거나(`이희규`), 직함 키워드로 갈라낸 것
    ///   (`실장 곽용환`). 근거가 분명하다.
    /// - **약**: 다른 내용이 섞인 긴 줄에서 토큰 하나를 뜯어낸 것
    ///   (`이정현 DA Sovargen`). 슬로건 끝자락도 이 모양이라 구별이 안 된다.
    ///
    /// 강이 하나라도 있으면 약은 쓰지 않는다.
    String? nameLineStrong;
    String? nameLineWeak;
    OcrNameSource? weakSource;
    // 이름/회사명을 "어떤 규칙으로" 뽑았는지 기록한다(값이 아니라 경로만).
    // 인식 품질 측정용 — 약한 폴백 비율이 얼마나 되는지 보기 위함.
    var nameSource = OcrNameSource.none;
    var companySource = OcrCompanySource.none;
    final leftover = <String>[];

    // 한글 2~4자 줄이 **여럿이면 가장 큰 줄**을 이름으로 본다(추가 405).
    //
    // ## 왜
    //
    // `koreanStripped`는 규칙에 걸리는 **첫 줄**을 이름으로 썼다. 그런데 명함에는
    // 부서명·브랜드어처럼 **이름과 형태가 똑같은 한글 2~4자 줄**이 이름보다 위에
    // 있는 경우가 흔하다. 그때 이름은 영영 안 잡힌다.
    //
    // 2026-08-22 실측(정답지 대조 95장, macOS Vision OCR로 뽑은 줄을 이 파서에
    // 넣어 잰 값):
    //
    // ```
    // 후보가 여럿일 때 첫 줄을 고르면    42 / 60  (70%)
    // 가장 큰 줄을 고르면               49 / 60  (82%)
    // ```
    //
    // 갈린 건들의 높이 차가 **2~3배**였다(예: 36 대 97). 이름이 명함에서 가장 크게
    // 인쇄된다는 상식이 수치로 확인된 셈이다.
    //
    // ⚠️ **아래 약한 폴백(`fontSizePreferred`)이 이미 쓰던 손이다.** 거기서는
    // "규칙이 다 실패했을 때"만 높이를 봤는데, 이 측정은 **확신 경로 안에서도**
    // 봐야 한다는 뜻이었다. 여유 1.1배도 그쪽과 같은 값을 쓴다 — 살짝 큰 정도는
    // 잡음일 수 있다.
    //
    // ⚠️ **높이를 모르면 예전 그대로 첫 줄**이다(테스트 입력 등). 그래서 이
    // 변경은 높이 정보가 있을 때만 동작한다.
    //
    // ⚠️ 위 수치는 **Vision OCR 기준**이다. 앱은 ML Kit을 쓰므로 줄 나눔이 달라
    // 실제 이득은 다를 수 있다 — 실기기에서 다시 재야 확정이다.
    // ⭐ **로마자 성씨 신호**를 루프 전에 구해 둔다(추가 429). 이 신호는
    // "어떤 줄이 한글 2~4자다"보다 **강한 근거**라, 아래 `koreanStripped`가
    // 다른 줄을 먼저 집어가지 못하게 막는 데 쓴다.
    // ⚠️ **루프 전에 구해 둔다** — 「이 줄이 회사인가」를 판단할 때 **명함
    //    전체에 법인 표기가 있는지**가 근거가 된다(아래 `weakOnly`).
    final hasStrongCompanyLine = lines.any(
      (l) => _strongCompanyMarker.hasMatch(_stripContacts(l)),
    );

    String? romanizedNameToken;
    for (final raw in lines) {
      final byRoman = _nameByRomanizedSurname(raw);
      if (byRoman != null) {
        romanizedNameToken = byRoman;
        break;
      }
    }

    String? preferredKoreanNameLine;
    // 이름 후보 중에 **성씨로 시작하는 것이 따로 있는가**(추가 413).
    // 아래 `koreanStripped` 경로의 안전판으로 쓴다 — 자세한 것은 그 자리 주석.
    var hasSurnameCandidate = false;
    {
      final candidates = <String>[];
      for (final line in remaining) {
        final stripped = line.replaceAll(RegExp(r'\s+'), '');
        if (_koreanNameRegExp.hasMatch(stripped) &&
            !_isRejectedName(stripped)) {
          candidates.add(line);
          if (_startsWithSurname(stripped)) hasSurnameCandidate = true;
        }
      }
      if (candidates.length >= 2) {
        var tallest = candidates.first;
        var tallestH = heightByText[tallest] ?? 0;
        for (final c in candidates.skip(1)) {
          final h = heightByText[c] ?? 0;
          if (h > tallestH) {
            tallest = c;
            tallestH = h;
          }
        }
        final firstH = heightByText[candidates.first] ?? 0;
        if (tallest != candidates.first &&
            firstH > 0 &&
            tallestH >= firstH * 1.1) {
          preferredKoreanNameLine = tallest;
        }
      }
    }

    for (final line in remaining) {
      // 연락처 라벨만 남은 줄은 **어떤 판정도 하지 않고** 버린다. 번호·이메일은
      // 이미 앞 단계에서 뽑아 갔고, 남은 "TEL. FAX." 같은 조각은 어느 칸에도
      // 들어갈 값이 아니다. 67장 실측에서 이름에 "TEL.  FAX. 02-2606-3026",
      // 회사명에 "Tel  Fax 070-7600-0812", "Fax."가 들어갔다(추가 181·182).
      //
      // ⚠️ **회사 키워드 검사보다 먼저** 해야 한다. "www.hanbit.co.kr E-mail"은
      // 도메인의 `.co.`가 회사 키워드 'Co.'에 걸려 회사명으로 확정돼 버린다
      // — 뒤에서 걸러 봐야 이미 늦는다(테스트가 잡았다).
      if (_isContactLabelResidue(line)) continue;

      // 주소로 보이는 줄은 회사명·직함·이름 후보로 쓰지 않는다.
      //
      // 주소 필드는 하나뿐이라 **두 번째 주소**(본사와 공장, 국문과 영문 병기
      // 등)는 어디에도 안 들어간다. 그런데 그대로 두면 leftover로 흘러 회사명
      // 자리를 차지한다 — 103장 실측에서 회사명 오분류의 대부분이 이것이었다
      // (`대구 공장| 대구광역시 달서구 …`, `(07207 ) 서울특별시 영등포구 …`).
      // 값이 없는 것이 틀린 값보다 낫다는 원칙(추가 183)과 같은 방향이다.
      if (addressRegExp.hasMatch(line) ||
          roadAddressNoProvinceRegExp.hasMatch(line)) {
        continue;
      }

      // 직함 키워드가 걸린 줄에 이름도 같이 붙어 있는 경우가 실제 명함
      // 샘플에서 흔하게 확인됐다 — "실장 곽용환"(키워드 먼저), "이정섭
      // 부장"(이름 먼저), "윤 덕 현 컨설팅 및 딜리버리 팀장"(이름이 한
      // 글자씩 띄어져 있고 직함은 길게 서술형)까지 순서와 형태가 제각각.
      // 줄 전체를 직함으로 삼으면 이름을 영영 못 찾으므로 토큰 단위로
      // 분리를 시도한다.
      // ⚠️ 직함 키워드는 `_containsCi`(단어 경계 없는 부분 문자열)로 걸리므로,
      // **직함이 아닌 줄이 직함 키워드를 우연히 품고 있는 경우**를 먼저 걸러야
      // 한다. 이 검사가 없으면 그 줄이 통째로 직함이 되고 `continue` 때문에
      // 회사명은 영영 못 채운다 — 2026-08-13 진단에서 실제로 확인했다
      // (backlog 추가 180):
      //
      //   "한빛전자 강남대리점"      → '대리'가 "강남**대리**점"에 걸려 회사·이름이 전부 어긋남
      //   "한빛사원아파트관리사무소" → '사원'이 걸려 회사명이 빈 값
      //   "정보시스템수석감리원"     → '수석'이 걸려 자격증이 직함 자리를 차지
      //
      // 영문에서 짧은 약어를 뺀 것과 달리 '대리'·'사원'·'수석'은 **그 자체로
      // 정당한 직함**이라 목록에서 지울 수 없고, "뒤에 한글이 이어지면 제외"
      // 같은 형태 규칙도 못 쓴다("수석연구원"이 같은 모양이면서 정상 직함이다).
      // 그래서 줄이 무엇인지를 보고 거른다.
      // ⚠️ 회사 키워드는 **URL·이메일을 걷어낸 뒤** 본다. `.co.kr` 도메인의
      // `.co.`가 키워드 'Co.'에 걸려, 웹사이트 줄이 회사명으로 확정되던 문제가
      // 실측에서 2장 나왔다(추가 183). 추가 178·180·182와 같은 부분 문자열
      // 함정의 네 번째 사례다.
      final lineWithoutContacts = _stripContacts(line);
      // 🚨 **`그룹장` 의 `그룹` 이 회사 키워드에 걸린다**(2026-08-30, 실측).
      //
      // ```
      // 임준석.그룹장/상무   →  줄 전체가 **회사 칸**으로 갔다
      //                        (정답: 이름 「임준석」 · 직함 「그룹장/상무」)
      // ```
      //
      // `그룹` 은 회사 키워드(`삼성그룹`)인데 **`그룹장` 은 직함**이다. 그래서
      // 이 줄은 직함 키워드 매칭 자체를 건너뛰고 회사 후보로 흘러갔다.
      //
      // ⚠️ **이 파일이 반복해 겪은 부분 문자열 함정의 또 한 사례다** —
      //    `SK telecom` 의 `tel`(추가 178·180), `.co.kr` 의 `Co.`(추가 183),
      //    `ceonitios` 의 `ceo`(추가 592). **회사 낱말 뒤에 `장` 이 붙으면
      //    그것은 사람의 직함이지 회사가 아니다.**
      final lineForCompanyCheck = lineWithoutContacts.replaceAll(
        RegExp(r'(그룹|본부|사업부|공사|공단)장'),
        ' ',
      );
      // 🚨 **약한 회사 낱말만 있는 줄은, 같은 명함에 법인 표기가 있으면
      //    회사가 아니다**(2026-08-30, 두 자 대조 실측).
      //
      // ```
      // 기업부설연구소                →  회사 칸  (정답 (주)그린아이티코리아)
      // MNO마케팅그룹 로밍마케팅팀      →  회사 칸  (정답 SK텔레콤)
      // Production Support Group    →  회사 칸  (정답 현대제철주식회사)
      // ```
      //
      // `연구소`·`그룹`·`센터` 는 회사 키워드다(`무지개청소년센터` 는 진짜
      // 회사명이다). 그런데 **부서 이름도 같은 낱말로 끝난다.** 둘을 낱말만
      // 보고는 못 가른다.
      //
      // 📌 **가르는 근거는 「같은 명함에 더 강한 표기가 있는가」다** —
      //    `(주)`·`주식회사`·`Inc.` 는 **회사에만** 붙는다. 그런 줄이 따로
      //    있으면 약한 낱말 줄은 부서 쪽이다.
      //
      // ⚠️ **더 강한 줄이 없으면 예전 그대로** 회사로 본다 — 법인 표기 없이
      //    `…센터` 로만 된 회사가 실제로 있다.
      final weakOnly =
          !_strongCompanyMarker.hasMatch(lineForCompanyCheck) &&
          _companyKeywords.any((k) => _containsCi(lineForCompanyCheck, k));
      final isCompanyLine = weakOnly
          ? !hasStrongCompanyLine
          : _companyKeywords.any((k) => _containsCi(lineForCompanyCheck, k));
      final isQualificationLine = _qualificationMarkers.any(
        (k) => _containsCi(line, k),
      );
      final matchedTitleKeyword = (isCompanyLine || isQualificationLine)
          ? ''
          : _titleKeywords.firstWhere(
              (k) => _containsCi(line, k),
              orElse: () => '',
            );
      if (titleLine == null && matchedTitleKeyword.isNotEmpty) {
        final split = _splitNameFromTitleLine(line, matchedTitleKeyword);
        // 갈라낸 값이 사람 이름 모양이 아니면(`디지털`) **가르지 않은 것으로
        // 본다** — 줄 전체를 직함으로 두고, 이름은 다른 줄에서 찾는다.
        if (nameLineStrong == null &&
            split != null &&
            !_isRejectedName(split.name) &&
            _hangulNameLooksReal(split.name)) {
          nameLineStrong = split.name;
          nameSource = OcrNameSource.keywordSplit;
          titleLine = split.title;
        } else {
          titleLine = line;
        }
        continue;
      }
      // 영문 회사 표기가 "NELSON SPORTS, INC."처럼 전부 대문자인 경우가
      // 실제 명함에서 확인됐다 — 키워드 목록의 "Inc."/"Co."는 대소문자가
      // 섞여 있어 그대로 비교하면 놓친다. 대소문자를 구분하지 않고 검사.
      if (companyLine == null && isCompanyLine) {
        final matchedCompanyKeyword = _companyKeywords.firstWhere(
          (k) => _containsCi(lineWithoutContacts, k),
          orElse: () => '',
        );
        companyLine = matchedCompanyKeyword.isEmpty
            ? line
            : _trimCompanyAroundKeyword(line, matchedCompanyKeyword);
        companySource = OcrCompanySource.keyword;
        continue;
      }
      // 명함에서 이름을 "최 태 웅"처럼 음절 사이를 띄워서 강조하는 서체가
      // 흔해서(실기기 스캔으로 확인됨), 공백을 뺀 버전으로도 검사한다 —
      // 매칭되면 공백 없는 형태로 저장한다(입력칸에 공백 섞인 이름이
      // 들어가는 것보다 자연스럽다). 이 검사를 leftover로 넘기기 "전에"
      // 하는 게 중요하다 — 안 그러면 아래 leftover 순서 배정에서 이름이
      // 아닌 줄(예: 접미사 없는 회사명)이 먼저 이름 자리를 차지하고, 정작
      // 이름은 회사명 자리로 밀려나는 문제가 있었다.
      final strippedForName = line.replaceAll(RegExp(r'\s+'), '');
      if (nameLineStrong == null &&
          _koreanNameRegExp.hasMatch(strippedForName) &&
          !_isRejectedName(strippedForName) &&
          // ⚠️ **성씨로 시작하는 다른 후보가 있을 때만** 이 줄을 미룬다
          // (추가 413). `통일부`처럼 기관명이 한글 2~4자라 이름 규칙을 그대로
          // 통과하고, 하필 진짜 이름보다 위에 인쇄돼 있으면 이름 자리를
          // 차지한다. 그러면 밀려난 진짜 이름이 **회사 칸으로 들어간다** —
          // 테스터 B가 본 증상이 이것이다(96장 실측에서 이름 2·회사 1을 얻고
          // 깨진 것은 0이었다).
          //
          // ⚠️ **성씨 목록에 없으면 무조건 버리는 것이 아니다.** 성씨 목록은
          // 79개라 드문 성을 놓칠 수 있고, 그때 이름이 통째로 사라지면 훨씬
          // 나쁘다. 그래서 **대안이 있을 때만** 미룬다 — 영문 사람 이름 판정이
          // *"다른 후보가 없으면 그대로 쓴다"*로 스스로를 막아 둔 것과 같다.
          (_startsWithSurname(strippedForName) || !hasSurnameCandidate) &&
          // ⚠️ **로마자 성씨 신호가 다른 이름을 가리키면 양보한다**(추가 429).
          // 이 경로는 "한글 2~4자"만 보므로, 명함에 그런 낱말이 둘 이상이면
          // 먼저 오는 줄이 이긴다 — 실측 96장에서 그 때문에 3장이 엉뚱한 줄을
          // 이름으로 삼았다. 로마자 표기가 성씨와 맞는 쪽이 더 강한 근거다.
          (romanizedNameToken == null ||
              strippedForName == romanizedNameToken) &&
          // 더 큰 후보가 있으면 그 줄이 올 때까지 미룬다(추가 405). 밀린 줄은
          // 예전처럼 leftover로 흘러가 회사명 후보로 계속 쓰인다.
          (preferredKoreanNameLine == null ||
              line == preferredKoreanNameLine)) {
        nameLineStrong = strippedForName;
        nameSource = OcrNameSource.koreanStripped;
        continue;
      }
      // 이름과 회사 로고 텍스트가 같은 줄(같은 행)에 같이 인식되는 경우가
      // 실제 명함(Sovargen)에서 확인됐다 — 로고 그래픽을 ML Kit이 "DA"
      // 같은 엉뚱한 텍스트로 잘못 읽어서 "이정현 DA Sovargen"처럼 한 줄로
      // 뭉친다. 줄 전체는 한글+영문이 섞여 있어 위 순수 한글 검사를 통과
      // 못 하지만, 첫/마지막 토큰만 떼어보면 이름 모양인 경우가 많다 —
      // 그 토큰만 이름으로 뽑고 나머지는 버리지 않고 leftover로 넘겨
      // 회사명 후보로 계속 쓸 수 있게 한다(안 그러면 이름 자리를 못 찾은
      // 줄 전체가 leftover로 밀려서 다음 name 배정 때 통째로 소비되고,
      // 정작 회사명 자리는 leftover가 텅 비어 못 채우는 문제가 있었다).
      // 순수 한글 여러 단어로 된 줄(예: "국민 맞춤형 복지를 실현하는
      // 디지털 플랫폼 전문기관" 같은 슬로건 문구)까지 이 검사에 걸리면,
      // 첫 단어가 우연히 2~4자 한글 조합이라 이름처럼 보여서 오탐이
      // 났다(실제 명함 SSIS에서 확인된 회귀 — "국민"이 이름으로 잘못
      // 뽑힘). 로고 오인식 텍스트가 섞인 경우(한글+영문 혼용)만 노리는
      // 검사이므로, 한글이 아닌 문자가 섞여 있을 때만 시도한다.
      // 🚨 **부서·직함 뒤에 자간을 벌려 인쇄한 이름**(2026-08-29, 94장 실측).
      //
      // ```
      // 개발협력부 김수 진      →  이름 「김수진」
      // 종괄매니저 김지 홍      →  이름 「김지홍」
      // ```
      //
      // 위 검사는 **영문이 섞인 줄만** 보고(슬로건 오탐을 막으려고), 게다가
      // **앞에서부터** 이어 붙인다. 그래서 **부서가 앞에 오는 이 모양**은
      // 통째로 놓쳤다 — 94장에서 이름이 비거나 로고가 들어간 12장 중
      // **세 장이 이것**이었다.
      //
      // ⚠️ **슬로건이 걸리지 않게 조건을 좁힌다** — 앞부분이 **부서 접미사나
      // 직함 키워드**여야 하고, 뒤 토막을 이어 붙인 것이 **진짜 이름 모양**
      // 이어야 한다. `국민 맞춤형 복지를…` 같은 문장은 앞부분이 부서·직함이
      // 아니라 걸리지 않는다.
      // ⚠️ **영문 후보가 이미 잡혀 있어도 본다.** 실측에서 로고 글씨
      //    (`ARENA FITNESS`·`BIS`)가 **앞줄에서 먼저 이름 자리를 차지**해
      //    뒤에 오는 진짜 한글 이름을 막고 있었다. 한국 명함에서 **한글 이름은
      //    영문 후보보다 강한 근거**다.
      if (nameLineStrong == null &&
          (nameLineWeak == null || !_hasHangul(nameLineWeak))) {
        final t = line
            .split(_whitespaceSplitRegExp)
            .where((x) => x.isNotEmpty)
            .toList();
        final allHangul = t.every((x) => RegExp(r'^[가-힣]+$').hasMatch(x));
        if (t.length >= 2 && allHangul) {
          for (var start = t.length - 1; start >= 1; start--) {
            final tail = t.sublist(start).join();
            if (tail.length < 2 || tail.length > 4) continue;
            final head = t.sublist(0, start).join();
            final headIsDeptOrTitle =
                _departmentSuffixes.any(head.endsWith) ||
                RegExp(r'(부|팀|실|과|처|국|센터|본부|그룹|파트)$').hasMatch(head) ||
                _titleKeywords.any((k) => _containsCi(head, k));
            if (!headIsDeptOrTitle) continue;
            if (!_koreanNameRegExp.hasMatch(tail)) continue;
            if (_isRejectedName(tail)) continue;
            if (!_hangulNameLooksReal(tail)) continue;
            nameLineWeak = tail;
            weakSource = OcrNameSource.mixedTokenLast;
            break;
          }
        }
      }

      final hasNonHangul = line.replaceAll(RegExp(r'[가-힣\s]'), '').isNotEmpty;
      if (nameLineStrong == null && nameLineWeak == null && hasNonHangul) {
        final tokens = line
            .split(_whitespaceSplitRegExp)
            .where((t) => t.isNotEmpty)
            .toList();
        if (tokens.length >= 2) {
          // 이름이 "이 시영"처럼 음절 일부만 띄어져서 여러 토큰으로 갈라져
          // 나오는 경우가 실제 명함(알로이스)에서 확인됐다 — 앞 토큰 하나만
          // 보면 "이"(1자)라 이름 정규식(2~4자)에 안 걸려서 놓쳤다. 맨
          // 앞부터 순수 한글 토큰이 연속되는 만큼 이어붙여 보고, 그 결과가
          // 이름 모양(2~4자)이면 그 구간 전체를 이름으로 쓴다(토큰이 1개뿐인
          // 경우 = 위 strippedForName 검사와 동치이므로 자연히 포함된다).
          final hangulOnlyRegExp = RegExp(r'^[가-힣]+$');
          var frontRunEnd = 0;
          final frontBuffer = StringBuffer();
          while (frontRunEnd < tokens.length &&
              hangulOnlyRegExp.hasMatch(tokens[frontRunEnd])) {
            frontBuffer.write(tokens[frontRunEnd]);
            frontRunEnd++;
          }
          if (frontRunEnd > 0 &&
              frontRunEnd < tokens.length &&
              _koreanNameRegExp.hasMatch(frontBuffer.toString()) &&
              !_isRejectedName(frontBuffer.toString()) &&
              _hangulNameLooksReal(frontBuffer.toString())) {
            nameLineWeak = frontBuffer.toString();
            weakSource = OcrNameSource.mixedTokenFront;
            // 이름 바로 다음 토큰이 로고 오인식 잡음인 경우가 실제
            // 명함(Sovargen, 알로이스)에서 확인됐다 — "DA Sovargen"이나
            // "O ALOYS"를 그대로 leftover에 넘기면 회사명이 지저분해진다
            // ("최서연,이정현 모두 회사명에 DA 가 들어오네" 재제보,
            // 2026-08-07). 이름 바로 뒤 토큰이 2자 이하면 걷어낸다.
            final restTokens = tokens.sublist(frontRunEnd);
            if (restTokens.length > 1 && restTokens.first.length <= 2) {
              restTokens.removeAt(0);
            }
            final rest = restTokens.join(' ');
            if (rest.isNotEmpty) leftover.add(rest);
            continue;
          }
          if (_koreanNameRegExp.hasMatch(tokens.last) &&
              !_isRejectedName(tokens.last) &&
              _hangulNameLooksReal(tokens.last)) {
            nameLineWeak = tokens.last;
            weakSource = OcrNameSource.mixedTokenLast;
            final restTokens = tokens.sublist(0, tokens.length - 1);
            if (restTokens.length > 1 && restTokens.last.length <= 2) {
              restTokens.removeAt(restTokens.length - 1);
            }
            final rest = restTokens.join(' ');
            if (rest.isNotEmpty) leftover.add(rest);
            continue;
          }
        }
      }
      // 자격증 줄은 leftover에도 넣지 않는다. 직함·회사명·이름은 모두 leftover
      // 맨 앞을 폴백으로 쓰기 때문에, 여기 남겨 두면 직함 키워드 매칭에서
      // 걸러 놓고도 결국 직함 자리에 다시 들어간다(2026-08-13 확인).
      // 단 "○○감리사무소"처럼 회사명이면서 자격증 표기를 품은 줄은 회사명으로
      // 살려야 하므로 회사 키워드가 걸린 줄은 예외로 둔다.
      if (isQualificationLine && !isCompanyLine) continue;
      leftover.add(line);
    }

    // 회사 로고를 이름으로 착각하는 것을 막는다.
    //
    // 명함 위쪽의 큰 영문 로고("CREAMHOUSE")는 글자도 크고 맨 앞에 있어서,
    // 한글 이름이 인식되지 않으면 아래 약한 폴백이 그걸 이름으로 고른다.
    // 실기기에서 실제로 벌어졌고 "이름 칸에 기업명이 들어가는 경우가 많다"는
    // 사용자 보고와 같은 현상이다(2026-08-13, backlog 추가 180).
    //
    // 판별 근거: **그 후보가 회사명 줄 안에 통째로 들어 있는지.** 로고는
    // 회사명/도메인의 일부라 거의 항상 걸리고("CREAMHOUSE" ⊂
    // "Www.CREAMHOUSE.CO.KR"), 사람 이름이 회사명 문자열에 통째로 포함되는
    // 일은 드물다. 한글이 섞인 후보는 건드리지 않는다 — 한글 이름은 위
    // 규칙들이 이미 정확히 잡고, 여기서 잘못 걸러내면 손해가 크다.
    // 글자가 사실상 없는 잔여물("M.", "T." 같은 라벨 찌꺼기)은 이름 후보에서
    // 뺀다. 빈 이름보다 이런 값이 들어가는 쪽이 더 나쁘다 — 사용자는 화면에
    // 뜬 "M."을 보고 인식이 됐다고 오해하고, 저장하면 그대로 인맥 이름이 된다.
    // 값을 지어내지 않는다는 원칙(CLAUDE.md)과도 같은 방향이다.
    leftover.removeWhere(
      (candidate) =>
          candidate.replaceAll(RegExp(r'[^가-힣A-Za-z]'), '').length < 2,
    );

    // 남는 후보가 없어져 이름이 빈 값이 되는 것도 **의도한 결과**다. 로고를
    // 사람 이름으로 저장하는 것보다, 비워 두고 사용자가 직접 채우게 하는 쪽이
    // 낫다(스캔 화면이 "이름을 찾지 못했다"고 안내한다).
    //
    // 비교 대상은 두 곳이다. 회사명 줄만 보면 회사명이 한글로 정확히 잡힌
    // 순간("크림하우스(주)") 로고 영문과 겹치는 부분이 없어져 필터가 무력해진다
    // — 실기기 재스캔에서 실제로 그렇게 됐다. **이메일 도메인**이 남은 근거다
    // (`globe@creamhouse.net` ← `CREAMHOUSE`).
    final emailDomain = email == null || !email.contains('@')
        ? null
        : email.split('@').last;
    // 웹사이트 주소도 로고 판별의 근거다 — 로고는 도메인과 같은 브랜드명인
    // 경우가 많다(`HANBIT` ⊂ `www.hanbit.co.kr`). 회사명 줄만 보면, URL을
    // 회사명에서 걷어낸 뒤로는 단서가 사라진다(테스트가 잡았다).
    final urlTexts = [
      for (final l in lines)
        for (final m in RegExp(
          r'(https?://|www\.)[^\s]+',
          caseSensitive: false,
        ).allMatches(l))
          m.group(0)!,
    ];
    final logoHaystacks = [
      ?companyLine,
      ?emailDomain,
      ...urlTexts,
    ].map((s) => s.replaceAll(RegExp(r'[\s.]'), '')).toList();

    // ⚠️ leftover에서 **지우지는 않는다.** 여기서 지우면 회사명 폴백까지 후보를
    // 잃는다 — 접미사 없는 회사명(Sovargen)은 자기 도메인(sovargen.com)에
    // 들어 있어서 로고 판정에 걸리고, 지워 버리면 회사명이 빈 값이 된다
    // (테스트 5건이 이걸로 깨졌다). 이름을 고를 때만 뺀다.
    bool isLogoLike(String candidate) {
      if (logoHaystacks.isEmpty || _hasHangul(candidate)) return false;
      final squashed = candidate.replaceAll(RegExp(r'[\s.]'), '');
      // 4자 미만은 비교하지 않는다 — "Han"이 "hanbit.co.kr"에 걸리는 식으로
      // 짧은 영문 이름이 도메인에 우연히 들어가는 경우를 피한다.
      if (squashed.length < 4) return false;
      return logoHaystacks.any((h) => _containsCi(h, squashed));
    }

    // 약한 폴백에는 **이름 모양인 후보만** 넣는다(사용자 결정 2026-08-14).
    //
    // 예전에는 규칙으로 확신하지 못하면 남은 줄 맨 앞을 그냥 이름으로 썼다.
    // 그래서 쓰레기를 하나 걸러내면 **그 자리를 다음 쓰레기가 채웠다** —
    // 67장 실측에서 라벨 찌꺼기를 없앴더니 슬로건("I'm a Voyager of value",
    // "설계, 제작 및 납품 E-mail.")이 대신 들어왔다(추가 182).
    //
    // 명함 앱에서 이름이 틀린 채 저장되면 나중에 그 사람을 못 찾고, 사용자는
    // 틀린 줄도 모른다. 그래서 **확신하지 못하면 비운다** — 스캔 화면이
    // "이름을 찾지 못했다"고 안내하고 사용자가 직접 채운다.
    final nameCandidates = leftover
        .where((l) => !isLogoLike(l) && _looksLikePersonName(l))
        .toList();

    String name;
    // 확신 경로가 모두 실패했을 때, **영문 약폴백보다 한글 이름 토큰을 먼저**
    // 본다(2026-08-14).
    //
    // 사용자 지적: "한글이름 옆이나 아래 영문이름이 있는 경우도 있음". 한국
    // 명함은 한글 이름과 영문 표기를 나란히 인쇄하는 경우가 흔한데, OCR이 그
    // 줄을 로고·슬로건과 뭉쳐 읽으면 앞뒤 규칙이 다 빗나간다. 그러면 남은
    // 줄에서 짧은 영문 조각이 이름 자리를 차지했다 — card_02는 원문에
    // `Molecule 박병건 | Andy Park`이 있는데 이름 칸에 `Audience`가 들어갔다.
    //
    // 한글 이름 토큰(성 1자 + 이름 2자, 지명·직함·슬로건 제외)은 짧은 영문
    // 조각보다 훨씬 확실한 근거다. 그래서 순서를 뒤집는다.
    String? hangulTokenName;
    String? hangulTokenLine;
    if (nameLineStrong == null && nameLineWeak == null) {
      for (final rawLine in lines) {
        // 주소로 읽히는 **구간만** 걷어내고 나머지를 본다. 예전에는 그런 줄을
        // 통째로 건너뛰었는데, 명함 한 장이 한 줄로 뭉쳐 인식되면 그 안에
        // 이름도 같이 들어 있어서 통째로 놓쳤다(card_18의 `손연기`).
        // 지명(`경기도`·`영등포구`)은 걷어낸 구간 안에 있으므로 보호는 그대로다.
        final line = _withoutAddressSpans(
          rawLine,
          addressRegExp,
          roadAddressNoProvinceRegExp,
          address: address,
          addressDetail: addressDetail,
        );
        if (line.isEmpty) continue;
        final picked = _extractPersonNameToken(line);
        if (picked == null) continue;
        if (companyLine != null && companyLine.contains(picked)) continue;
        hangulTokenName = picked;
        hangulTokenLine = rawLine;
        break;
      }
    }

    // ⭐ **로마자 성씨 신호**(추가 429). 확정 근거가 없거나 약한 근거뿐일 때만
    // 본다 — 이미 강한 근거로 찾았으면 건드리지 않는다.
    //
    // ⚠️ **루프가 끝난 뒤에 본다.** 루프 안에서 `continue`로 끊으면 그 줄이
    // 다른 칸(회사·직함) 후보에서 빠져 엉뚱한 곳이 빈다 — 추가 430에서
    // 같은 종류의 손실을 겪었다.
    if (nameLineStrong == null && romanizedNameToken != null) {
      nameLineStrong = romanizedNameToken;
      nameSource = OcrNameSource.romanizedSurname;
    }

    // 강이 있으면 강, 없으면 약. 위 `nameLineStrong` 주석 참고.
    final nameLine = nameLineStrong ?? nameLineWeak;
    if (nameLineStrong == null && nameLineWeak != null) {
      nameSource = weakSource!;
    }
    if (nameLine != null) {
      name = nameLine;
    } else if (hangulTokenName != null) {
      name = hangulTokenName;
      nameSource = OcrNameSource.hangulTokenPreferred;
      // 이름을 뽑아낸 **그 줄의 나머지를 직함 1순위로 돌린다.** 명함은 이름과
      // 직함을 나란히 인쇄하는 경우가 많아, 그 줄에 직함이 함께 있을 가능성이
      // 가장 높다. 이 처리가 없으면 그 줄이 그냥 남아 있고, 대신 로고 줄이
      // 직함 자리를 차지한다 — card_26에서 직함이 `이든.`(로고)이 됐다.
      final idx = leftover.indexOf(hangulTokenLine!);
      if (idx != -1) {
        final rest = hangulTokenLine
            .replaceFirst(name, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .replaceAll(RegExp(r'^[\s|:/,.·]+|[\s|:/,.·]+$'), '')
            .trim();
        leftover.removeAt(idx);
        if (rest.isNotEmpty) leftover.insert(0, rest);
      }
    } else if (nameCandidates.isEmpty) {
      name = '';
      nameSource = OcrNameSource.none;
    } else {
      // P0②(테스터 B 제보, 2026-08-20) 재현: "뒷장 촬영 후 이름란이 회사
      // 영문명으로 자동 변경". leftover에 회사 영문명("LG CNS")·부서명
      // ("DT Optimization")·사람 영문 이름("Kim Do Young")이 함께 남으면,
      // 순서가 이르다는 이유만으로 회사명이 이름 자리를 차지했다.
      //
      // 오늘 같은 날 직함 폴백(`_pickWeakTitleFallback`, 추가 354)에서 이미
      // 검증한 신호(Title Case = 사람 이름)를 재사용한다 — 새 규칙을 만들지
      // 않고, **사람 이름 모양(또는 한글)인 후보가 있으면 그것부터** 본다.
      // 그런 후보가 하나도 없으면(접미사 없는 진짜 회사명은 사람 이름과
      // 형태가 같아 구별 불가) 기존대로 leftover 순서를 쓴다.
      final preferred = nameCandidates
          .where((l) => _hasHangul(l) || _looksLikeEnglishPersonName(l))
          .toList();
      final pool = preferred.isNotEmpty ? preferred : nameCandidates;

      // 규칙으로 이름을 확신하지 못한 약한 폴백 구간이다. 예전엔 남은 줄 "맨
      // 앞"(읽기 순서)을 그냥 이름으로 썼는데, 명함에서 이름은 대개 가장 크게
      // 인쇄되므로 글자 높이를 아는 경우엔 "가장 큰 줄"을 이름으로 고른다.
      // 높이 정보가 전혀 없으면(테스트 입력 등) 기존과 똑같이 맨 앞 줄을 쓴다 —
      // 그래서 이 개선은 확신 경로를 건드리지 않고 약한 폴백만 바꾼다.
      final withHeight = pool.where((l) => (heightByText[l] ?? 0) > 0).toList();
      if (withHeight.length >= 2) {
        withHeight.sort(
          (a, b) => (heightByText[b] ?? 0).compareTo(heightByText[a] ?? 0),
        );
        final biggest = withHeight.first;
        // 가장 큰 줄이 실제로 맨 앞 줄보다 눈에 띄게 커야 이름으로 본다(살짝
        // 큰 정도는 잡음일 수 있어 10% 여유를 둔다). 그렇지 않으면 기존
        // 동작(맨 앞 줄)을 유지한다.
        final biggestH = heightByText[biggest] ?? 0;
        final firstH = heightByText[pool.first] ?? 0;
        if (biggest != pool.first && biggestH >= firstH * 1.1) {
          name = _blankIfUnsureHangul(biggest);
          leftover.remove(biggest);
          nameSource = OcrNameSource.fontSizePreferred;
        } else {
          name = _blankIfUnsureHangul(pool.first);
          leftover.remove(pool.first);
          nameSource = OcrNameSource.leftoverFallback;
        }
      } else {
        name = _blankIfUnsureHangul(pool.first);
        leftover.remove(pool.first);
        nameSource = OcrNameSource.leftoverFallback;
      }
    }

    // 슬로건 문장 조각이 이름이 되는 것을 막는다.
    //
    // 명함 위쪽 홍보 문구("인터넷, 모바일 서비스를 **통해** **고객에게** 성공과
    // 만족을 제공하는…")는 OCR에서 여러 줄로 잘리는데, 그 조각이 한글 2~4자라
    // 이름 규칙에 그대로 걸린다. 실기기 재스캔에서 이름 칸에 "고객에게"가
    // 들어갔다(2026-08-13, backlog 추가 180).
    //
    // 사람 이름은 **조사나 어미로 끝나지 않는다** — 이 성질만으로 충분히 걸러진다.
    // 걸리면 비워 둔다. 잘못된 이름을 넣는 것보다 낫고, 스캔 화면이 "이름을 찾지
    // 못했다"고 안내해 사용자가 직접 채운다.
    if (_isRejectedName(name)) {
      name = '';
      nameSource = OcrNameSource.none;
    }

    // 로고 판정은 **확정 경로(nameLine)에도** 적용한다. 후보 목록에서만 걸렀더니
    // 로고가 약한 폴백이 아니라 앞쪽 규칙으로 이름이 되는 경우에 그대로 통과했다
    // — 실기기 재스캔에서 "CREAMHOUSE"가 이 경로로 들어왔다(2026-08-13).
    // 한글 이름은 `isLogoLike`가 처음부터 건드리지 않으므로 영향이 없다.
    if (isLogoLike(name)) {
      name = '';
      nameSource = OcrNameSource.none;
    }

    // 주소 줄에서 건진 회사명은 **다른 줄에서 못 찾았을 때만** 쓴다.
    companyLine ??= companyFromAddressLine;
    if (companyLine != null && companySource == OcrCompanySource.none) {
      companySource = OcrCompanySource.keyword;
    }
    final companyFromKeyword = companyLine;
    // ⚠️ 두 갈래(키워드 확정 · leftover 고르기)가 여기서 합쳐진다. 회사명
    // 다듬기는 **이 한 곳에서만** 한다 — 갈래마다 손보면 한쪽만 고쳐진다.
    var company = _tidyCompany(
      companyFromKeyword ?? _pickCompanyFromLeftover(leftover) ?? '',
    );
    if (companyFromKeyword == null) {
      companySource = company.isEmpty
          ? OcrCompanySource.none
          : OcrCompanySource.leftoverPick;
    }

    // ── 빈자리 재검증 (사용자 제안 2026-08-14) ──────────────────────────────
    //
    // OCR 추출 자체는 정확한데 **각 칸으로 나누는 과정에서** 값을 잃는 경우가
    // 실측에서 반복 확인됐다. 그래서 1차 배정이 끝난 뒤, **비어 있는 칸만**
    // 다시 한 번 채워 본다. 이미 채워진 칸은 건드리지 않으므로 잘 되던 명함이
    // 나빠질 수 없다.
    //
    // 이름: 주소와 한 줄로 뭉쳐 나온 후보를 쓴다. 이 시점에는 회사명이 정해져
    // 있어서, 그 후보가 사실은 회사명이었던 경우를 걸러낼 수 있다.
    if (name.isEmpty && nameHintBeforeAddress != null) {
      final hint = nameHintBeforeAddress;
      final squashedCompany = company.replaceAll(RegExp(r'\s'), '');
      final isCompanyName =
          squashedCompany.isNotEmpty && _containsCi(squashedCompany, hint);
      if (!isCompanyName && !isLogoLike(hint) && _looksLikePersonName(hint)) {
        name = hint;
        nameSource = OcrNameSource.mergedWithAddress;
      }
    }

    // 직함 칸에서 웹사이트·이메일을 걷어낸다. OCR이 홈페이지 주소를 직함 줄과
    // 붙여 읽는 경우가 흔한데(`www.edenpat.com 파트너 변리사`), 그대로 두면
    // 직함 칸에 URL이 섞여 저장된다(103장 표본 card_10·card_103, 추가 197).
    // 값 자체는 위에서 홈페이지 칸으로 이미 담았고, 여기서는 직함 줄에 남은
    // 찌꺼기를 지우는 일만 한다.
    var title = _stripContacts(
      titleLine ?? _pickWeakTitleFallback(leftover),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();

    // ── 빈자리 재검증 (2) — 직함 칸에 섞여 들어간 이름 ─────────────────────
    //
    // 실측에서 잔여 결함의 가장 큰 공통 모양이었다: **이름 칸은 비었는데 직함
    // 칸 안에 이름이 들어 있다**(card_102 `김효성 연구소장 GIT`, card_28,
    // card_60 `Manager 서비스구매팀 이상화 …`, card_14 `안민식.이사`).
    // OCR이 이름과 직함을 한 덩어리로 읽었는데 `_splitNameFromTitleLine`이
    // 못 가른 경우다.
    //
    // 이름 칸이 **비어 있을 때만** 시도하므로, 이름을 이미 제대로 찾은 명함은
    // 영향을 받지 않는다. 떼어낸 이름은 직함에서 빼서 직함도 같이 깨끗해진다.
    if (name.isEmpty && title.isNotEmpty) {
      final picked = _extractPersonNameToken(title);
      if (picked != null) {
        name = picked;
        nameSource = OcrNameSource.splitFromTitle;
      }
    }

    // ── 빈자리 재검증 (3) — 그래도 이름이 없으면 원문 전체를 다시 훑는다 ──
    //
    // 앞의 규칙들이 모두 실패해도 원문 어딘가에 이름이 남아 있는 경우가 있다.
    // 이미 다른 칸이 가져간 값(회사·직함·주소)은 후보에서 뺀다 — 한 값이 두
    // 칸에 동시에 들어가면 사용자가 지우는 수고가 늘어난다.
    if (name.isEmpty) {
      final taken = [
        company,
        title,
        address ?? '',
        addressDetail ?? '',
      ].where((v) => v.isNotEmpty).join(' ');
      // ⚠️ 여기는 **가장 약한 폴백**이라 기준을 가장 빡빡하게 잡는다. 처음
      // 느슨하게 열었더니 이름 채움이 18장 늘었는데 그중 8장이 쓰레기였다
      // (`경기도`·`영등포구`·`서울시`·`성수역`·`서대문구`). 추가 182에서 겪은
      // "쓰레기를 하나 걸러내면 다음 쓰레기가 그 자리를 채운다"와 같은 모양이다.
      //
      // 그래서 셋을 건다.
      // 1. 주소로 읽히는 줄은 아예 보지 않는다 — 지명이 이름 규칙에 잘 걸린다.
      // 2. 행정구역·장소 접미사로 끝나는 토큰은 뺀다(`…시`·`…구`·`…역`).
      // (글자 수·성씨·지명 검사는 `_extractPersonNameToken`이 이미 한다.)
      for (final rawLine in lines) {
        // 주소로 읽히는 **구간만** 걷어내고 나머지를 본다. 예전에는 그런 줄을
        // 통째로 건너뛰었는데, 명함 한 장이 한 줄로 뭉쳐 인식되면 그 안에
        // 이름도 같이 들어 있어서 통째로 놓쳤다(card_18의 `손연기`).
        // 지명(`경기도`·`영등포구`)은 걷어낸 구간 안에 있으므로 보호는 그대로다.
        final line = _withoutAddressSpans(
          rawLine,
          addressRegExp,
          roadAddressNoProvinceRegExp,
          address: address,
          addressDetail: addressDetail,
        );
        if (line.isEmpty) continue;
        final picked = _extractPersonNameToken(line);
        if (picked == null) continue;
        if (taken.contains(picked)) continue;
        name = picked;
        nameSource = OcrNameSource.rawLineRecheck;
        break;
      }
    }

    // 같은 값이 **이름과 직함 두 칸에 동시에** 들어가지 않게 한다.
    //
    // 이름을 어느 경로로 찾았든(직함 줄을 갈라냈든, 원문을 다시 훑었든) 직함
    // 칸에 그 이름이 남아 있으면 사용자가 손으로 지워야 한다. 이름을 확정한
    // 뒤 한 곳에서만 정리하면 경로마다 따로 신경 쓰지 않아도 된다.
    if (name.isNotEmpty && title.contains(name)) {
      title = title
          .replaceFirst(name, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[\s|:/,.·]+|[\s|:/,.·]+$'), '')
          .trim();
    }

    // ── 부서 분리 (2026-08-19 사용자 확정, 추가 321) ──────────────────────
    //
    // 부서는 직함과 **다른 칸**이다. 예전에는 갈 곳이 없어 직함 칸에 함께
    // 들어갔고, 정답지도 장마다 `대리` / `경영지원팀 대리`로 갈렸다. 그래서
    // 파서를 어느 쪽에 맞춰도 반대쪽이 틀렸다(추가 286, 시도 ②가 −5장).
    //
    // ⚠️ **명함 전체에서 부서를 새로 찾지 않는다.** 그렇게 하면 회사명 자리를
    // 뺏는다 — 이 파일이 이미 겪었다(:483 주석). **이미 직함 칸에 들어온 것만**
    // 가른다. 바로 위 "직함에서 이름 떼어내기"와 같은 모양이고 같은 자리다.
    //
    // 📌 **양쪽이 다 남을 때만 가른다.** 직함 칸이 통째로 부서인 경우
    // (`경영지원팀`만 있는 장)는 건드리지 않는다 — 가르면 직함 칸이 비고,
    // 그것이 이득인지 손해인지는 아직 안 쟀다. 재고 나서 넓힌다.
    var department = '';
    if (title.isNotEmpty) {
      final tokens = title
          .split(_whitespaceSplitRegExp)
          .where((t) => t.isNotEmpty)
          .toList();
      if (tokens.length >= 2) {
        // 접미사가 붙은 토큰만 떼면 **부서 이름의 앞머리가 직함에 남는다** —
        // `ICT 사업본부 상무`가 직함 `ICT 상무` / 부서 `사업본부`로 갈렸다.
        // 그래서 접미사 토큰에서 **앞으로 이어 붙인다**: 바로 앞이 직함 낱말이
        // 아니면 그것도 부서에 속한다(`ICT`). 직함 낱말이면 멈춘다
        // (`상무 ICT사업본부`에서 `상무`를 뺏지 않는다).
        final isDept = List<bool>.filled(tokens.length, false);
        String bareOf(String t) =>
            t.replaceAll(RegExp(r'^[|:/,.·]+|[|:/,.·]+$'), '');
        // 🚨 **조직 계층을 나란히 찍은 명함에서 한 조각만 집고 있었다**
        //    (2026-08-30, 기기 채점 실측). 부서가 틀린 5장이 **전부 이 모양**
        //    이었다.
        //
        // ```
        // 대리 / 구로지점 / 제1영업본부   →  부서 「제1영업본부」  ← 구로지점을 잃었다
        // 팀장 서울사업팀 서울동부지사     →  부서 「서울사업팀」    ← 지사를 잃었다
        // ```
        //
        // 원인이 둘이었다.
        //
        // ① **되짚기가 구분자에서 멈췄다** — `/` 는 `bareOf` 로 빈 문자열이
        //    되는데 그때 `break` 했다. 구분자는 **넘어가야** 그 앞 조각까지
        //    닿는다. 다만 **연달아 비면 멈춘다**(줄이 끊긴 것으로 본다).
        // ② **앞으로만 갔다** — 상위 조직이 뒤에 오는 명함이 있다
        //    (`서울사업팀 서울동부지사`). 조직 꼬리가 붙은 토큰이면 이어 간다.
        //
        // ⚠️ **조직 꼬리를 이 자리에서만 넓힌다.** `지사`·`지점`·`부문`은 줄
        //    전체를 가릴 때 쓰기엔 위험하지만, **이미 부서 토큰에 잇닿아 있는
        //    조각**이라 부서일 가능성이 훨씬 높다.
        bool orgTail(String t) =>
            RegExp(r'(지점|지사|부문|사업부|연구소|본부|센터)$').hasMatch(t);
        for (var i = 0; i < tokens.length; i++) {
          final bare = bareOf(tokens[i]);
          if (bare.isEmpty || !_departmentSuffixes.any(bare.endsWith)) continue;
          isDept[i] = true;
          var blanks = 0;
          for (var j = i - 1; j >= 0 && !isDept[j]; j--) {
            final prev = bareOf(tokens[j]);
            if (prev.isEmpty) {
              if (++blanks >= 2) break; // 연달아 비면 줄이 끊긴 것이다
              continue;
            }
            blanks = 0;
            if (_titleKeywords.any((k) => _containsCi(prev, k))) break;
            isDept[j] = true;
          }
          blanks = 0;
          for (var j = i + 1; j < tokens.length && !isDept[j]; j++) {
            final next = bareOf(tokens[j]);
            if (next.isEmpty) {
              if (++blanks >= 2) break;
              continue;
            }
            blanks = 0;
            if (_titleKeywords.any((k) => _containsCi(next, k))) break;
            // ⚠️ 뒤쪽은 **조직 꼬리가 있을 때만** 이어 간다 — 앞쪽과 달리
            //    회사명·이름이 뒤따르는 줄이 흔하다.
            if (!orgTail(next) && !_departmentSuffixes.any(next.endsWith)) {
              break;
            }
            isDept[j] = true;
          }
        }
        // ⚠️ **부서 조각 사이의 구분자는 살린다.** 명함에 `구로지점 / 제1영업본부`
        //    로 찍혀 있으면 `/` 까지가 그 사람이 받은 표기다 — 공백으로 바꾸면
        //    **인쇄된 것과 다른 값**이 된다(정답지도 `/` 를 지운 것과 남긴 것을
        //    구분해 적고 있다).
        final first = isDept.indexOf(true);
        final last = isDept.lastIndexOf(true);
        final deptTokens = <String>[];
        final restTokens = <String>[];
        for (var i = 0; i < tokens.length; i++) {
          if (isDept[i]) {
            deptTokens.add(bareOf(tokens[i]));
          } else if (first >= 0 && i > first && i < last &&
              bareOf(tokens[i]).isEmpty) {
            // 부서 조각 **사이**에 낀 구분자다. 직함 쪽으로 보내지 않는다.
            deptTokens.add(tokens[i]);
          } else {
            restTokens.add(tokens[i]);
          }
        }
        if (deptTokens.isNotEmpty && restTokens.isNotEmpty) {
          department = deptTokens.join(' ');
          title = restTokens
              .join(' ')
              .replaceAll(RegExp(r'^[\s|:/,.·]+|[\s|:/,.·]+$'), '')
              .trim();
        }
      }
    }

    // 🚨 `/`·`|` 로 묶여 들어온 직함을 마지막에 가른다(2026-08-29, 52장 실측).
    //    52장 중 직함이 이상한 19장의 **절반이 이 모양**이었고, 잘려 나간
    //    조각 상당수가 **부서**였다(부서 채움률은 21%였다).
    //
    // ⚠️ **여기서 한다.** 앞에서 가르면 그 뒤의 검사들이 조각난 값을 보고
    //    다르게 움직인다 — 지금 잘 되는 것을 흔들지 않으려면 마지막이 안전하다.
    final split = _splitTitleSegments(title);
    title = split.title;

    // 🚨 **회사명이 직함 줄 한가운데 박혀 있는 명함**(2026-08-30, 추가 615).
    //
    // ```
    // K.ACE LAB 케이스랩 개발실장     ← 로고 · 회사 · 직함이 한 줄이다
    // ```
    //
    // ⭐ **이것은 「고르기」로는 못 닿는다.** 자국을 심어 보니 `케이스랩` 이
    // `leftover` 에 **아예 오지 않았다** — 이 줄이 통째로 직함으로 잡혀서다.
    // 그동안 회사 칸에는 엉뚱한 값이 들어갔다(`Hong Gyu, Park` · 주소 조각).
    //
    // ⚠️ **아주 좁게 건다.** 앞이 순수 영문이고, 그 뒤가 **한글 두 덩어리**이고,
    // **마지막만** 직함 낱말일 때다. 하나라도 어긋나면 손대지 않는다.
    //
    // ⚠️ **키워드로 이미 회사를 찾았으면 덮지 않는다** — 그쪽이 근거가 세다.
    final inTitle = RegExp(
      r'^([A-Za-z][A-Za-z.&-]*(?:\s+[A-Za-z][A-Za-z.&-]*)*)\s+'
      r'([가-힣]{2,10})\s+([가-힣]{2,10})$',
    ).firstMatch(title);
    if (inTitle != null && companySource != OcrCompanySource.keyword) {
      final mid = inTitle.group(2)!;
      final tail = inTitle.group(3)!;
      final midIsDept = RegExp(
        r'(팀|부|실|과|처|국|센터|본부|그룹|파트|연구소|부문|지사|지점|단)$',
      ).hasMatch(mid);
      if (!midIsDept &&
          _titleKeywords.any((k) => _containsCi(tail, k)) &&
          !_titleKeywords.any((k) => _containsCi(mid, k))) {
        company = _tidyCompany(mid);
        title = tail;
      }
    }
    // 🚨 가른 **뒤에** 본다 — `부장 / 이주배경청소년지원재단.`처럼 묶여 온
    //    경우 가르기가 먼저 직함을 건져 낼 수 있다.
    if (_isNotTitle(title)) title = '';

    // 🚨 직함 끝에 이름이 붙어 온 경우를 뗀다(2026-08-29). 이름 칸이 비어
    //    있을 때만 옮긴다 — 이미 찾은 이름을 덮지 않는다.
    final tailSplit = _splitTrailingName(title);
    if (tailSplit.name != null) {
      title = tailSplit.title;
      // ⚠️ 비어 있을 때뿐 아니라 **영문 후보가 들어 있을 때도** 바꾼다.
      //    실측에서 로고 글씨(ARENA FITNESS)가 이름 자리를 차지한 채
      //    진짜 한글 이름을 막고 있었다.
      if (name.isEmpty || !_hasHangul(name)) name = tailSplit.name!;
    }

    // 🚨 **부서가 한 줄로 따로 있으면 아예 못 쓰고 있었다**(2026-08-29, 실측).
    //
    // ```
    // 마케팅팀 (한 줄)  →  부서 [] · 직함 [마케팅팀]   ← 직함으로 먹히거나 버려짐
    // ```
    //
    // 부서 채움률이 낮았던 큰 이유가 이것이다. 회사·직함·이름으로 쓰이지 않고
    // 남은 줄 중에 **부서 모양**이 있으면 부서로 쓴다.
    //
    // ⚠️ **이미 정한 값은 건드리지 않는다.** 회사로 고른 줄, 이름, 직함은
    //    제외하고 본다 — `무지개청소년 센터`처럼 회사면서 센터로 끝나는
    //    이름을 부서로 끌어오면 안 된다.
    if (department.isEmpty) {
      for (final l in leftover) {
        final t = l.trim();
        // ⚠️ **길이를 30자로 넓혔다**(2026-08-30, 실측). `DX사업본부 공공시스템부문
        //    공공시스템2팀`(25자)처럼 계층을 다 적은 부서가 20자에서 잘렸다.
        if (t.isEmpty || t.length > 30) continue;
        if (t == company || t == name || t == title) continue;
        // ⚠️ 글머리 기호로 시작하는 줄은 **인증·수상 배지**다(실측에서
        //    `•산업통상자원부`가 부서로 들어왔다). 부서가 아니다.
        if (RegExp(r'^[•·※▪◦①-⑳-]').hasMatch(t)) continue;
        // ⚠️ **정부 부처는 그 사람의 부서가 아니다.** 인증·수상 배지에
        //    찍혀 있다(실측: `③산업통상자원부`, `G 중소벤처기업부`).
        if (_ministryNames.any(t.endsWith)) continue;
        // 🚨 **영문 조직 줄도 본다**(2026-08-30). `UX Group. Executive Leader`
        //    처럼 **부서와 직함이 마침표로 이어진 영문 줄**이 있다. 예전에는
        //    한글이 없으면 건너뛰어, 이 줄이 직함 줄로 안 잡히는 순간 부서를
        //    통째로 잃었다.
        //
        // ⚠️ **조직 꼬리로 끝나는 앞부분만** 가져온다 — 뒤쪽(`Executive
        //    Leader`)은 직함이다.
        if (!_hasHangul(t)) {
          final m = RegExp(
            r'^(.{2,24}?(?:Center|Centre|Group|Team|Division|Dept|Department|'
            r'Lab|Unit|Office))\.\s+\S',
            caseSensitive: false,
          ).firstMatch(t);
          if (m == null) continue;
          final head = m.group(1)!.trim();
          if (head == company || head == name || head == title) continue;
          // ⚠️ **`Head of R&D Dept.` 는 부서가 아니라 직함이다**(실측에서 2장이
          //    부서 칸에 들어갔다). 조직 꼬리로 끝나도 **앞에 직함 낱말이
          //    있으면** 그 사람의 자리를 말하는 것이다.
          if (RegExp(
            r'(?<![A-Za-z])(Head|Chief|Director|Manager|Leader|Officer|'
            r'President|VP)(?![A-Za-z])',
            caseSensitive: false,
          ).hasMatch(head)) {
            continue;
          }
          department = head;
          break;
        }
        // 🚨 **칸막이로 이어 적은 부서를 통째로 버리고 있었다**(2026-08-30, 실측).
        //
        // ```
        // 매니지드운영본부 | 매니지드운영 팀   →  아무 칸에도 안 들어갔다
        // 기술평가부문 | 기술인증평가단
        // ```
        //
        // 예전에는 `|` 가 들어간 줄을 통째로 건너뛰었다 — `A | B` 가 **회사와
        // 부서**인 경우를 막으려던 것이다. 그런데 **양쪽이 다 조직 단위면**
        // 그건 한 부서를 두 단계로 적은 것이다.
        //
        // ⚠️ **한쪽이라도 조직 모양이 아니면 예전처럼 건너뛴다.**
        bool deptShape(String x) =>
            _departmentSuffixes.any(x.endsWith) ||
            RegExp(
              r'(팀|부|실|과|처|국|센터|본부|그룹|파트|연구소|부문|지사|지점)$',
            ).hasMatch(x) ||
            // ⚠️ `기술인증평가단`·`사업단` 은 부서다. 다만 **`재단` 은 회사**이므로
            //    바로 앞 글자가 `재` 면 뺀다(`서울관광재단`).
            RegExp(r'(?<!재)단$').hasMatch(x);
        // 🚨 **줄 앞에 로고 조각이 한두 글자 붙어 온다**(`0 기업부설연구소` —
        //    올빼미 로고를 `0` 으로 읽었다).
        //
        // ⚠️ **이 규칙은 오늘 한 번 뺐다가 다시 넣었다.** 처음 넣었을 때는
        //    숫자가 안 움직여서 *「재서 안 나온 규칙은 남기지 않는다」* 로
        //    뺐다([추가 599]). 그런데 회사 고르기를 고치자(이 PR) **그 줄이
        //    비로소 부서 후보까지 오게 됐고**, 그제야 효과가 생겼다.
        //
        // 📌 **조건이 바뀌면 다시 잰다** — 「그때 효과가 없었다」가 「지금도
        //    없다」는 뜻은 아니다.
        var t2 = t.replaceFirst(RegExp(r'^[^가-힣A-Za-z(]{1,2}\s+'), '');
        var candidate = t2;
        if (t2.contains('|')) {
          final parts = t2
              .split(RegExp(r'\s*\|\s*'))
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .toList();
          if (parts.length < 2 || !parts.every(deptShape)) continue;
          candidate = parts.join(' ');
        }
        if (!deptShape(candidate)) continue;
        if (_titleKeywords.any((k) => _containsCi(candidate, k))) continue;
        // ⚠️ **법인 표기가 붙어 있으면 회사다.** `주식회사 디엠지그룹`이
        //    「그룹」으로 끝나 부서로 끌려 들어왔다(정답 대비 실측).
        if (RegExp(r'\(주\)|\(유\)|주식회사|유한회사|사단법인|재단법인')
            .hasMatch(t)) {
          continue;
        }
        department = candidate;
        break;
      }
    }
    if (department.isEmpty && split.department != null) {
      department = split.department!;
    }

    department = _tidyDepartment(department);

    // 🚨 **상위 조직이 윗줄에 따로 찍힌 명함**(2026-08-30, 기기 채점 실측).
    //
    // ```
    // 서울컨벤션뷰로            ← 이 줄을 통째로 잃고 있었다
    // MICE지원팀 | 주임
    // ```
    //
    // 부서를 집어 온 줄의 **바로 윗줄**이 조직 이름이면 그것까지가 부서다.
    // 실측에서 이 모양이 셋이었다(`card_205`·`212`·`213`, 전부 서울관광재단).
    //
    // ⚠️ **바로 위 한 줄만 본다.** 더 올라가면 회사명·슬로건에 닿는다.
    // ⚠️ **회사로 고른 줄은 절대 안 붙인다** — `서울관광재단`이 회사고
    //    `서울컨벤션뷰로`는 그 안의 본부다. 둘을 섞으면 회사를 잃는다.
    if (department.isNotEmpty) {
      final idx = lines.indexWhere((l) => l.contains(department));
      if (idx > 0) {
        // ⚠️ **윗줄 끝에 로고가 붙어 오는 일이 잦다** — `서울컨벤션뷰로 PLUS
        //    SEOUL` 처럼. 그래서 줄 전체가 아니라 **앞머리 한글 덩어리**를 본다.
        final rawAbove = lines[idx - 1].trim();
        final headMatch = RegExp(r'^[가-힣][가-힣\s]*').firstMatch(rawAbove);
        final above = (headMatch?.group(0) ?? rawAbove).trim();
        final aboveOrg =
            above.length >= 2 &&
            above.length <= 20 &&
            _hasHangul(above) &&
            RegExp(r'(뷰로|본부|사업부|부문|센터|연구소|지사|지점|단)$')
                .hasMatch(above) &&
            !_isSameOrg(above, company) &&
            above != name &&
            above != title &&
            !department.contains(above) &&
            !_titleKeywords.any((k) => _containsCi(above, k)) &&
            !_ministryNames.any(above.endsWith) &&
            !RegExp(r'\(주\)|\(유\)|주식회사|유한회사|사단법인|재단법인')
                .hasMatch(above);
        if (aboveOrg) department = '$above $department';
      }
    }

    final rawText = lines.join('\n');

    final shape = OcrParseShape(
      lineCount: lines.length,
      rawLength: rawText.length,
      nameFilled: name.isNotEmpty,
      companyFilled: company.isNotEmpty,
      titleFilled: title.isNotEmpty,
      mobileFilled: (mobile ?? '').isNotEmpty,
      officeFilled: (office ?? '').isNotEmpty,
      emailFilled: (email ?? '').isNotEmpty,
      addressFilled: (address ?? '').isNotEmpty,
      addressDetailFilled: (addressDetail ?? '').isNotEmpty,
      postalFilled: (postalCode ?? '').isNotEmpty,
      nameSource: nameSource,
      companySource: companySource,
    );

    return OcrScanResult(
      rawText: rawText.isEmpty ? '[텍스트를 인식하지 못했습니다]' : rawText,
      // 터치 퀵 매핑 UI(명함 등록 화면)가 이 목록을 칩으로 깔고, 사용자가
      // 잘못 배정된 값을 직접 눌러 다른 칸으로 옮긴다. 여기서 안 채우면
      // 기본값 const []가 그대로 나가 UI가 **조용히 안 뜬다**(2026-08-13
      // 실기기 확인, backlog 추가 178).
      rawLines: lines,
      rawLineBoxes: lineData,
      name: name,
      company: company,
      title: title,
      department: department,
      phone: mobile ?? '',
      officePhone: office ?? '',
      fax: fax ?? '',
      email: email ?? '',
      website: website ?? '',
      addressDetail: _stripBrandNoiseFromAddressDetail(addressDetail ?? ''),
      postalCode: postalCode ?? '',
      address: address ?? '',
      tags: const [],
      avatarUrl: null,
      imagePath: imagePath,
      parseShape: shape,
    );
  }

  /// 상세주소 줄에 명함과 무관한 **영문 로고·브랜드 잔재**가 섞여 들어오는
  /// 것을 막는다(테스터 제보, 2026-08-20).
  ///
  /// 원인: 상세주소를 채우는 두 경로(층/호 패턴이 걸린 줄을 통째로 쓰는
  /// 직접 매칭, 그리고 "주소 다음 줄에 숫자가 있으면 줄 전체" 폴백)가 모두
  /// **줄 전체**를 그대로 담는다. 명함이 2단 레이아웃이면 `_extractOrderedLines`가
  /// 같은 높이의 서로 다른 열을 한 줄로 합치는 일이 흔해서, 층수 옆에 로고체
  /// 브랜드명이 붙어 함께 읽히는 경우가 있다(`5층 ARCTERYX`).
  ///
  /// ⚠️ **한글 꼬리는 건드리지 않는다.** "3층 인사팀"처럼 부서명이 실제로
  /// 상세주소 줄에 함께 인쇄되는 경우가 흔해서 회귀 테스트로 이미 고정돼
  /// 있다. 그래서 **순수 로마자 대문자로만 된 토큰**(숫자·한글이 하나도
  /// 안 섞인, 로고체 표기의 전형적인 모양)만 앞뒤 끝에서 뗀다. 중간 토큰이나
  /// 숫자·기호가 섞인 토큰(`B1F`처럼 실제 상세주소 표기일 수 있는 것)은
  /// 손대지 않는다 — 확신 없이 떼면 진짜 상세주소를 깎을 수 있다.
  static String _stripBrandNoiseFromAddressDetail(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) return trimmed;
    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.length < 2) return trimmed;

    bool isBrandNoiseToken(String t) {
      // 숫자·한글·기호가 하나라도 섞이면 주소 표기(동/호수/층수 등)일 수
      // 있으므로 순수 로마자 토큰만 본다.
      if (!RegExp(r'^[A-Za-z]+$').hasMatch(t)) return false;
      if (t.length < 3) return false;
      return t == t.toUpperCase();
    }

    var start = 0;
    var end = tokens.length;
    while (start < end && isBrandNoiseToken(tokens[start])) {
      start++;
    }
    while (end > start && isBrandNoiseToken(tokens[end - 1])) {
      end--;
    }
    // 토큰이 전부 로고 잡음으로 판정되면(=상세주소 전체가 영문 대문자뿐이면)
    // 뗄 근거가 약하다 — 그대로 둔다. 판정은 "명백한 잔재를 거른다"는 것이지
    // "영문 상세주소는 없다"는 것이 아니다.
    if (start >= end) return trimmed;
    if (start == 0 && end == tokens.length) return trimmed;
    return tokens.sublist(start, end).join(' ');
  }

  /// 숫자와 헷갈리기 쉬운 알파벳(0↔O)을 전화번호 패턴 매칭 전에 바로잡는다.
  /// 숫자와 바로 붙어 있는 O/o만 0으로 바꾸므로("MO10" → "M010"), 회사명
  /// 등 다른 곳의 진짜 알파벳 O는 건드리지 않는다.
  static String _normalizePhoneLookalikes(String line) {
    final buffer = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == 'O' || c == 'o') {
        final prevIsDigit = i > 0 && RegExp(r'[0-9]').hasMatch(line[i - 1]);
        final nextIsDigit =
            i + 1 < line.length && RegExp(r'[0-9]').hasMatch(line[i + 1]);
        buffer.write(prevIsDigit || nextIsDigit ? '0' : c);
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }

  static String _normalizePhone(String raw) {
    // "(02)855-5900"처럼 지역번호를 괄호로 감싼 표기를 매칭할 때 정규식이
    // 괄호까지 통째로 캡처한다(mobileRegExp/officeRegExp가 ')'도 구분자로
    // 허용하기 때문) — 자릿수를 세기 전에 괄호부터 지운다.
    final cleanedRaw = raw.replaceAll(RegExp(r'[()]'), '');
    final digits = cleanedRaw.replaceAll(RegExp(r'[^0-9]'), '');
    // ⚠️ 서울(02)은 **지역번호가 두 자리**다. 자릿수만 보고 3-3-4로 끊으면
    // `02-3446-9300`(10자리)이 `023-446-9300`이 된다 — 국번이 4자리인 서울
    // 번호가 전부 이렇게 깨졌다(2026-08-14 발견, backlog 추가 197).
    if (digits.startsWith('02')) {
      if (digits.length == 10) {
        return '02-${digits.substring(2, 6)}-${digits.substring(6)}';
      }
      if (digits.length == 9) {
        return '02-${digits.substring(2, 5)}-${digits.substring(5)}';
      }
    }
    // 대표번호(15xx·16xx·17xx·18xx)는 **네 자리씩 끊는다** — `1877-9920`.
    // 자릿수 규칙(3-3-4)에 맡기면 `187-799-20` 꼴이 된다.
    if (digits.length == 8 && RegExp(r'^1[5-8]').hasMatch(digits)) {
      return '${digits.substring(0, 4)}-${digits.substring(4)}';
    }
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    // 9자리(예: 서울 지역번호 2자리 + 국번 3자리 + 4자리)도 흔한 유선전화
    // 자릿수라 보기 좋게 포맷한다. 그 외 자릿수는 괄호만 지운 원본을 그대로.
    if (digits.length == 9) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 5)}-${digits.substring(5)}';
    }
    return cleanedRaw;
  }
}
