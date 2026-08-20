/// 촬영 과정에서 생기는 **평문 임시 파일**을 지우는 규칙(2026-08-16).
///
/// ## 왜 필요한가
///
/// 명함 저장본은 AES-256-GCM으로 암호화하는데(`ContactImageService`), 그
/// **원본이 평문으로 앱 캐시에 그대로 남는다.** 실기기에서 확인한 값은
/// **83장 · 198.5MB**였고, 저장된 명함은 16장뿐이었다 — **등록하지 않고 버린
/// 촬영분까지 전부** 쌓여 있었다는 뜻이다.
///
/// - **저장본을 암호화하는 이유 자체를 무력화한다**
/// - 명함을 지워도 남아 **개인정보처리방침의 "명함 삭제 시 즉시 파기"와
///   어긋난다**
/// - CLAUDE.md 개인정보 원칙: *암호화되지 않는 저장소에 개인정보 원문을 넣지
///   않는다*
///
/// ## ⚠️ 언제 지우는가가 전부다 — 너무 일찍 지우면 인식이 깨진다
///
/// ```
/// 촬영(CAP*.jpg) → 크롭(card_scan_*) → 회전(card_rot_*) → OCR → 화면 닫힘
///                                                              → 저장
/// ```
///
/// | 파일 | 언제까지 필요한가 |
/// |---|---|
/// | 카메라 원본 | **크롭이 끝나면 끝** — 가장 먼저 지울 수 있고 **가장 크다** |
/// | 크롭·회전 결과 | **저장까지** — 인식이 끝나도 저장이 이 파일을 읽는다 |
///
/// **저장은 화면이 닫힌 뒤 다른 화면에서 일어난다.** 그래서 스캔 화면을 닫을 때
/// 지우면 안 된다 — 저장이 빈 파일을 읽게 된다.
library;

import 'dart:io';

/// 이 앱이 만드는 임시 파일 이름의 앞부분.
///
/// `card_silent_`는 무음 촬영(추가 — 테스터 B 요청, 프레임 캡처 경로)이 만드는
/// **원본** 파일이다 — 정상 흐름에서는 크롭이 끝나면 바로 지워지지만, 화면을
/// 중간에 닫는 등으로 남을 수 있어 다른 원본·크롭·회전 파일과 같은 규칙으로
/// 쓸어 담는다.
const List<String> kScanTempPrefixes = [
  'card_scan_',
  'card_rot_',
  'card_silent_',
];

/// 쓸어 담을 때의 나이 기준. 이보다 오래된 것만 지운다.
///
/// **지금 쓰고 있는 파일을 지우지 않기 위한 안전선이다.** 촬영 → 저장까지는
/// 길어야 몇 분이므로 1시간이면 넉넉하다.
const Duration kScanTempMaxAge = Duration(hours: 1);

/// 이름이 우리가 만든 임시 파일인가.
///
/// ⚠️ **우리가 만든 것만 지운다.** 다른 앱·플러그인의 파일을 지우면 그쪽이
/// 깨진다.
bool isScanTempName(String fileName) =>
    kScanTempPrefixes.any(fileName.startsWith);

/// [now] 기준으로 지워도 되는가.
///
/// 이름이 맞고 **[maxAge]보다 오래됐을 때만** true. 방금 만든 파일은 지금
/// 쓰이는 중일 수 있어 건드리지 않는다.
///
/// [maxAge]에 `Duration.zero`를 주면 **나이를 따지지 않고 전부** 지운다 —
/// 회원 탈퇴 정리처럼 "지금 쓰는 중인 것도 남기면 안 되는" 자리에서 쓴다.
/// 방침이 "탈퇴 시 전부 파기"라고 적고 있어, 1시간이 안 된 파일이 남는 것
/// 자체가 방침과 실물의 차이가 된다(2026-08-16).
bool shouldSweep(
  String fileName,
  DateTime modified,
  DateTime now, {
  Duration maxAge = kScanTempMaxAge,
}) {
  if (!isScanTempName(fileName)) return false;
  if (maxAge == Duration.zero) return true;
  return now.difference(modified) > maxAge;
}

/// 파일 하나를 조용히 지운다.
///
/// ⚠️ **던지지 않는다.** 정리가 실패해도 촬영·저장은 계속돼야 한다 — 사용자가
/// 잃는 것(명함)이 얻는 것(용량)보다 크다.
Future<void> deleteQuietly(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // 무시한다. 다음 쓸어담기에서 다시 걸린다.
  }
}

/// [dir]에서 오래된 임시 파일을 쓸어 담는다.
///
/// 중간에 버려진 촬영(등록하지 않고 화면을 닫은 경우)이 여기서 걸린다.
/// 실패해도 던지지 않는다.
///
/// [maxAge]는 [shouldSweep]에 그대로 넘어간다 — 탈퇴 정리에서는
/// `Duration.zero`를 줘 나이와 상관없이 전부 지운다.
/// ⚠️ 이 함수가 보는 폴더는 **`Directory.systemTemp`**다. 안드로이드에서 그것은
/// `code_cache`이고, 우리가 `card_scan_*`·`card_rot_*`를 쓰는 곳과 **같은
/// 표현식이라 같은 폴더**다. 카메라 원본과 갤러리 사본이 있는 `cache`는
/// **다른 폴더**이고 [sweepPickerAndCameraLeftovers]가 맡는다.
Future<int> sweepScanTemp(
  Directory dir, {
  DateTime? now,
  Duration maxAge = kScanTempMaxAge,
}) async {
  final at = now ?? DateTime.now();
  var removed = 0;
  try {
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      try {
        final stat = await entity.stat();
        if (shouldSweep(name, stat.modified, at, maxAge: maxAge)) {
          await entity.delete();
          removed++;
        }
      } catch (_) {
        // 파일 하나가 실패해도 나머지는 계속 본다.
      }
    }
  } catch (_) {
    // 디렉터리를 못 열어도 조용히 넘어간다.
  }
  return removed;
}

// ---------------------------------------------------------------------------
// 이미 쌓인 잔재 (2026-08-16, 추가 248)
// ---------------------------------------------------------------------------
//
// 위 정리는 **새로 생기는 것**을 막는다. 그런데 그 정리가 없던 동안 쌓인 것이
// 실기기에 그대로 있었다.
//
// | 무엇 | 실측(SM-F966N) | 누가 만드나 |
// |---|---|---|
// | `cache/CAP*.jpg` | **83장 · 198.5MB** | camera 플러그인이 촬영마다 |
// | `cache/<UUID>/<사진>` | **22장 · 5.6MB** | image_picker가 갤러리 선택마다 |
// | `cache/scaled_*` | 2장 · 0.11MB | image_picker가 재인코딩할 때 |
//
// 셋 다 **평문 명함·프로필 사진**이다. 저장본을 암호화하는 이유가 무력해진다.
//
// ## 지워도 되는 근거 — 짐작이 아니라 플러그인 소스로 확인했다
//
// - **CAP**: `ImageCaptureProxyApi.java:91-102`가 촬영마다 `File.createTempFile`
//   로 만들어 **지역 변수**로 콜백에 넘기고 경로만 Dart로 준다. 플러그인에
//   **지난 파일을 다시 찾는 코드도, 지우는 코드도 없다.** 즉 촬영이 끝난
//   파일은 순수한 쓰레기다.
// - **UUID 폴더**: `FileUtils.java:65`가 `new File(context.getCacheDir(), uuid)`
//   로 **선택마다 새 폴더**를 만들어 사진을 복사한다.
// - image_picker에는 앱이 죽었을 때 결과를 되찾는 장치(`ImagePickerCache`)가
//   있지만, **우리 앱은 `retrieveLostData`를 부르지 않는다**(호출 0건). 그래서
//   지난 사본을 지워도 되찾을 경로가 깨지지 않는다.
//
// ## ⚠️ 어디까지 이름·구조에 기대는가
//
// 오늘 **파일 주인을 이름 모양으로 짐작해 두 번 틀렸다**(추가 248 기록 참고).
// 그래서 여기서는 **기대는 것을 최소로 줄이고 그것을 명시**한다.
//
// - 폴더 이름이 **UUID 모양인 것만** 본다. `WebView`·`Crash Reports`·`fm_cache`
//   같은 다른 구성요소의 캐시는 모양이 달라 걸리지 않는다.
// - 그 안에서 **이미지 확장자만** 지운다. image_picker가 복사하는 것이
//   이미지뿐이므로, 다른 것이 들어 있다면 우리 것이 아니라는 뜻이다.
// - **나이**로 한 번 더 막는다. 시점은 **우리가 아는 값**이다 — 이 파일들은
//   한 번의 스캔 흐름 안에서 쓰이고 끝나므로, 오래된 것은 확실히 버려진 것이다.

/// 카메라 플러그인이 촬영마다 만드는 원본 이름(`CAP…​.jpg`).
bool isCameraCaptureName(String fileName) =>
    fileName.startsWith('CAP') && fileName.toLowerCase().endsWith('.jpg');

/// image_picker가 재인코딩할 때 만드는 사본 이름(`scaled_…`).
bool isScaledCopyName(String fileName) => fileName.startsWith('scaled_');

/// 카메라 플러그인이 **아이폰에서** 촬영 원본을 넣는 폴더 이름.
///
/// ## ⚠️ 왜 따로 있어야 하나 (2026-08-17 실측)
///
/// 위 정리는 **안드로이드의 평평한 캐시 구조**를 전제로 쓰였다 —
/// `cache/CAP*.jpg`처럼 **맨 위 칸에** 있다고 봤다. **아이폰은 두 칸 아래다.**
///
/// ```
/// 안드로이드  cache/CAP*.jpg                ← 맨 위. 걸린다
/// 아이폰      tmp/camera/pictures/CAP_*.jpg ← 두 칸 아래. **안 걸렸다**
/// ```
///
/// 그래서 **아이폰에서만 조용히 안 돌았다.** 실기기에서 **59장·262.7MB**가
/// 남아 있었고, 가장 오래된 것은 **닷새 전** 것이었다. 전부 **평문 명함**이다.
///
/// 📌 `sweepPickerAndCameraLeftovers`는 **죽은 코드가 아니었다.** `main.dart`가
/// 앱을 열 때마다 제대로 부른다 — **훑는 범위가 좁았을 뿐**이다. 처음에는
/// "안 불리는 것"으로 오해했다가 호출부를 찾아보고 정정했다. **부르는 곳이
/// 있는지부터 확인할 것.**
///
/// ## 지워도 되는 근거 — 짐작이 아니라 플러그인 소스로 확인했다
///
/// `camera_avfoundation`의 `DefaultCamera.swift:757-773`이
/// `temporaryDirectory/camera/<subfolder>/CAP_<uuid>.jpg`를 **촬영마다 새로**
/// 만든다. 그리고 플러그인 소스 전체에 **`removeItem`도 `contentsOfDirectory`도
/// 없다** — 지우지도, 지난 파일을 다시 찾지도 않는다. 촬영이 끝난 파일은 순수한
/// 쓰레기다(안드로이드 쪽과 같은 결론, 같은 방식으로 확인).
const String kCameraPluginDirName = 'camera';

bool isCameraPluginDirName(String dirName) => dirName == kCameraPluginDirName;

/// image_picker가 갤러리 선택마다 만드는 폴더 이름인가(UUID 모양).
///
/// `8-4-4-4-12` 16진수만 통과시킨다 — 다른 구성요소의 캐시 폴더
/// (`WebView`·`Crash Reports`·`fm_cache`)는 걸리지 않는다.
final RegExp _uuidDirPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isPickerCacheDirName(String dirName) => _uuidDirPattern.hasMatch(dirName);

/// 이미지 파일인가. UUID 폴더 안에서 **이것만** 지운다.
bool isImageFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic');
}

bool _isOldEnough(DateTime modified, DateTime now, Duration maxAge) {
  if (maxAge == Duration.zero) return true;
  return now.difference(modified) > maxAge;
}

/// 촬영 원본·갤러리 사본이 쌓인 **앱 캐시 폴더**를 쓸어낸다.
///
/// [cacheDir]는 `getTemporaryDirectory()`(안드로이드에서 `cache`)를 넘긴다 —
/// [sweepScanTemp]가 보는 `Directory.systemTemp`(`code_cache`)와 **다른
/// 폴더**다.
///
/// 지운 파일 수를 돌려준다. **어디서도 던지지 않는다** — 정리 실패로 촬영·
/// 저장이 막히면 사용자가 잃는 것이 더 크다.
Future<int> sweepPickerAndCameraLeftovers(
  Directory cacheDir, {
  DateTime? now,
  Duration maxAge = kScanTempMaxAge,
}) async {
  final at = now ?? DateTime.now();
  var removed = 0;
  try {
    if (!await cacheDir.exists()) return 0;
    await for (final entity in cacheDir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      try {
        if (entity is File) {
          if (!isCameraCaptureName(name) && !isScaledCopyName(name)) continue;
          if (!_isOldEnough((await entity.stat()).modified, at, maxAge)) {
            continue;
          }
          await entity.delete();
          removed++;
        } else if (entity is Directory && isPickerCacheDirName(name)) {
          removed += await _sweepPickerDir(entity, at, maxAge);
        } else if (entity is Directory && isCameraPluginDirName(name)) {
          // ⚠️ 아이폰은 촬영 원본이 **두 칸 아래**(`camera/pictures/`)에 있다.
          // 이 갈래가 없어서 아이폰에서만 조용히 안 지워졌다.
          removed += await _sweepCameraPluginDir(entity, at, maxAge);
        }
      } catch (_) {
        // 하나가 실패해도 나머지는 계속 본다.
      }
    }
  } catch (_) {
    // 폴더를 못 열어도 조용히 넘어간다.
  }
  return removed;
}

/// 카메라 플러그인 폴더(`camera/`)를 정리한다 — **아이폰용**.
///
/// 안에 `pictures`·`videos` 같은 칸이 하나 더 있고, 그 안에 `CAP_*` 파일이
/// 있다. **그 이름을 가진 파일만** 지운다.
///
/// ⚠️ **폴더는 남긴다.** 플러그인이 없으면 다시 만들긴 하지만, 지우는 순간
/// 촬영 중인 다른 흐름과 부딪힐 수 있다 — **우리 목적은 사진을 없애는 것**이지
/// 폴더를 없애는 것이 아니다.
///
/// ⚠️ **한 칸만 더 내려간다.** 끝까지 훑지 않는 이유는 이 파일이 처음부터
/// 지켜 온 원칙과 같다 — **기대는 것을 최소로 줄이고 명시한다.** 깊이 들어갈수록
/// 남의 파일을 지울 위험이 커진다.
Future<int> _sweepCameraPluginDir(
  Directory dir,
  DateTime at,
  Duration maxAge,
) async {
  var removed = 0;
  try {
    await for (final entity in dir.list(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      try {
        if (entity is File) {
          // 폴더 바로 아래에 있는 경우도 받는다(구조가 바뀔 수 있다).
          if (!isCameraCaptureName(name)) continue;
          if (!_isOldEnough((await entity.stat()).modified, at, maxAge)) {
            continue;
          }
          await entity.delete();
          removed++;
        } else if (entity is Directory) {
          await for (final inner in entity.list(followLinks: false)) {
            if (inner is! File) continue;
            final innerName = inner.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last;
            if (!isCameraCaptureName(innerName)) continue;
            try {
              if (!_isOldEnough((await inner.stat()).modified, at, maxAge)) {
                continue;
              }
              await inner.delete();
              removed++;
            } catch (_) {
              // 하나가 실패해도 나머지는 계속 본다.
            }
          }
        }
      } catch (_) {
        // 하나가 실패해도 나머지는 계속 본다.
      }
    }
  } catch (_) {
    // 폴더를 못 열어도 조용히 넘어간다.
  }
  return removed;
}

/// UUID 폴더 하나를 정리한다. 안의 **이미지 파일만** 지우고, 그래서 폴더가
/// 비면 폴더까지 지운다(빈 폴더가 무한정 늘지 않게).
///
/// ⚠️ 이미지가 아닌 것이 들어 있으면 **폴더를 남긴다** — 우리 것이 아닐 수
/// 있다는 신호이므로 지우지 않는 쪽으로 기운다.
Future<int> _sweepPickerDir(
  Directory dir,
  DateTime at,
  Duration maxAge,
) async {
  var removed = 0;
  var leftSomething = false;
  await for (final entity in dir.list(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is! File || !isImageFileName(name)) {
      leftSomething = true;
      continue;
    }
    try {
      if (!_isOldEnough((await entity.stat()).modified, at, maxAge)) {
        leftSomething = true;
        continue;
      }
      await entity.delete();
      removed++;
    } catch (_) {
      leftSomething = true;
    }
  }
  if (!leftSomething) {
    try {
      await dir.delete();
    } catch (_) {
      // 폴더가 안 지워져도 안의 사진은 이미 없어졌다 — 그것이 목적이다.
    }
  }
  return removed;
}
