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
      expect(File('${dir.path}/$kMeasureFileName').existsSync(), isFalse);
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
      expect(cols.length, 5);
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
      expect(cols.length, 5);
      expect(cols[0], 'a b.jpg');
      expect(cols[1].split(kMeasureLineSep).length, 1);
      expect(cols[3], '다 라');
    });

    group('토큰 칸 (추가 409)', () {
      test('낱말마다 높이·위·왼을 남긴다', () {
        final row = formatMeasureRow(
          imageName: 'IMG_0002.jpg',
          lines: const [(text: '홍길동 ㈜회사', height: 88)],
          nameSource: 'fontSizePreferred',
          parsedName: '홍길동',
          tokens: const [
            (text: '홍길동', height: 88.4, top: 100.2, left: 40.7),
            (text: '㈜회사', height: 32.6, top: 104.1, left: 300.9),
          ],
        );
        final cols = row.split('\t');
        final tokens = cols[4].split(kMeasureLineSep);
        expect(tokens.length, 2);
        expect(tokens[0].split(kMeasureFieldSep), ['홍길동', '88', '100', '41']);
        expect(tokens[1].split(kMeasureFieldSep), ['㈜회사', '33', '104', '301']);
      });

      test('⭐ 합친 줄 높이가 감추는 것을 토큰 칸이 드러낸다', () {
        // 이것이 추가 409의 요지다. 이름과 회사가 좌우로 나란하면 행 높이는
        // **둘 중 큰 쪽**(88)이 되어 회사도 이름만큼 커 보인다. 토큰 칸에는
        // 회사가 33으로 남아 **두 배 넘는 차이**가 그대로 보인다.
        final row = formatMeasureRow(
          imageName: 'IMG_0002.jpg',
          lines: const [(text: '홍길동 ㈜회사', height: 88)],
          nameSource: 'fontSizePreferred',
          parsedName: '홍길동',
          tokens: const [
            (text: '홍길동', height: 88, top: 100, left: 40),
            (text: '㈜회사', height: 33, top: 104, left: 300),
          ],
        );
        final cols = row.split('\t');
        final lineHeights = cols[1]
            .split(kMeasureLineSep)
            .map((l) => l.split(kMeasureFieldSep)[1])
            .toList();
        final tokenHeights = cols[4]
            .split(kMeasureLineSep)
            .map((t) => t.split(kMeasureFieldSep)[1])
            .toList();
        expect(lineHeights, ['88'], reason: '행은 하나로 합쳐져 높이가 하나뿐이다');
        expect(tokenHeights, ['88', '33'], reason: '토큰은 갈려 있어야 한다');
      });

      test('토큰을 안 주면 마지막 칸이 빈다 — 앞 네 칸은 v1과 같다', () {
        final row = formatMeasureRow(
          imageName: 'x.jpg',
          lines: const [(text: '가', height: 10)],
          nameSource: 'none',
          parsedName: '',
        );
        final cols = row.split('\t');
        expect(cols.length, 5);
        expect(cols[4], '');
      });

      test('⚠️ 토큰 글자에 섞인 구분자도 지운다', () {
        final row = formatMeasureRow(
          imageName: 'x.jpg',
          lines: const [],
          nameSource: 'none',
          parsedName: '',
          tokens: [
            (
              text: ['가', kMeasureFieldSep, '나', kMeasureLineSep, '다'].join(),
              height: 10,
              top: 1,
              left: 2,
            ),
          ],
        );
        final cols = row.split('\t');
        expect(cols[4].split(kMeasureLineSep).length, 1);
        expect(cols[4].split(kMeasureFieldSep).first, '가 나 다');
      });
    });

    group('⚠️ 판 구분', () {
      test('파일 이름에 판이 박혀 있다 — 지난 판과 한 파일에 섞이지 않는다', () {
        // 기기에는 지난 측정으로 만든 v1 파일이 남아 있다. 같은 이름에 이어
        // 쓰면 형식이 다른 줄이 한 파일에 섞이는데, **앞 네 칸이 같아서 그냥
        // 읽힌다** — 조용히 틀린 대조가 된다. 이름을 갈라 구조적으로 막는다.
        expect(kMeasureFormatVersion, greaterThanOrEqualTo(2));
        expect(kMeasureFileName, contains('v$kMeasureFormatVersion'));
        expect(kMeasureFileName, isNot('ocr_measure.tsv'));
      });
    });

    test('줄이 없으면 가운데 칸이 빈다', () {
      final row = formatMeasureRow(
        imageName: 'x.jpg',
        lines: const [],
        nameSource: '없음',
        parsedName: '',
      );
      expect(row.split('\t'), ['x.jpg', '', '없음', '', '']);
    });
  });
}
