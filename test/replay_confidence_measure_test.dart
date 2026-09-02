// 파서를 **다시 돌려** 각 칸을 「어느 경로로 골랐는지」를 뽑는다.
//
// ## 왜 필요한가 (2026-09-02)
//
// `OcrNameSource`·`OcrCompanySource` 는 처음부터 이렇게 적혀 있었다:
//
//   "약한 폴백(leftoverFallback)의 비율이 높으면 그만큼 파서가 **확신 없이
//    찍고 있다**는 뜻이라, 인식 품질 측정의 핵심 신호다."
//
// 그런데 **어느 경로가 얼마나 맞는지는 잰 적이 없다.** 그것을 모르면
// 「이 칸은 확인이 필요합니다」의 경계를 감으로 긋게 된다.
//
// ⚠️ 이것은 검사가 아니라 **측정 통로**다. 통과/실패를 보지 않는다.
// ⚠️ 개인정보: 값은 화면에 찍지 않고 파일로만 내보낸다. 파일은 저장소 밖
//    (`connection-sense-assets/명함데이터/`, 권한 700)에 쓴다.
//
// 돌리는 법:
//   flutter test test/replay_confidence_measure_test.dart
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _assets = '/Volumes/X31/Claude/connection-sense-assets/명함데이터/';
const _scan = '${_assets}scan_result_기기_190장_2026-08-30.tsv';
const _out = '${_assets}재생_경로_2026-09-02.tsv';
const _sep = ' ⏐ ';

void main() {
  test('190장을 재생해 경로를 뽑는다', () {
    final lines = File(_scan).readAsLinesSync();
    final head = lines.first.split('\t');
    final iName = head.indexOf('파일명');
    final iRaw = head.indexOf('원문');
    final iBox = head.indexOf('좌표');
    expect(iRaw >= 0 && iBox >= 0, isTrue, reason: '원문·좌표 칸이 있어야 한다');

    final out = StringBuffer()
      ..writeln([
        '파일명', '이름', '회사', '직함', '부서',
        '이름경로', '회사경로', '줄수',
      ].join('\t'));

    var replayed = 0;
    var boxMismatch = 0;
    for (final l in lines.skip(1)) {
      final c = l.split('\t');
      if (c.length <= iBox) continue;
      final raw = c[iRaw].split(_sep).where((s) => s.isNotEmpty).toList();
      final box = c[iBox].split(_sep).where((s) => s.isNotEmpty).toList();
      if (raw.isEmpty) continue;

      // ⚠️ 좌표가 줄 수와 안 맞으면 **좌표 없이** 돌린다. 억지로 맞추면
      //    크기 폴백 경로가 실제와 달라져 측정이 거짓말이 된다.
      final useBox = raw.length == box.length;
      if (!useBox) boxMismatch++;

      final data = <OcrLineBox>[
        for (var i = 0; i < raw.length; i++)
          if (useBox)
            _boxOf(raw[i], box[i])
          else
            lineBoxOf(raw[i]),
      ];

      final r = OcrScannerService.parseLinesForTestingWithBoxes(data);
      replayed++;
      out.writeln([
        c[iName],
        r.name, r.company, r.title, r.department,
        r.parseShape?.nameSource.name ?? '(없음)',
        r.parseShape?.companySource.name ?? '(없음)',
        raw.length,
      ].map((s) => '$s'.replaceAll('\t', ' ')).join('\t'));
    }

    File(_out).writeAsStringSync(out.toString());
    // 값이 아니라 개수만 찍는다.
    // ignore: avoid_print
    print('재생 $replayed장 · 좌표 불일치로 좌표 없이 돌린 것 $boxMismatch장 → $_out');
    expect(replayed, greaterThan(150));
  });
}

OcrLineBox _boxOf(String text, String box) {
  final n = box.split(',').map((s) => double.tryParse(s.trim()) ?? 0).toList();
  if (n.length < 4) return lineBoxOf(text);
  // 기록 순서는 left,top,width,height (ocr_batch_scan_view.dart:293)
  return (
    text: text,
    height: n[3],
    top: n[1],
    left: n[0],
    width: n[2],
  );
}
