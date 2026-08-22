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

  group('backSideHintFor (추가 397 동승 결함)', () {
    test('주소·이메일을 둘 다 찾았으면(=missing 아님) null이다', () {
      // ⚠️ 이 결함의 핵심 — 예전에는 여기서도 "뒷면에 있는 경우가 많아요"가
      // 고정으로 떴다. 다 찾았으면 아무 말도 안 하는 게 맞다.
      expect(backSideHintFor(const []), isNull);
      expect(backSideHintFor(const ['이름', '휴대폰 번호']), isNull);
    });

    test('주소만 못 찾았으면 주소만 말한다', () {
      expect(backSideHintFor(const ['주소']), '주소가 뒷면에 있는 경우가 많아요');
    });

    test('이메일만 못 찾았으면 이메일만 말한다', () {
      expect(backSideHintFor(const ['이메일']), '이메일이 뒷면에 있는 경우가 많아요');
    });

    test('둘 다 못 찾았으면 예전과 같은 문구다', () {
      expect(
        backSideHintFor(const ['주소', '이메일']),
        '주소·이메일이 뒷면에 있는 경우가 많아요',
      );
    });

    test('이름·회사명·휴대폰만 못 찾은 것은 뒷면 안내 대상이 아니다', () {
      expect(backSideHintFor(const ['이름', '회사명', '휴대폰 번호']), isNull);
    });
  });
}
