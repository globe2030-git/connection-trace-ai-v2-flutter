/// OCR **측정 전용** 기록기 — 명함별 인식 줄과 이름 경로를 파일로 남긴다.
///
/// ## 왜 필요한가 (추가 405)
///
/// 파서를 고칠 때 *"전체적으로 좋아졌는가"*를 알려면 명함별 대조가 있어야 한다.
/// 그런데 앱은 **명함별 OCR 원문을 저장하지 않고**, 진단 화면은 경로별
/// **합계만** 준다.
///
/// 2026-08-22에는 macOS Vision으로 촬영본에서 줄을 뽑아 파서에 넣어 쟀다. 그
/// 자로 76% → 90%를 만들었지만, **앱은 ML Kit을 쓴다** — 같은 명함이라도 줄
/// 나눔이 달라 경로와 결과가 갈릴 수 있다. 그래서 **기기에서 실제로 도는 줄**로
/// 다시 재야 한다.
///
/// ## ⚠️ 기본 꺼짐이고, 켜도 등록하지 않는다
///
/// `--dart-define=OCR_MEASURE_DUMP=true`로 빌드했을 때만 동작한다. 자리채움
/// 정리 빌드(`RELAX_REQUIRED_FOR_CLEANUP`)와 같은 손이다.
///
/// 측정 경로는 **명함을 등록하지 않는다.** 101장을 재려고 등록하면 명함이 두
/// 배로 불어나고, 되돌리는 손이 만드는 손보다 커진다(2026-08-22 자리채움 정리에서
/// 실제로 겪었다).
///
/// ## ⚠️ 떨군 파일은 제3자 개인정보다
///
/// OCR 원문이 그대로 담긴다 — 이름·전화·이메일·주소가 들어 있다. 그래서
///
/// - 파일은 앱 전용 폴더에만 만든다(갤러리·공유 폴더에 두지 않는다)
/// - 기기에서 꺼낸 뒤 **기기 쪽 파일은 지운다**
/// - 보관은 `connection-sense-assets/명함데이터/`(권한 700) 규칙을 따른다
///
/// 측정이 끝나면 이 경로를 남길지 뺄지 정한다.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 측정 기록이 켜져 있는지. 기본(정의 안 함)에서는 항상 false다.
const bool ocrMeasureDumpEnabled = bool.fromEnvironment('OCR_MEASURE_DUMP');

/// 줄 사이 구분자. 파일에 줄바꿈을 쓸 수 없어(한 명함이 한 줄이어야 한다)
/// 제어문자를 쓴다. macOS Vision 쪽 도구와 **같은 형식**이라 그대로 대조된다.
const String kMeasureLineSep = '';

/// 한 줄 안에서 글자와 높이를 가르는 구분자.
const String kMeasureFieldSep = '';

/// 측정 파일 형식 판. **줄 높이만 남기던 v1에 토큰 칸을 더한 것이 v2다**(추가 409).
///
/// ⚠️ **판이 바뀌면 파일 이름도 바뀐다.** 같은 이름에 이어 쓰면 기기에 남아
/// 있던 지난 판 줄과 새 판 줄이 **한 파일에 섞인다.** 섞여도 앞 네 칸은
/// 그대로라 읽히기 때문에 **조용히 틀린 대조**가 된다 — 어긋난 것을 사람이
/// 알아채지 못한다.
const int kMeasureFormatVersion = 2;

/// 측정 파일 이름. 판마다 다르다(위 경고 참고).
const String kMeasureFileName = 'ocr_measure_v$kMeasureFormatVersion.tsv';

/// 측정 한 줄을 만든다. 형식은 Vision 도구와 같다.
///
/// ```
/// 사진이름 \t 글자높이  글자높이 … \t 경로 \t 뽑은이름
/// ```
///
/// ⚠️ 글자에 구분자가 섞이면 대조가 깨지므로 **미리 지운다.** OCR이 제어문자를
/// 돌려주는 일은 없지만, 깨지면 조용히 어긋나는 종류의 사고라 막아 둔다.
///
/// ## 토큰 칸을 왜 더했나 (추가 409)
///
/// 줄 높이는 **한 행으로 묶인 뒤의 값**이다. `_extractOrderedLines`가 좌우로
/// 나란한 줄을 한 행으로 합치면서 **높이를 그중 가장 큰 것으로** 잡는다.
/// 그래서 "홍길동  ㈜회사이름"처럼 이름과 회사가 나란히 인쇄돼 있으면
/// **회사까지 이름만큼 큰 것으로 기록된다.** 글자 크기로 이름을 고르는 규칙이
/// 흔들리는 자리가 여기다.
///
/// 그래서 **합치기 전의 낱말 상자**를 따로 남긴다. 위·왼 좌표를 같이 남기는
/// 것은 대조하는 쪽이 **행 묶음을 스스로 다시 만들 수 있게** 하려는 것이다 —
/// 앱의 묶는 규칙이 바뀌어도 지난 측정을 다시 해석할 수 있다.
///
/// ⚠️ **재료일 뿐 규칙이 아니다.** 토큰 높이로 이름을 고르는 규칙은 아직 만들지
/// 않았다. 먼저 재고, 기대 이득을 본 뒤에 정한다(PM 지시, 2026-08-23).
///
/// 토큰 칸은 **맨 뒤에** 붙였다. 앞 네 칸이 v1과 같아서 지난 판으로 만든 대조
/// 스크립트가 그대로 돈다.
String formatMeasureRow({
  required String imageName,
  required List<({String text, double height})> lines,
  required String nameSource,
  required String parsedName,
  List<({String text, double height, double top, double left})> tokens =
      const [],
}) {
  String clean(String s) =>
      s.replaceAll(kMeasureLineSep, ' ').replaceAll(kMeasureFieldSep, ' ');

  final payload = lines
      .map((l) => '${clean(l.text)}$kMeasureFieldSep${l.height.round()}')
      .join(kMeasureLineSep);
  final tokenPayload = tokens
      .map(
        (t) =>
            '${clean(t.text)}$kMeasureFieldSep${t.height.round()}'
            '$kMeasureFieldSep${t.top.round()}$kMeasureFieldSep${t.left.round()}',
      )
      .join(kMeasureLineSep);
  return '${clean(imageName)}\t$payload\t${clean(nameSource)}'
      '\t${clean(parsedName)}\t$tokenPayload';
}

/// 측정 파일에 한 줄 덧붙인다. 꺼져 있으면 아무것도 하지 않는다.
///
/// 실패해도 **던지지 않는다** — 측정 때문에 스캔이 죽으면 안 된다.
///
/// ## ⚠️ 어디에 쓰는지가 중요하다 (2026-08-22 실기기에서 데임)
///
/// 처음에는 **앱 내부 문서 폴더**에 썼다. 그런데 **릴리스 빌드는 debuggable이
/// 아니라 `adb run-as`가 거부된다** — 101장을 다 돌리고도 **파일을 꺼낼 수가
/// 없었다.** 같은 함정이 이 저장소 코드에 이미 적혀 있었는데
/// (`ocr_batch_scan_view.dart`의 "앱 내부 문서 폴더는 run-as로 넣는다") 그것을
/// 읽고도 **release에서는 run-as가 막힌다**는 것을 못 이었다.
///
/// 그래서 **앱 전용 외부 저장소**(`/sdcard/Android/data/<pkg>/files`)에 쓴다.
/// `adb shell`이 읽고 쓸 수 있는 것을 실기기에서 확인했다.
///
/// 📌 부르는 쪽이 경로를 정해 넘긴다 — 이 함수는 어디에 쓸지 모른다.
Future<void> appendMeasureRow({
  required Directory directory,
  required String row,
}) async {
  if (!ocrMeasureDumpEnabled) return;
  try {
    final file = File('${directory.path}/$kMeasureFileName');
    await file.writeAsString('$row\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // 조용히 넘어간다. 측정은 부수적인 일이다.
  }
}

/// 측정 파일을 **어디에 쓰는지 한 곳에서 정한다**.
///
/// ## ⚠️ 왜 함수로 묶었나 (추가 409)
///
/// 2026-08-22에 저장 위치를 내부 → 앱 전용 외부로 옮겼는데, **파일만 옮기고
/// 화면 안내는 그대로 뒀다.** 스캔이 끝나면 뜨는 안내가 여전히 내부 폴더를
/// 가리켜, 그 자리를 뒤지면 **파일이 없다.** 위치를 못 찾아 101장을 다시
/// 돌릴 뻔한 그 사고의 재판이다.
///
/// 쓰는 쪽과 알려 주는 쪽이 **서로 다른 값을 고를 수 있으면 언젠가 갈린다.**
/// 그래서 둘 다 이 함수를 부른다.
///
/// 앱 전용 외부 저장소(`/sdcard/Android/data/<pkg>/files`)를 쓴다. 릴리스
/// 빌드는 debuggable이 아니라 `adb run-as`가 막혀 **내부 폴더는 꺼낼 수가
/// 없다.** 외부를 못 얻으면 내부로 되돌아간다 — 안 쓰는 것보다는 낫다.
Future<Directory> measureDumpDirectory() async =>
    await getExternalStorageDirectory() ??
    await getApplicationSupportDirectory();

/// 측정 파일의 전체 경로. 화면에 안내할 때 쓴다.
Future<String> measureDumpPath() async =>
    '${(await measureDumpDirectory()).path}/$kMeasureFileName';
