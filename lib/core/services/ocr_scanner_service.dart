import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

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
  final String phone;
  final String officePhone;
  final String email;
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

  /// 이 결과가 "어떻게" 만들어졌는지에 대한 형태 정보(내용 없음). 인식 품질
  /// 측정용이라 앱 화면에는 안 쓴다. 테스트에서 만든 결과 등에는 없을 수 있어
  /// nullable.
  final OcrParseShape? parseShape;

  const OcrScanResult({
    required this.rawText,
    this.rawLines = const [],
    required this.name,
    required this.company,
    required this.title,
    required this.phone,
    required this.officePhone,
    required this.email,
    required this.address,
    this.addressDetail = '',
    this.postalCode = '',
    required this.tags,
    this.avatarUrl,
    this.imagePath,
    this.parseShape,
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
      // ML Kit이 예외 없이 끝없이 대기만 하는 경우가 있어(촬영 화면이
      // "AI 텍스트 추출 중..."에서 멈추는 문제로 실기기에서 확인됨) 타임아웃을
      // 걸어 일정 시간 안에 안 끝나면 실패로 처리한다.
      final recognizedText = await recognizer
          .processImage(inputImage)
          .timeout(const Duration(seconds: 20));
      var orderedLines = _extractOrderedLines(recognizedText);

      // Dual-Pass OCR: 마진 크롭으로 텍스트가 극히 일부만 읽혔거나 잘린 경우
      // (인식된 총 길이 < 8), 원본 이미지 전체로 2차 풀 스캔을 시도한다.
      final totalLen = orderedLines.fold<int>(0, (sum, l) => sum + l.text.length);
      if (totalLen < 8) {
        debugPrint('OCR 1차 크롭 결과 부족($totalLen자) -> 2차 풀 스캔 자동 실행');
        final rawInput = InputImage.fromFilePath(imageFile.path);
        final rawRecognized = await recognizer
            .processImage(rawInput)
            .timeout(const Duration(seconds: 15));
        final rawOrdered = _extractOrderedLines(rawRecognized);
        if (rawOrdered.fold<int>(0, (sum, l) => sum + l.text.length) > totalLen) {
          orderedLines = rawOrdered;
        }
      }

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
  static List<({String text, double height})> _extractOrderedLines(
    RecognizedText recognizedText,
  ) {
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
          return (text: text, height: height);
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

  static const _companyKeywords = [
    '주식회사',
    '(주)',
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
    // 2026-08-13: 회사 접미사 확장. 위 "연구원을 넣지 않는다"와 같은 이유로,
    // 부분 문자열로 엉뚱하게 걸리는 단어는 뺐다 — 'AI'는 이메일 줄의
    // "e-m**ai**l"에, 'Tech'는 직함 "**Tech**nical Director"에, 'Lab'은
    // "Co**lab**oration"에 걸린다. 'Global'은 실제로 부서명 "Global Sales
    // Division"을 회사명 자리로 끌어와 테스트가 깨졌다(부서명이 회사명을
    // 뺏는 문제는 아래 _departmentSuffixes 주석의 실사용 버그와 같은 계열).
    // 한글 표기('테크'·'바이오'·'글로벌')는 겹칠 여지가 없어 그대로 둔다.
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
  ];

  // 회사명에 위 키워드가 하나도 안 걸릴 때(예: "Sovargen", "SSiS
  // 한국사회보장정보원"처럼 접미사 없는 브랜드명/영문명) leftover 맨 앞
  // 줄을 무조건 회사명으로 쓰면, 부서명이나 슬로건 같은 줄이 대신 들어가는
  // 문제가 실제 명함 3장(이정현·최서연·이상헌, Sovargen/SSIS)에서
  // 확인됐다 — "경영기획실", "국민 맞춤형 복지를 실현하는..." 같은 줄이
  // 회사명 자리를 차지했다. 부서명 흔한 접미사로 끝나는 줄만 후순위로
  // 미룬다("팀"/"실"/"국"/"처" 같은 짧은 접미사는 정상적인 회사명 끝
  // 글자와도 우연히 겹칠 수 있어 긴 접미사부터 확인).
  static const _departmentSuffixes = [
    '사업본부',
    '기획실',
    '관리부',
    '지원부',
    '지원실',
    '사업부',
    '부서',
    '본부',
    '센터',
    '팀',
    '실',
    '국',
    '처',
  ];

  static final _koreanNameRegExp = RegExp(r'^[가-힣]{2,4}$');
  static final _singleHangulRegExp = RegExp(r'^[가-힣]$');
  static final _whitespaceSplitRegExp = RegExp(r'[\s　]+');

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
      if (tokens[idx].length == 1 && _singleHangulRegExp.hasMatch(tokens[idx])) {
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

  static bool _looksLikeDeptOrTagline(String line) {
    final trimmed = line.trim();
    final endsWithDeptSuffix = _departmentSuffixes.any(trimmed.endsWith);
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
    final bestIndex = leftover.indexWhere(
      (l) => !_looksLikeDeptOrTagline(l) && !_looksLikeLogoNoise(l),
    );
    if (bestIndex != -1) return leftover.removeAt(bestIndex);
    final betterIndex = leftover.indexWhere(
      (l) => !_looksLikeDeptOrTagline(l),
    );
    final idx = betterIndex != -1 ? betterIndex : 0;
    return leftover.removeAt(idx);
  }

  /// `_parse`는 파일 내부 전용이라 다른 파일(테스트 포함)에서 직접 못
  /// 부른다 — ML Kit 인식 결과를 흉내 낸 줄 목록으로 필드 분류 규칙만
  /// 따로 검증할 수 있도록 테스트 전용 통로를 열어둔다. 실제 앱 코드에서는
  /// 쓰지 않는다.
  @visibleForTesting
  static OcrScanResult parseLinesForTesting(List<String> lines) => _parse(
    [for (final l in lines) (text: l, height: 0.0)],
    '',
  );

  /// 글자 높이까지 넣어 파싱 규칙을 검증하는 테스트 통로 — 이름을 규칙으로
  /// 확신하지 못했을 때 글자 크기 폴백이 제대로 동작하는지 확인하는 용도.
  @visibleForTesting
  static OcrScanResult parseLinesForTestingWithHeights(
    List<({String text, double height})> lineData,
  ) => _parse(lineData, '');

  static OcrScanResult _parse(
    List<({String text, double height})> lineData,
    String imagePath,
  ) {
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
    final mobileRegExp = RegExp(r'01[0-9][-.\s)]?\d{3,4}[-.\s]?\d{4}');
    // 02(서울)/031~069(지역 국번) 외에 070(인터넷전화)도 요즘 명함에 흔히
    // 쓰이는데 빠져 있었음 — 회사 전화번호가 있어도 인식이 안 되는 원인이었음.
    final officeRegExp = RegExp(
      r'0(2|[3-6][0-9]|70)[-.\s)]?\d{3,4}[-.\s]?\d{4}',
    );
    // 광역시/도. 줄임말(충북)과 풀네임(충청북도)이 둘 다 명함에 쓰이는데,
    // 예전엔 줄임말만 있어서 "충청북도 청주시..."처럼 풀네임으로 쓴 주소를
    // 통째로 놓쳤다(2026-08-11 측정에서 주소가 최대 오인식 지점으로 확인됨).
    // 서울/강원/제주/세종은 풀네임이 줄임말을 접두어로 포함하므로 그대로 둔다.
    final addressRegExp = RegExp(
      r'(서울|경기|인천|부산|대구|광주|대전|울산|세종|강원|충청북도|충청남도|충북|충남|전라북도|전라남도|전북|전남|경상북도|경상남도|경북|경남|제주)[^\n]*(로|길|동|구)[^\n]*',
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
    String? office;
    String? email;
    String? address;
    String? addressDetail;
    String? postalCode;
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

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
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
        email = emailMatch.group(0)!.replaceAll(RegExp(r'\s+'), '');
        matchedRanges.add((emailMatch.start, emailMatch.end));
        matchedContactField = true;
      }
      // OCR이 전화번호 라벨("M "/"T ") 바로 뒤에 오는 숫자 0을 알파벳 O로
      // 잘못 읽는 경우가 실기기에서 확인됐다(예: "M 010-..." → "MO10-...").
      // 휴대폰/사무실 전화 패턴 매칭에만 쓰는 임시 정규화 버전을 따로 만들어
      // 적용한다 — 원본 line은 그대로 둬서 이메일/주소/이름 판별에는 영향을
      // 주지 않는다(글자 수가 같은 치환이라 매칭 위치는 원본과 동일하다).
      final phoneLookup = _normalizePhoneLookalikes(line);
      final mobileMatch = mobileRegExp.firstMatch(phoneLookup);
      if (mobile == null && mobileMatch != null) {
        mobile = _normalizePhone(mobileMatch.group(0)!);
        matchedRanges.add((mobileMatch.start, mobileMatch.end));
        matchedContactField = true;
      }
      final officeMatch = officeRegExp.firstMatch(phoneLookup);
      if (officeMatch != null) {
        // 팩스 번호가 사무실 전화로 잘못 들어가는 문제(실제 명함에서 흔함 —
        // "fax 070-...", "팩스 02-..."). 팩스 라벨이 붙은 줄이면 사무실
        // 전화로 배정하지 않는다. 단 번호 자체는 줄에서 걷어내야 이름/회사로
        // 오분류되지 않으므로, 배정과 무관하게 매칭 구간은 지운다.
        if (office == null && !_looksLikeFaxLine(line)) {
          office = _normalizePhone(officeMatch.group(0)!);
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
          remaining.add(remainder);
        }
        continue;
      }

      // 광역시/도로 시작하는 주소를 먼저 보고, 없으면 "시/군/구 + 로/길 +
      // 숫자" 형태(도/시 생략 주소)로 보완한다.
      final addressMatch = addressRegExp.firstMatch(line) ??
          roadAddressNoProvinceRegExp.firstMatch(line);
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
        var matched = addressMatch.group(0)!.trim();
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
      if (addressDetail == null &&
          addressLineIndex != null &&
          lineIndex == addressLineIndex + 1) {
        addressDetail = line.trim();
        continue;
      }
      remaining.add(line);
    }

    // 직함/회사 키워드로 먼저 매칭하고, 순수 한글 2~4자 줄은 이름 후보로 잡는다.
    // 셋 다 못 찾은 나머지는 예전처럼 "남은 줄 중 앞에서부터" 순서로 채운다.
    String? titleLine;
    String? companyLine;
    String? nameLine;
    // 이름/회사명을 "어떤 규칙으로" 뽑았는지 기록한다(값이 아니라 경로만).
    // 인식 품질 측정용 — 약한 폴백 비율이 얼마나 되는지 보기 위함.
    var nameSource = OcrNameSource.none;
    var companySource = OcrCompanySource.none;
    final leftover = <String>[];

    for (final line in remaining) {
      // 직함 키워드가 걸린 줄에 이름도 같이 붙어 있는 경우가 실제 명함
      // 샘플에서 흔하게 확인됐다 — "실장 곽용환"(키워드 먼저), "이정섭
      // 부장"(이름 먼저), "윤 덕 현 컨설팅 및 딜리버리 팀장"(이름이 한
      // 글자씩 띄어져 있고 직함은 길게 서술형)까지 순서와 형태가 제각각.
      // 줄 전체를 직함으로 삼으면 이름을 영영 못 찾으므로 토큰 단위로
      // 분리를 시도한다.
      final matchedTitleKeyword = _titleKeywords.firstWhere(
        (k) => _containsCi(line, k),
        orElse: () => '',
      );
      if (titleLine == null && matchedTitleKeyword.isNotEmpty) {
        final split = _splitNameFromTitleLine(line, matchedTitleKeyword);
        if (nameLine == null && split != null) {
          nameLine = split.name;
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
      if (companyLine == null &&
          _companyKeywords.any((k) => _containsCi(line, k))) {
        companyLine = line;
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
      if (nameLine == null && _koreanNameRegExp.hasMatch(strippedForName)) {
        nameLine = strippedForName;
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
      final hasNonHangul = line
          .replaceAll(RegExp(r'[가-힣\s]'), '')
          .isNotEmpty;
      if (nameLine == null && hasNonHangul) {
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
              _koreanNameRegExp.hasMatch(frontBuffer.toString())) {
            nameLine = frontBuffer.toString();
            nameSource = OcrNameSource.mixedTokenFront;
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
          if (_koreanNameRegExp.hasMatch(tokens.last)) {
            nameLine = tokens.last;
            nameSource = OcrNameSource.mixedTokenLast;
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
      leftover.add(line);
    }

    String name;
    if (nameLine != null) {
      name = nameLine;
    } else if (leftover.isEmpty) {
      name = '';
      nameSource = OcrNameSource.none;
    } else {
      // 규칙으로 이름을 확신하지 못한 약한 폴백 구간이다. 예전엔 남은 줄 "맨
      // 앞"(읽기 순서)을 그냥 이름으로 썼는데, 명함에서 이름은 대개 가장 크게
      // 인쇄되므로 글자 높이를 아는 경우엔 "가장 큰 줄"을 이름으로 고른다.
      // 높이 정보가 전혀 없으면(테스트 입력 등) 기존과 똑같이 맨 앞 줄을 쓴다 —
      // 그래서 이 개선은 확신 경로를 건드리지 않고 약한 폴백만 바꾼다.
      final withHeight = leftover
          .where((l) => (heightByText[l] ?? 0) > 0)
          .toList();
      if (withHeight.length >= 2) {
        withHeight.sort(
          (a, b) => (heightByText[b] ?? 0).compareTo(heightByText[a] ?? 0),
        );
        final biggest = withHeight.first;
        // 가장 큰 줄이 실제로 맨 앞 줄보다 눈에 띄게 커야 이름으로 본다(살짝
        // 큰 정도는 잡음일 수 있어 10% 여유를 둔다). 그렇지 않으면 기존
        // 동작(맨 앞 줄)을 유지한다.
        final biggestH = heightByText[biggest] ?? 0;
        final firstH = heightByText[leftover.first] ?? 0;
        if (biggest != leftover.first && biggestH >= firstH * 1.1) {
          name = biggest;
          leftover.remove(biggest);
          nameSource = OcrNameSource.fontSizePreferred;
        } else {
          name = leftover.removeAt(0);
          nameSource = OcrNameSource.leftoverFallback;
        }
      } else {
        name = leftover.removeAt(0);
        nameSource = OcrNameSource.leftoverFallback;
      }
    }

    final companyFromKeyword = companyLine;
    final company = companyFromKeyword ?? _pickCompanyFromLeftover(leftover) ?? '';
    if (companyFromKeyword == null) {
      companySource = company.isEmpty
          ? OcrCompanySource.none
          : OcrCompanySource.leftoverPick;
    }

    final title =
        titleLine ?? (leftover.isNotEmpty ? leftover.removeAt(0) : '');

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
      name: name,
      company: company,
      title: title,
      phone: mobile ?? '',
      officePhone: office ?? '',
      email: email ?? '',
      addressDetail: addressDetail ?? '',
      postalCode: postalCode ?? '',
      address: address ?? '',
      tags: const [],
      avatarUrl: null,
      imagePath: imagePath,
      parseShape: shape,
    );
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
