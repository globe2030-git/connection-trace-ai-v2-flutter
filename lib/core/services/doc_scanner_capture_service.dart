/// 기성 문서 스캐너로 명함을 찍는 **두 번째 촬영 경로**(추가 266, 1단계).
///
/// ## 왜 만드나
///
/// 지금 촬영 경로는 `_cropToGuideFrame`이 **가이드 상자 안을 그대로** 잘라낸다.
/// 가이드는 명함 비율에 맞춰 뒀지만, **사용자가 그 상자에 정확히 맞춰 대지
/// 않으면 남는 부분(책상·벽)이 그대로 사진에 들어온다.**
///
/// ⚠️ **비율 문제가 아니라 "상자를 자르느냐, 명함을 자르느냐"의 차이다.**
///
/// 기성 스캐너(Android는 ML Kit Document Scanner, iOS는 VisionKit)는 **명함의
/// 네 모서리를 찾아 그것만** 오려내고 기울기까지 편다.
///
/// ## ⚠️ 이것은 기존 경로를 대체하지 않는다
///
/// 1단계에서는 **경로를 하나 더 만들 뿐**이고, 기본값은 그대로 기존 화면이다.
/// 2단계에서 실제 명함 20~30장으로 둘을 나란히 재고, **이겼을 때만** 3단계에서
/// 기본값을 바꾼다.
///
/// 📌 *"기성품이니 더 좋을 것"*도 **추정이다.** pub 점수가 만점이라는 것과
/// **우리 기기에서 명함이 잘 잘린다는 것은 다른 얘기다.**
///
/// ## 어디까지만 갈라지나
///
/// ```
/// [기존]  CameraScanModalView            → card_scan_*.jpg ┐
/// [신규]  DocScannerCaptureService       → card_scan_*.jpg ┤
///                                                          ├→ OcrScannerService
///                                                          │  → ContactImageService
///                                                          │    (축소·한도·정리)
/// ```
///
/// **갈라지는 곳은 "사진 파일을 만드는 데까지"뿐이다.** 그 뒤 저장 경로는 손대지
/// 않는다 — `ContactImageService`의 축소(긴 변 1600·품질 80)·한도·재설치 카운터·
/// 임시 파일 정리가 **전부 그대로 지나간다.**
///
/// ## ⚠️ 평문 임시 파일을 새로 새게 두지 않는다
///
/// 이 앱은 저장본을 AES-256-GCM으로 암호화하는데, **그 원본이 평문으로 앱
/// 캐시에 남으면 암호화하는 이유 자체가 무력해진다.** 실기기에서 83장·198.5MB가
/// 쌓여 있던 전례가 있다(2026-08-16, 저장된 명함은 16장뿐이었다).
///
/// 이 경로는 평문 파일을 **두 군데** 만든다. 둘 다 막는다.
///
/// | 어디 | 누가 만드나 | 어떻게 지우나 |
/// |---|---|---|
/// | 플러그인 캐시 | `cunning_document_scanner` | [CunningDocumentScanner.cleanCache] + [deleteQuietly] |
/// | 앱 임시 폴더 | 이 파일 | 접두사를 **`card_scan_`**으로 써서 **기존 쓸어담기가 그대로 잡게** 한다 |
///
/// ⚠️ **접두사를 바꾸면 정리 규칙에 구멍이 생긴다.** `kScanTempPrefixes`에 이미
/// 들어 있는 이름을 쓰는 것이 핵심이고, 그 결합은 테스트가 지킨다
/// (`test/doc_scanner_capture_test.dart`).
library;

import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../utils/scan_temp_cleanup.dart';

/// **기본 촬영 경로가 무엇인가.** `false`면 기존 `CameraScanModalView`다.
///
/// ⚠️ **3단계 전까지 `false`다.** 2단계에서 실제 명함 20~30장으로 재서
/// **기성 스캐너가 이겼을 때만** 이 값을 뒤집는다. 졌으면 그대로 두면 되고,
/// 기존 화면을 지우지 않았으므로 되돌릴 것도 없다.
const bool kUseDocScannerCaptureByDefault = false;

/// 지금 이 순간 어느 경로를 쓰는가.
///
/// ⚠️ **release 빌드에서는 [kUseDocScannerCaptureByDefault]에서 절대 움직이지
/// 않는다.** 값을 바꾸는 스위치가 `kDebugMode` 안에만 있기 때문이다 —
/// 테스터에게 배포되는 빌드에는 그 스위치가 아예 없다("로그인 건너뛰기"와
/// 같은 취급).
///
/// **왜 상수가 아니라 뒤집을 수 있게 두나**: 2단계가 *"같은 명함 20~30장을 두
/// 경로에 나란히 넣어 재는 것"*이라, 상수였다면 **명함 한 장마다 빌드를 다시
/// 깔아야 해서** 사실상 비교가 안 된다.
///
/// 📌 **2단계가 끝나면 이 스위치를 지운다.** 3단계에서 기본값이 정해지면 쓸
/// 데가 없고, 남겨 두면 다음 사람이 *"이건 왜 있나"*를 묻는다.
final ValueNotifier<bool> docScannerCaptureEnabled = ValueNotifier<bool>(
  kUseDocScannerCaptureByDefault,
);

/// 이 경로가 만드는 임시 파일의 접두사.
///
/// ⚠️ **`kScanTempPrefixes`에 들어 있는 값이어야 한다.** 기존 쓸어담기
/// (`sweepScanTemp`)와 탈퇴 정리가 이 이름을 보고 지운다 — 다른 이름을 쓰면
/// 평문 명함 사진이 캐시에 남는다.
const String kDocScannerTempPrefix = 'card_scan_';

/// 굽는 JPEG 품질.
///
/// **기존 경로(`_cropToGuideFrame`)의 `encodeJpg(quality: 100)`과 맞춘다.**
/// 2단계에서 두 경로를 나란히 재는데, 압축률이 다르면 **파일 크기 차이가
/// "자르기가 달라서"인지 "압축이 달라서"인지 구분되지 않는다.**
///
/// ⚠️ 여기서 줄이지 않는다. 저장 직전의 축소(`ContactImageService`)가
/// 품질 80으로 다시 굽는 자리이고, **그 상수는 비용 계산의 전제값이다.**
const int kDocScannerJpegQuality = 100;

/// 촬영 한 번의 결과와 **잰 값**.
///
/// 픽셀 수를 함께 돌려주는 이유가 있다. 저장 직전 축소는 **긴 변이 1,600을
/// 넘을 때만** 도는데, 기성 스캐너가 여백을 걷어내면 **결과 픽셀 수가 줄어
/// 임계 아래로 내려갈 수 있다.** 그러면 축소를 건너뛰어 **더 작게 잘랐는데
/// 저장본은 더 커지는** 일이 생긴다.
///
/// ⚠️ **그 계산은 손익 세션이 냈고 아직 실측이 아니다**(커버 화면 1,805px →
/// 1,504px 추정, 임계 1,600). **2단계에서 이 값을 접은 화면·편 화면 각각
/// 적어 넘겨야 한다.** 폴더블은 화면 크기가 크롭 픽셀 수를 정한다.
@immutable
class DocScannerCapture {
  /// 인식·저장으로 넘길 JPEG 파일 경로. 접두사는 [kDocScannerTempPrefix].
  final String path;

  /// 잘린 결과의 가로 픽셀.
  final int widthPx;

  /// 잘린 결과의 세로 픽셀.
  final int heightPx;

  /// 파일 크기(바이트).
  final int bytes;

  /// 플러그인이 준 것을 **다시 구웠는지**.
  ///
  /// Android는 PNG로 주므로 JPEG으로 굽는다. iOS는 JPEG으로 달라고 했으므로
  /// 그대로 옮긴다 — **다시 구우면 화질만 깎이고 얻는 것이 없다.**
  final bool reencoded;

  const DocScannerCapture({
    required this.path,
    required this.widthPx,
    required this.heightPx,
    required this.bytes,
    required this.reencoded,
  });

  /// 긴 변. 저장 직전 축소가 **이 값**을 1,600과 견준다.
  int get longEdgePx => widthPx > heightPx ? widthPx : heightPx;
}

/// 기성 문서 스캐너를 띄우고, 결과를 우리 임시 파일로 옮긴다.
class DocScannerCaptureService {
  const DocScannerCaptureService._();

  /// 스캐너를 띄워 명함 한 장을 찍는다.
  ///
  /// 사용자가 취소하면 `null`. 실패는 예외로 던진다 — 부르는 쪽이 기존 촬영
  /// 실패와 같은 방식으로 안내한다.
  ///
  /// ⚠️ **`noOfPages: 1`이다.** 명함 한 면이 한 장이고, 앞뒤는 기존 흐름대로
  /// 화면을 두 번 여는 방식이라 여기서 여러 장을 받을 이유가 없다.
  ///
  /// ⚠️ **`ScannerSource.camera`다.** 갤러리는 이미 다른 진입점
  /// (`FilePickerModalView`)이 맡고 있다 — 여기서 같이 열면 같은 일을 하는
  /// 진입점이 늘어난다(제품 원칙 2-3절).
  static Future<DocScannerCapture?> capture() async {
    String? srcPath;
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        scannerSource: ScannerSource.camera,
        // iOS는 기본이 PNG인데, 우리 저장 경로는 JPEG 바이트를 받는다. 여기서
        // 바로 JPEG으로 달라고 하면 **다시 굽는 단계가 통째로 없어진다.**
        // 품질 1.0 = 최저 압축 — 기존 경로의 quality 100과 같은 자리다.
        iosScannerOptions: IosScannerOptions(
          imageFormat: IosImageFormat.jpg,
          jpgCompressionQuality: 1.0,
        ),
      );

      // 취소는 모든 플랫폼에서 null로 정규화돼 온다(플러그인 문서).
      if (paths == null || paths.isEmpty) return null;

      srcPath = paths.first;
      return await _adoptAsScanTemp(srcPath);
    } finally {
      // ⚠️ **평문 명함 사진을 남기지 않는다. 세 갈래를 다 지운다.**
      //
      // | 무엇 | 누가 만드나 |
      // |---|---|
      // | 플러그인 복사본 `DOCUMENT_SCAN_*` | 플러그인이 우리에게 준 그 파일 |
      // | 플러그인 캐시 전체 | 위와 같은 규칙의 잔재 |
      // | **ML Kit 원본** | **GMS가 이름을 정한다 — 위 둘이 못 잡는다** |
      //
      // ⚠️ **취소했을 때도 돌아야 한다.** 사용자가 한 장 찍고 나서 닫으면
      // 결과는 안 오지만 **ML Kit은 이미 파일을 써 뒀을 수 있다.** 그래서
      // `getPictures` 호출 자체를 try 안에 넣었다 — 예전 구조에서는 취소가
      // finally보다 먼저 return해서 이 정리를 건너뛰었다.
      await deleteQuietly(srcPath);
      await _cleanPluginCacheQuietly();
      // ⚠️ **`getTemporaryDirectory()`다. `Directory.systemTemp`가 아니다.**
      // 앞의 것은 `cache`, 뒤의 것은 `code_cache`이고 **ML Kit은 `cache`에
      // 쓴다.** 이걸 틀리면 조용히 아무것도 안 지운다(2026-08-16 실측).
      await _sweepMlKitCacheQuietly();
    }
  }

  /// 플러그인이 준 파일을 **우리 이름·우리 형식**으로 옮긴다.
  ///
  /// 읽지 못하거나 해독되지 않으면 `null`.
  static Future<DocScannerCapture?> _adoptAsScanTemp(String srcPath) async {
    final src = File(srcPath);
    if (!await src.exists()) return null;

    final srcBytes = await src.readAsBytes();
    final decoded = img.decodeImage(srcBytes);
    if (decoded == null) return null;

    // 이미 JPEG이면 **바이트를 그대로 옮긴다.** 다시 구우면 재압축으로 화질만
    // 깎인다 — 회전 버튼이 각도만 들고 있다가 한 번만 굽는 것과 같은 판단이다.
    final alreadyJpeg = looksLikeJpeg(srcBytes);
    final outBytes = alreadyJpeg
        ? srcBytes
        : img.encodeJpg(decoded, quality: kDocScannerJpegQuality);

    final outPath =
        '${Directory.systemTemp.path}/${docScannerTempFileName(DateTime.now())}';
    await File(outPath).writeAsBytes(outBytes);

    final capture = DocScannerCapture(
      path: outPath,
      widthPx: decoded.width,
      heightPx: decoded.height,
      bytes: outBytes.length,
      reencoded: !alreadyJpeg,
    );

    // ⚠️ **개인정보를 찍지 않는다.** 이름·전화번호가 아니라 **픽셀 수와
    // 바이트만** 남긴다(CLAUDE.md 개인정보 원칙). 2단계에서 축소 임계(1,600)를
    // 넘는지 판정할 근거라 실기기에서 읽을 수 있어야 한다.
    if (kDebugMode) {
      debugPrint(
        '[docscan] ${capture.widthPx}x${capture.heightPx} '
        'long=${capture.longEdgePx} bytes=${capture.bytes} '
        'reencoded=${capture.reencoded}',
      );
    }
    return capture;
  }

  /// 플러그인 캐시를 비운다. **실패해도 던지지 않는다.**
  ///
  /// 정리가 실패했다고 촬영을 막으면 사용자가 잃는 것(명함)이 얻는 것(용량)보다
  /// 크다 — [deleteQuietly]와 같은 판단이다.
  /// ML Kit 원본 폴더를 비운다. 경로를 얻는 것부터 실패할 수 있어 감싼다.
  static Future<void> _sweepMlKitCacheQuietly() async {
    try {
      await sweepMlKitScannerCache(await getTemporaryDirectory());
    } catch (_) {
      // 무시한다. 다음 촬영에서 다시 걸린다.
    }
  }

  static Future<void> _cleanPluginCacheQuietly() async {
    try {
      await CunningDocumentScanner.cleanCache();
    } catch (_) {
      // 무시한다. 우리가 만든 파일은 아니지만, 남아도 다음 촬영에서 다시 비운다.
    }
  }
}

/// ⚠️ **ML Kit 스캐너가 자기 원본을 두고 가는 폴더**(2026-08-16 실기기 실측).
///
/// 앱 캐시 안에 있지만 **이름을 GMS가 정한다.** 우리 접두사 규칙(`card_scan_`)에도,
/// 플러그인 규칙(`DOCUMENT_SCAN_`)에도 안 걸린다.
const String kMlKitScannerCacheDir = 'mlkit_docscan_ui_client';

/// ML Kit이 남긴 평문 원본을 지운다.
///
/// ## ⚠️ 이 함수는 실측으로 생겼다 — 코드 리뷰로는 안 나왔다
///
/// 처음에는 [CunningDocumentScanner.cleanCache]가 **플러그인이 남기는 평문을
/// 지울 공식 경로**라고 보고 그것만 불렀다. **틀렸다.** 실기기에서 명함 두 장을
/// 찍은 뒤 캐시를 열어 보니 **평문 JPEG 두 개가 그대로 남아 있었고**, 바이트
/// 수가 우리가 찍은 사진과 정확히 같았다(168,797 · 490,420).
///
/// 원인은 플러그인 소스(`FileUtil.kt`)에 적혀 있었다:
///
/// > *"ML Kit **owns and names the source file itself, outside this plugin's
/// > naming convention**."*
///
/// | 파일 | 지우는 주체 |
/// |---|---|
/// | 플러그인 복사본 `DOCUMENT_SCAN_*.jpg` | `cleanCache()` ✅ |
/// | **ML Kit 원본** `mlkit_docscan_ui_client/*.jpg` | **아무도** ❌ |
///
/// 📌 **추가 248의 `image_picker` UUID 폴더와 같은 모양이다** — **남이 이름을
/// 정하면 우리 규칙이 못 잡는다.** 그래서 폴더를 지목해서 비운다.
///
/// ## 왜 폴더째 비워도 되나
///
/// **우리 앱 캐시 안이고, 그 안에 들어오는 것은 우리 사용자가 찍은 명함뿐이다.**
/// 지워도 스캐너가 다음에 다시 만든다. 추가 248에서 *"이름 모양으로 주인을
/// 짐작해 두 번 틀렸다"*고 했는데, 여기는 **짐작이 아니라 폴더 이름으로 주인이
/// 특정된다.**
///
/// ## ⚠️ 캐시는 폴더가 **둘**이다 — 어느 쪽을 보는지가 이 함수의 전부다
///
/// 처음 구현은 `Directory.systemTemp`를 기본값으로 썼다. **틀렸다.**
///
/// ```
/// Directory.systemTemp  →  code_cache/     ← 우리 card_scan_* 이 사는 곳
/// ML Kit이 쓰는 곳       →  cache/          ← 실제 원본이 사는 곳
/// ```
///
/// `code_cache/mlkit_docscan_ui_client`는 **아예 없어서** 이 함수가 *"폴더가
/// 없네"* 하고 즉시 나갔고, **진짜 폴더는 아무도 안 건드렸다.** 실기기에서
/// 평문 3장·1.6MB가 남아 있는 것으로 확인했다(2026-08-16).
///
/// 📌 `tool/README.md`가 이미 경고한 그 함정이다 — *"캐시는 폴더가 둘이다.
/// 어느 쪽을 보는지부터 정하고 재라."* **경고를 적어 두고도 새 코드가 같은
/// 자리에 빠졌다.**
///
/// 그래서 **부르는 쪽이 폴더를 넘기게** 했다. 기본값을 두면 그 기본값이 또
/// 틀릴 수 있고, **틀려도 조용하다**(없는 폴더는 예외도 안 낸다).
///
/// ⚠️ **던지지 않는다** — 정리 실패로 촬영을 막지 않는다([deleteQuietly]와 같은 판단).
Future<void> sweepMlKitScannerCache(Directory cacheRoot) async {
  final dir = Directory('${cacheRoot.path}/$kMlKitScannerCacheDir');
  try {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        await deleteQuietly(entity.path);
      }
    }
  } catch (_) {
    // 무시한다. 다음 촬영에서 다시 걸린다.
  }
}

/// 임시 파일 이름을 만든다.
///
/// ⚠️ 반드시 [isScanTempName]을 통과해야 한다 — 테스트가 지킨다.
String docScannerTempFileName(DateTime now) =>
    '$kDocScannerTempPrefix${now.millisecondsSinceEpoch}.jpg';

/// 바이트 앞머리가 JPEG인가(`FF D8 FF`).
///
/// **확장자가 아니라 실제 바이트를 본다.** 플랫폼마다 형식이 다르고
/// (Android PNG · iOS 지정 가능), 확장자가 내용과 어긋나면 다시 굽는 판단이
/// 틀린다.
bool looksLikeJpeg(Uint8List bytes) =>
    bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
