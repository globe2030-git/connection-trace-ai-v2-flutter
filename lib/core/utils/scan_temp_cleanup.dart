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
const List<String> kScanTempPrefixes = ['card_scan_', 'card_rot_'];

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
