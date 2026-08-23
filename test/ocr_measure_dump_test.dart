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
            (
              text: '홍길동',
              height: 88.4,
              top: 100.2,
              left: 40.7,
              width: 264.3,
            ),
            (
              text: '㈜회사',
              height: 32.6,
              top: 104.1,
              left: 300.9,
              width: 97.4,
            ),
          ],
        );
        final cols = row.split('\t');
        final tokens = cols[4].split(kMeasureLineSep);
        expect(tokens.length, 2);
        expect(tokens[0].split(kMeasureFieldSep), [
          '홍길동',
          '88',
          '100',
          '41',
          '264',
        ]);
        expect(tokens[1].split(kMeasureFieldSep), [
          '㈜회사',
          '33',
          '104',
          '301',
          '97',
        ]);
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
            (text: '홍길동', height: 88, top: 100, left: 40, width: 264),
            (text: '㈜회사', height: 33, top: 104, left: 300, width: 97),
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
              width: 30,
            ),
          ],
        );
        final cols = row.split('\t');
        expect(cols[4].split(kMeasureLineSep).length, 1);
        expect(cols[4].split(kMeasureFieldSep).first, '가 나 다');
      });
    });

    group('⭐ 너비 칸 — 낱말 사이 틈을 잴 수 있다 (추가 412)', () {
      // 이것이 v3의 존재 이유다. 추가 411에서 "자간을 넓게 인쇄한 이름"과
      // "그냥 붙어 있는 두 낱말"을 가르려다 멈췄다 — 틈을 구하려면
      //   틈 = 다음 낱말의 왼쪽 − (이 낱말의 왼쪽 + 너비)
      // 인데 v2에는 너비가 없었다. 너비를 글자수×높이로 어림잡았더니 틈이
      // 음수로 나왔다(어림이 안 맞는다는 뜻).
      //
      // ⚠️ 아래는 **틈을 구할 수 있는지**만 본다. 얼마면 자간이고 얼마면
      // 다른 낱말인지는 **아직 안 정했다** — 기기로 재고 나서 정한다.
      double gapBetween(String tokenPayload, int i) {
        final t = tokenPayload
            .split(kMeasureLineSep)
            .map((x) => x.split(kMeasureFieldSep))
            .toList();
        final leftOfNext = double.parse(t[i + 1][3]);
        final rightOfThis = double.parse(t[i][3]) + double.parse(t[i][4]);
        return leftOfNext - rightOfThis;
      }

      test('자간을 넓힌 이름 — 낱말마다 좁은 틈이 고르게 난다', () {
        // "홍 길 동"을 한 글자씩 벌려 인쇄한 모양. 글자폭 40, 틈 12.
        final row = formatMeasureRow(
          imageName: 'x.jpg',
          lines: const [(text: '홍 길 동', height: 40)],
          nameSource: 'none',
          parsedName: '',
          tokens: const [
            (text: '홍', height: 40, top: 100, left: 0, width: 40),
            (text: '길', height: 40, top: 100, left: 52, width: 40),
            (text: '동', height: 40, top: 100, left: 104, width: 40),
          ],
        );
        final payload = row.split('\t')[4];
        expect(gapBetween(payload, 0), 12);
        expect(gapBetween(payload, 1), 12);
      });

      test('별개 낱말 — 틈이 눈에 띄게 넓다', () {
        final row = formatMeasureRow(
          imageName: 'x.jpg',
          lines: const [(text: '홍길동 대표이사', height: 40)],
          nameSource: 'none',
          parsedName: '',
          tokens: const [
            (text: '홍길동', height: 40, top: 100, left: 0, width: 120),
            (text: '대표이사', height: 40, top: 100, left: 300, width: 160),
          ],
        );
        expect(gapBetween(row.split('\t')[4], 0), 180);
      });

      test('⚠️ 틈이 음수로 나오지 않는다 — v2의 어림이 실패한 자리', () {
        // v2에서는 너비가 없어 글자수×높이로 어림잡았고, 그 어림이 실제와
        // 어긋나 틈이 −11 같은 값으로 나왔다. 실제 너비를 쓰면 겹치지 않는
        // 낱말끼리는 틈이 음수가 될 수 없다.
        final row = formatMeasureRow(
          imageName: 'x.jpg',
          lines: const [(text: '가나다라마 바', height: 30)],
          nameSource: 'none',
          parsedName: '',
          tokens: const [
            // 글자수×높이로 어림하면 150이지만 실제 너비는 96이다.
            (text: '가나다라마', height: 30, top: 10, left: 0, width: 96),
            (text: '바', height: 30, top: 10, left: 120, width: 20),
          ],
        );
        expect(gapBetween(row.split('\t')[4], 0), 24);
        expect(gapBetween(row.split('\t')[4], 0), greaterThan(0));
      });
    });

    group('⚠️ 판 구분', () {
      test('파일 이름에 판이 박혀 있다 — 지난 판과 한 파일에 섞이지 않는다', () {
        // 기기에는 지난 측정으로 만든 v1 파일이 남아 있다. 같은 이름에 이어
        // 쓰면 형식이 다른 줄이 한 파일에 섞이는데, **앞 네 칸이 같아서 그냥
        // 읽힌다** — 조용히 틀린 대조가 된다. 이름을 갈라 구조적으로 막는다.
        expect(kMeasureFormatVersion, greaterThanOrEqualTo(3));
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
