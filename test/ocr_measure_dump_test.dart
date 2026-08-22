import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/ocr_measure_dump.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('⚠️ 릴리스 혼입 방지', () {
    test('기본 빌드에서는 측정이 꺼져 있다', () {
      // `--dart-define=OCR_MEASURE_DUMP=true` 없이 빌드하면 항상 false여야
      // 한다. 이 테스트가 깨지면 측정 코드가 릴리스에 살아 있다는 뜻이다.
      expect(ocrMeasureDumpEnabled, isFalse);
    });

    test('꺼져 있으면 파일을 만들지 않는다', () async {
      final dir = await Directory.systemTemp.createTemp('measure_off');
      await appendMeasureRow(directory: dir, row: 'x\ty\tz\tw');
      expect(File('${dir.path}/ocr_measure.tsv').existsSync(), isFalse);
      await dir.delete(recursive: true);
    });
  });

  group('formatMeasureRow', () {
    test('Vision 도구와 같은 형식으로 만든다', () {
      final row = formatMeasureRow(
        imageName: 'IMG_0001.jpg',
        lines: const [(text: '영업부', height: 30.4), (text: '김철수', height: 90.6)],
        nameSource: 'koreanStripped',
        parsedName: '김철수',
      );
      final cols = row.split('\t');
      expect(cols.length, 4);
      expect(cols[0], 'IMG_0001.jpg');
      expect(cols[2], 'koreanStripped');
      expect(cols[3], '김철수');

      final lines = cols[1].split(kMeasureLineSep);
      expect(lines.length, 2);
      expect(lines[0].split(kMeasureFieldSep), ['영업부', '30']);
      expect(lines[1].split(kMeasureFieldSep), ['김철수', '91']); // 반올림
    });

    test('⚠️ 글자에 구분자가 섞여도 칸이 안 밀린다', () {
      // 깨지면 조용히 어긋나는 종류의 사고라 막아 둔다.
      // 보간 대신 join으로 만든다 — 제어문자를 문자열 안에 박으면 읽기도
      // 어렵고 lint도 걸린다.
      const ls = kMeasureLineSep;
      const fs = kMeasureFieldSep;
      final row = formatMeasureRow(
        imageName: ['a', ls, 'b.jpg'].join(),
        lines: [
          (text: ['가', fs, '나'].join(), height: 10),
        ],
        nameSource: 'none',
        parsedName: ['다', ls, '라'].join(),
      );
      final cols = row.split('\t');
      expect(cols.length, 4);
      expect(cols[0], 'a b.jpg');
      expect(cols[1].split(kMeasureLineSep).length, 1);
      expect(cols[3], '다 라');
    });

    test('줄이 없으면 가운데 칸이 빈다', () {
      final row = formatMeasureRow(
        imageName: 'x.jpg',
        lines: const [],
        nameSource: '없음',
        parsedName: '',
      );
      expect(row.split('\t'), ['x.jpg', '', '없음', '']);
    });
  });
}
