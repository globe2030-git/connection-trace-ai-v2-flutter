// **합치기 전의 낱말 상자**를 모으는 것(추가 409).
//
// ## 무엇을 지키나
//
// `_extractOrderedLines`는 좌우로 나란한 줄을 한 행으로 합치면서 **높이를 그중
// 가장 큰 것으로** 잡는다. 그래서 이름과 회사가 나란히 인쇄된 명함에서는
// **회사까지 이름만큼 큰 것으로 기록된다.** 글자 크기로 이름을 고르는 규칙이
// 흔들리는 자리가 여기다.
//
// `measureTokens`는 그 합치기 **전** 값을 그대로 남긴다. 이 테스트는 합친 값과
// 안 합친 값이 실제로 다르게 나오는지를 본다 — 같게 나오면 재는 의미가 없다.
//
// ⚠️ **파싱에는 쓰이지 않는다.** 이 값은 측정 파일로만 나가고, 토큰 높이로
// 이름을 고르는 규칙은 아직 없다(재고 나서 정한다).
import 'dart:ui';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

TextElement _el(String text, Rect box) => TextElement(
  text: text,
  symbols: const [],
  boundingBox: box,
  recognizedLanguages: const [],
  cornerPoints: const [],
  confidence: null,
  angle: null,
);

TextLine _line(List<TextElement> els) => TextLine(
  text: els.map((e) => e.text).join(' '),
  elements: els,
  boundingBox: els.first.boundingBox,
  recognizedLanguages: const [],
  cornerPoints: const [],
  confidence: null,
  angle: null,
);

RecognizedText _text(List<List<TextElement>> lines) => RecognizedText(
  text: '',
  blocks: [
    TextBlock(
      text: '',
      lines: lines.map(_line).toList(),
      boundingBox: Rect.zero,
      recognizedLanguages: const [],
      cornerPoints: const [],
    ),
  ],
);

void main() {
  group('measureTokens', () {
    test('⭐ 나란한 이름·회사의 높이 차이가 살아남는다', () {
      // 이것이 추가 409의 요지다. 두 낱말은 같은 높이(top 100 언저리)에 좌우로
      // 놓여 있어 앱이 **한 행으로 합치고 높이를 88로** 잡는다. 토큰 쪽에는
      // 88과 33이 그대로 남아야 한다.
      final tokens = OcrScannerService.measureTokens(
        _text([
          [
            _el('홍길동', const Rect.fromLTWH(40, 100, 120, 88)),
            _el('㈜회사이름', const Rect.fromLTWH(300, 104, 180, 33)),
          ],
        ]),
      );
      expect(tokens.map((t) => t.text), ['홍길동', '㈜회사이름']);
      expect(tokens.map((t) => t.height), [88, 33]);
    });

    test('위→아래, 같은 높이면 왼→오로 정렬한다', () {
      final tokens = OcrScannerService.measureTokens(
        _text([
          [_el('아래', const Rect.fromLTWH(10, 500, 50, 20))],
          [
            _el('오른쪽', const Rect.fromLTWH(300, 100, 50, 20)),
            _el('왼쪽', const Rect.fromLTWH(10, 100, 50, 20)),
          ],
        ]),
      );
      expect(tokens.map((t) => t.text), ['왼쪽', '오른쪽', '아래']);
    });

    test('빈 낱말은 버리고 앞뒤 공백은 지운다', () {
      final tokens = OcrScannerService.measureTokens(
        _text([
          [
            _el('  ', const Rect.fromLTWH(0, 0, 10, 10)),
            _el(' 김철수 ', const Rect.fromLTWH(20, 0, 50, 40)),
          ],
        ]),
      );
      expect(tokens.length, 1);
      expect(tokens.single.text, '김철수');
    });

    test('글자가 없으면 빈 목록', () {
      expect(
        OcrScannerService.measureTokens(RecognizedText(text: '', blocks: [])),
        isEmpty,
      );
    });
  });
}
