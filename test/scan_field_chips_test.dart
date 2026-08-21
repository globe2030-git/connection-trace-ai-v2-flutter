// 앞면 촬영 직후 시트의 "읽은 필드 칩"(P2-④ 이어찍기) 상태 계산을 검증한다.
import 'package:connection_trace_ai_flutter/core/utils/scan_field_chips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildScanFieldChipStates', () {
    const labels = ['이름', '회사명', '주소', '휴대폰 번호', '이메일'];

    test('빈 칸이 없으면 전부 filled다', () {
      final states = buildScanFieldChipStates(
        allLabels: labels,
        missingLabels: const [],
      );
      expect(states.every((s) => s.filled), isTrue);
      expect(states.map((s) => s.label), labels);
    });

    test('missing에 있는 라벨만 filled: false다', () {
      final states = buildScanFieldChipStates(
        allLabels: labels,
        missingLabels: const ['주소', '이메일'],
      );
      final byLabel = {for (final s in states) s.label: s.filled};
      expect(byLabel['이름'], isTrue);
      expect(byLabel['회사명'], isTrue);
      expect(byLabel['주소'], isFalse);
      expect(byLabel['휴대폰 번호'], isTrue);
      expect(byLabel['이메일'], isFalse);
    });

    test('전부 missing이면 전부 filled: false다', () {
      final states = buildScanFieldChipStates(
        allLabels: labels,
        missingLabels: labels,
      );
      expect(states.every((s) => !s.filled), isTrue);
    });

    test('순서는 allLabels 순서를 그대로 유지한다', () {
      final states = buildScanFieldChipStates(
        allLabels: labels,
        missingLabels: const ['이름'],
      );
      expect(states.map((s) => s.label).toList(), labels);
    });
  });
}
