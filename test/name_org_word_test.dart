/// **조직 낱말은 사람 이름이 아니다**(2026-08-29, 52장 실측).
///
/// ## 무엇이 문제였나
///
/// 이름 규칙이 *"영문 낱말 2~4개"*만 보고 있어서 **부서명이 이름 칸에
/// 들어갔다.**
///
/// ```
/// Innovation Team      → 이름 칸
/// Marketing Division   → 이름 칸
/// more than the most   → 이름 칸 (슬로건)
/// ```
///
/// 🚨 **빈 칸이 낫다.** 이름 칸이 채워져 있으면 이용자는 **맞게 읽혔다고
/// 생각하고 넘어간다.** 비어 있으면 직접 채운다 — 이 저장소의 *"가짜 데이터를
/// 만들지 않는다"*와 같은 자리다.
///
/// ✅ **실측(52장)**: 이름에 **잘못된 값이 든 장수 4 → 1장**(빈 칸 3 → 6장).
/// 100장 회귀 표본에서는 `more than the most` 자리에서 **진짜 이름 「김국진」이
/// 되살아났다.**
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String nameOf(List<String> lines) =>
    OcrScannerService.parseLinesForTesting(lines).name;

void main() {
  group('🚨 조직 낱말이 들어 있으면 이름이 아니다', () {
    test('Innovation Team', () {
      expect(nameOf(['Innovation Team', '010-0000-0000']), isEmpty);
    });

    test('Marketing Division', () {
      expect(nameOf(['Marketing Division', '010-0000-0000']), isEmpty);
    });

    test('Research Center', () {
      expect(nameOf(['Research Center', '010-0000-0000']), isEmpty);
    });
  });

  group('🚨 소문자로 시작하는 영문 구절은 슬로건이다', () {
    test('more than the most', () {
      expect(nameOf(['more than the most', '010-0000-0000']), isEmpty);
    });
  });

  group('⭐ 사람 이름은 그대로 잡는다 — 회귀 확인', () {
    test('John Smith', () {
      expect(nameOf(['John Smith', '010-0000-0000']), 'John Smith');
    });

    test('Anna Marie Lee', () {
      expect(nameOf(['Anna Marie Lee', '010-0000-0000']), 'Anna Marie Lee');
    });

    test('한글 이름', () {
      expect(nameOf(['홍길동', '010-0000-0000']), '홍길동');
    });
  });

  group('회사명 자리도 지킨다', () {
    test('🚨 영문 조직 단위 줄은 회사명이 아니다', () {
      final r = OcrScannerService.parseLinesForTesting([
        'Global Sales Division',
        'John Smith',
      ]);
      expect(r.company, isNot('Global Sales Division'));
    });

    test('⚠️ 그런데 Solutions·Systems 는 회사명에 흔하다 — 막지 않는다', () {
      final r = OcrScannerService.parseLinesForTesting([
        'ABC Solutions Inc',
        '홍길동',
        '010-0000-0000',
      ]);
      expect(r.company, contains('Solutions'));
    });
  });
}
