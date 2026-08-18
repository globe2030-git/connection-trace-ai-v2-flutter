// ⚠️⚠️ **측정 전용 — backlog 277이 끝나면 이 파일을 통째로 지운다.** ⚠️⚠️
//
// 지울 때 함께 지울 것:
//   - `cardCropKeepForMeasurement`를 쓰는 곳(촬영 화면·설정 화면 스위치)
//   - `test/measure_sample_sink_test.dart`
//
// ## 왜 만들었나
//
// 2단계 대조의 마지막 조각(필드별 인식률)을 재려면 **같은 명함을 경로마다 찍은
// 크롭본**이 필요하다. 그런데 일괄 스캔이 읽는 곳은 `card_samples` 폴더인데,
// **촬영한 크롭본은 임시 파일이라 확인 화면을 지나면 지워진다** — 그 폴더로 갈
// 길이 없었다. 이 파일이 그 한 칸을 잇는다.
//
// ## ⚠️ 이것은 **우리가 닷새에 걸쳐 다섯 군데서 막은 그것**이다
//
// 평문 명함 사진이 기기에 남는 문제로 아이폰 262.7MB·안드로이드 204MB를
// 걷어냈다(추가 248·269·275). 이 파일은 **그 길을 일부러 다시 낸다.**
// 그래서 조건을 걸고 만든다.
//
// | 조건 | 어떻게 |
// |---|---|
// | release에서 **코드가 아예 안 돈다** | `kDebugMode`가 아니면 즉시 반환 |
// | 스위치가 켜져도 release면 안 됨 | 스위치보다 `kDebugMode`를 먼저 본다 |
// | 지울 것임을 코드에 남긴다 | 이 머리말 |
// | 끝나면 실물로 확인 | 기기 파일 목록을 떠서 확인한다(개수가 아니라 이름·시각) |
//
// ⚠️ **"스위치가 꺼져 있다"로는 부족하다** — 스위치는 켜질 수 있다. release
// 빌드에서 **코드 자체가 돌지 않아야** 한다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 촬영한 크롭본을 `card_samples`에 남길지(측정 전용).
///
/// ⚠️ 기본은 꺼짐. 재는 사람이 화면에서 켠다. release에서는 켜도 안 돈다.
final ValueNotifier<bool> cardCropKeepForMeasurement = ValueNotifier<bool>(
  false,
);

/// 파일 이름 앞머리. 정리할 때 이것으로 찾는다.
///
/// ⚠️ 기존 임시파일 접두사(`card_scan_`)와 **일부러 다르게** 둔다 — 쓸어담기가
/// 이 파일들을 촬영 잔재로 오인해 **재는 도중에 지우면** 측정이 통째로 날아간다.
const String kMeasureSamplePrefix = 'measure_';

/// 측정본을 넣는 폴더 이름(일괄 스캔이 읽는 곳과 같다).
const String kMeasureSampleDirName = 'card_samples';

/// 크롭본을 측정용으로 한 장 남긴다.
///
/// [pathLabel]은 어느 경로로 찍었는지다(`on`=검출 켬, `off`=검출 끔).
/// 파일 이름에 들어가 나중에 경로별로 갈라 채점할 수 있게 한다.
///
/// ⚠️ **던지지 않는다.** 측정 장치 때문에 촬영이 막히면 안 된다.
/// 돌려주는 값은 저장한 경로(또는 안 했으면 null) — 부르는 쪽이 화면에
/// 표시해 **정말 저장됐는지 눈으로 확인**할 수 있게 한다.
///
/// ⚠️ `Success`가 아니라 **경로**를 돌려주는 이유: 이 저장소는
/// *"`Success`는 파일이 바뀌었다이지 그 코드가 돈다가 아니다"*를 여러 번 겪었다.
Future<String?> keepCropForMeasurement(
  File croppedFile, {
  required String pathLabel,
}) async {
  // ⚠️ **release에서는 여기서 끝난다.** 스위치보다 먼저 본다.
  if (!kDebugMode) return null;
  if (!cardCropKeepForMeasurement.value) return null;

  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$kMeasureSampleDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = File(
      '${dir.path}/$kMeasureSamplePrefix${pathLabel}_$stamp.jpg',
    );
    await croppedFile.copy(target.path);
    return target.path;
  } catch (_) {
    // 저장 실패로 촬영을 막지 않는다.
    return null;
  }
}

/// 측정본을 전부 지운다 — **측정이 끝나면 반드시 부른다.**
///
/// 지운 파일 수를 돌려준다. ⚠️ **개수만 보고 판정하지 말 것** — 기기에서
/// 파일 목록을 떠서 이름·시각까지 확인한다(추가 250).
Future<int> sweepMeasureSamples() async {
  if (!kDebugMode) return 0;
  var removed = 0;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$kMeasureSampleDirName');
    if (!dir.existsSync()) return 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!isMeasureSampleName(name)) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // 하나가 실패해도 나머지는 계속 본다.
      }
    }
  } catch (_) {
    // 폴더를 못 열어도 조용히 넘어간다.
  }
  return removed;
}

/// 측정본 이름인가.
///
/// ⚠️ **이 이름만** 지운다. `card_samples`에는 예전 검수용 원본 묶음(103장)이
/// 함께 들어 있고, **그것을 지우면 정답지가 가리키는 이미지가 사라진다.**
bool isMeasureSampleName(String fileName) =>
    fileName.startsWith(kMeasureSamplePrefix) &&
    fileName.toLowerCase().endsWith('.jpg');
