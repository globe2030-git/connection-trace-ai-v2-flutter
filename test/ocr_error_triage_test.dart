// 틀린 값을 **"인식 문제"와 "고르기 문제"로 가른다.**
//
// 채점기(`ocr_accuracy_score_test.dart`)는 *"정답과 다르다"*까지만 말한다.
// 누가 틀렸는지 — OCR이 글자를 잘못 읽은 것인지, 글자는 읽었는데 파서가 못
// 고른 것인지 — 는 **원문을 함께 봐야** 나온다. 이 파일이 그것을 센다.
//
// ## ⚠️ 왜 채점기와 같은 파일에서 도는가 (2026-08-19, 추가 322)
//
// 첫 판은 파이썬 스크립트였고 **TSV에 저장된 값**을 썼다. 그런데 그 값은
// **스캔 당시의 파서**가 낸 것이라, 그 뒤 개선된 칸(팩스 등)이 통째로 어긋났다.
// 팩스가 *"미검출 37건"*으로 나왔지만 지금 파서로는 **1건**이다.
//
// 그래서 채점기와 **똑같이 원문을 현재 파서에 다시 먹인다.** 두 파일이 같은
// 자를 쓰지 않으면 숫자를 나란히 놓을 수 없다.
//
// ## 판정
//
// | 이름 | 뜻 | 누구 문제 |
// |---|---|---|
// | 못 고름 | 정답이 원문에 **통째로** 있는데 다른 값이 들어갔다 | 파서 |
// | 조각만 | 정답 조각이 원문에 다 있는데 조합이 다르다 | 파서·표기 |
// | 미검출 | 정답이 원문에 있는데 칸이 비었다 | 파서 |
// | 오검출 | 명함에 없는 값이 들어갔다 | 파서 |
// | **오독** | 정답 조각이 원문에 **하나도 없다** | **OCR** |
//
// ⚠️ "오독"은 **상한이지 확정이 아니다.** 정답지 표기가 원문과 다른 경우도
// 여기 섞인다(추가 320에서 실제로 그랬다).
//
// ## 쓰는 법 — 채점기와 같다
//
// ```bash
// TSV=~/card-ocr-data/scan_result.tsv \
// TRUTH=~/card-ocr-data/ocr_truth.tsv \
// flutter test test/ocr_error_triage_test.dart
// ```
//
// 두 파일이 없으면 조용히 건너뛴다(CI에는 개인정보인 이 파일들이 없다).
// **통과 여부가 아니라 출력을 봐야 한다.**
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scan_row_lines.dart';

const _fields = [
  '이름',
  '회사',
  '직함',
  '부서',
  '휴대폰',
  '사무실',
  '팩스',
  '이메일',
  '홈페이지',
  '우편번호',
  '주소',
  '상세주소',
];

/// 채점기 `_norm`과 **같아야 한다** — 칸막이 기호를 공백으로, 공백은 하나로.
String _norm(String v) => v
    .replaceAll(RegExp(r'[|·｜]'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// 원문에 들어 있는지 볼 때는 **공백까지 지운다** — OCR이 줄을 다르게 끊는다.
String _squash(String v) => _norm(v).replaceAll(RegExp(r'\s+'), '');

Map<String, Map<String, String>> _readTsv(File file, String keyColumn) {
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
  if (lines.isEmpty) return {};
  final header = lines.first.split('\t');
  final out = <String, Map<String, String>>{};
  for (final line in lines.skip(1)) {
    final cells = line.split('\t');
    final row = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      row[header[i]] = i < cells.length ? cells[i] : '';
    }
    final key = row[keyColumn] ?? '';
    if (key.isNotEmpty) out[key] = row;
  }
  return out;
}

void main() {
  test('틀린 값을 인식 문제와 고르기 문제로 가른다', () {
    final scanPath = Platform.environment['TSV'];
    final truthPath = Platform.environment['TRUTH'];
    if (scanPath == null || truthPath == null) return;
    final scanFile = File(scanPath), truthFile = File(truthPath);
    if (!scanFile.existsSync() || !truthFile.existsSync()) return;

    final scans = _readTsv(scanFile, '파일명');
    final truths = _readTsv(truthFile, '파일명');

    // 채점기와 **같은 대상** — 검수를 마쳤고 스캔 결과도 있는 장만.
    final checked = truths.entries
        .where((e) => (e.value['확인함'] ?? '').trim() == 'Y')
        .map((e) => e.key)
        .where(scans.containsKey)
        .toList();
    if (checked.isEmpty) return;

    // ignore: avoid_print
    print('\n채점 대상 ${checked.length}장');
    // ignore: avoid_print
    print('\n칸        오류  못고름  조각만  미검출  오검출   오독');
    // ignore: avoid_print
    print('-' * 46);

    var gN = 0, gMiss = 0, gFrag = 0, gUndet = 0, gOver = 0, gBad = 0;

    for (final field in _fields) {
      var n = 0, miss = 0, frag = 0, undet = 0, over = 0, bad = 0;
      for (final name in checked) {
        final rawLines = scanRowLines(scans[name]!);
        if (rawLines.isEmpty) continue;
        final p = OcrScannerService.parseLinesForTestingWithBoxes(rawLines);
        final got = _norm(switch (field) {
          '이름' => p.name,
          '회사' => p.company,
          '직함' => p.title,
          '부서' => p.department,
          '휴대폰' => p.phone,
          '사무실' => p.officePhone,
          '팩스' => p.fax,
          '이메일' => p.email,
          '홈페이지' => p.website,
          '우편번호' => p.postalCode,
          '주소' => p.address,
          _ => p.addressDetail,
        });
        final want = _norm(truths[name]!['정답_$field'] ?? '');
        if ((got.isEmpty && want.isEmpty) || got == want) continue;

        n++;
        final raw = _squash(rawLines.map((b) => b.text).join(' '));
        if (want.isEmpty) {
          over++;
        } else if (got.isEmpty) {
          raw.contains(_squash(want)) ? undet++ : bad++;
        } else if (raw.contains(_squash(want))) {
          miss++;
        } else {
          final parts = want.split(' ').where((t) => t.isNotEmpty);
          if (parts.isNotEmpty && parts.every((t) => raw.contains(_squash(t)))) {
            frag++;
          } else {
            bad++;
          }
        }
      }
      if (n == 0) continue;
      gN += n;
      gMiss += miss;
      gFrag += frag;
      gUndet += undet;
      gOver += over;
      gBad += bad;
      // ignore: avoid_print
      print('${field.padRight(6)}${'$n'.padLeft(5)}${'$miss'.padLeft(7)}'
          '${'$frag'.padLeft(7)}${'$undet'.padLeft(7)}'
          '${'$over'.padLeft(7)}${'$bad'.padLeft(6)}');
    }

    // ignore: avoid_print
    print('-' * 46);
    // ignore: avoid_print
    print('${'합계'.padRight(6)}${'$gN'.padLeft(5)}${'$gMiss'.padLeft(7)}'
        '${'$gFrag'.padLeft(7)}${'$gUndet'.padLeft(7)}'
        '${'$gOver'.padLeft(7)}${'$gBad'.padLeft(6)}');
    // ignore: avoid_print
    print('\n고르기 문제 ${gMiss + gFrag + gUndet + gOver}건  ·  인식 문제 $gBad건');
  });
}
