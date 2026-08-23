import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/card_face_label.dart';

/// [cardFaceLabel] 순수 함수 테스트(추가 426).
///
/// 편집 화면 세그먼트·전체화면 뷰어 배지가 이 라벨을 그대로 쓰므로, 몇 번째
/// 면이 어떤 문구가 되는지는 화면 없이도 확정할 수 있다.
void main() {
  group('cardFaceLabel', () {
    test('0번째는 앞면', () {
      expect(cardFaceLabel(0), '앞면');
    });

    test('1번째는 뒷면', () {
      expect(cardFaceLabel(1), '뒷면');
    });

    test('2번째부터는 순번 — 접이식·부록면처럼 3장 이상도 막지 않는다', () {
      expect(cardFaceLabel(2), '3번째 면');
      expect(cardFaceLabel(5), '6번째 면');
    });
  });
}
