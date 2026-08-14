// "예전 기본값 그대로인 태그"를 고르는 규칙 검증.
//
// 이 판정이 틀리면 **사용자가 직접 넣은 맞는 태그를 지운다.** 되돌릴 수 없으므로
// 경계를 촘촘히 박아 둔다(backlog 추가 204).
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/seeded_tag_cleanup.dart';

void main() {
  group('기본값 그대로로 본다', () {
    test('AI, IT 둘뿐', () {
      expect(isSeededDefaultTagSet(['AI', 'IT']), isTrue);
    });

    test('순서가 바뀌어도 같다', () {
      expect(isSeededDefaultTagSet(['IT', 'AI']), isTrue);
    });

    test('대소문자·공백 차이는 무시한다', () {
      expect(isSeededDefaultTagSet([' ai ', 'It']), isTrue);
    });

    test('쉼표가 남아 빈 항목이 생긴 경우도 같다 — "AI, IT,"', () {
      expect(isSeededDefaultTagSet(['AI', 'IT', '']), isTrue);
    });
  });

  group('손대지 않는다 — 잘못 지우는 쪽이 더 나쁘다', () {
    test('다른 태그가 하나라도 함께 있으면', () {
      // 사용자가 이 칸을 의식하고 손댔다는 뜻이다.
      expect(isSeededDefaultTagSet(['AI', 'IT', 'C-Level']), isFalse);
    });

    test('둘 중 하나만 있으면', () {
      expect(isSeededDefaultTagSet(['AI']), isFalse);
      expect(isSeededDefaultTagSet(['IT']), isFalse);
    });

    test('비어 있으면', () {
      expect(isSeededDefaultTagSet([]), isFalse);
      expect(isSeededDefaultTagSet(['', '  ']), isFalse);
    });

    test('비슷하지만 다른 태그', () {
      expect(isSeededDefaultTagSet(['AI', 'IoT']), isFalse);
      expect(isSeededDefaultTagSet(['AIoT', 'IT']), isFalse);
    });
  });
}
