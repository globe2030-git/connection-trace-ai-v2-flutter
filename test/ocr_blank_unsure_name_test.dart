import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 확신 못 하면 이름을 비운다 — 사용자 결정 2026-08-22.
void main() {
  group('약한 폴백에서 한글은 비운다', () {
    test('한글 쓰레기가 이름 자리에 들어가지 않는다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '테스트(주)',
        '성공과만족을제공',
        '대리',
        'M 010-9999-0001',
      ]);
      expect(r.name, '');
    });

    test('⚠️ 영문은 그대로 둔다 — 영문 이름이 이 경로로 정상 유입된다', () {
      final r = OcrScannerService.parseLinesForTesting([
        'Acme Corp.',
        'John Smith',
        'Manager',
        'M 010-9999-0002',
      ]);
      expect(r.name, isNotEmpty);
    });

    test('확신 경로는 안 건드린다 — 한글 2~4자 이름은 그대로', () {
      final r = OcrScannerService.parseLinesForTesting([
        '테스트(주)',
        '김철수',
        '대리',
        'M 010-9999-0003',
      ]);
      expect(r.name.replaceAll(' ', ''), '김철수');
    });
  });
}
