/// **부서·직함 뒤에 자간을 벌려 인쇄한 이름을 이어 붙인다**(2026-08-29, 실측).
///
/// ## 무엇이 문제였나
///
/// ```
/// 개발협력부 김수 진     이름 칸이 비었다
/// 종괄매니저 김지 홍     줄 전체가 직함 칸으로 먹혔다
/// ```
///
/// 명함이 **직함·부서와 이름을 한 줄에** 찍고 **이름의 자간을 벌리면** 인식기가
/// `김수`·`진`으로 쪼갠다. 기존 이어붙이기는 **영문이 섞인 줄만**(슬로건 오탐을
/// 막으려고) 보고, 게다가 **앞에서부터** 붙여서 이 모양을 통째로 놓쳤다.
///
/// 🚨 그리고 **로고 글씨가 먼저 이름 자리를 차지**하고 있었다
/// (`ARENA FITNESS`·`소바젠`). 한국 명함에서 **한글 이름이 영문 후보보다 강한
/// 근거**다.
///
/// ## ✅ 측정
///
/// ```
/// 94장   2장 개선 (이름 82 → 84장)
/// 100장  5장 개선 · 나빠진 것 없음
/// 41장   0장 — 이 모양이 아예 없었다 (드문 결함이라는 뜻)
/// ```
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

({String name, String title, String dept}) parse(List<String> lines) {
  final r = OcrScannerService.parseLinesForTesting(lines);
  return (name: r.name, title: r.title, dept: r.department);
}

void main() {
  group('⭐ 부서 뒤에 벌어진 이름', () {
    test('개발협력부 김수 진 → 김수진', () {
      final r = parse(['개발협력부 김수 진', '010-0000-0000']);
      expect(r.name, '김수진');
    });
  });

  group('⭐ 직함 뒤에 벌어진 이름 — 줄이 통째로 직함이 되던 것', () {
    test('종괄매니저 김지 홍 → 직함 종괄매니저 · 이름 김지홍', () {
      final r = parse(['종괄매니저 김지 홍', '010-0000-0000']);
      expect(r.title, '종괄매니저');
      expect(r.name, '김지홍');
    });

    test('🚨 로고 글씨가 이름 자리를 차지하고 있어도 한글 이름이 이긴다', () {
      final r = parse([
        'ARENA FITNESS',
        '종괄매니저 김지 홍',
        '010-0000-0000',
      ]);
      expect(r.name, '김지홍');
    });
  });

  group('🚨 걸리면 안 되는 것', () {
    test('슬로건은 이름이 되지 않는다 — 앞부분이 부서·직함이 아니다', () {
      final r = parse([
        '국민 맞춤형 복지를 실현하는 디지털 플랫폼 전문기관',
        '010-0000-0000',
      ]);
      expect(r.name, isEmpty);
    });

    test('직함만 있는 줄은 그대로 — 뒤 토막이 이름이 아니다', () {
      final r = parse(['수석 연구원', '010-0000-0000']);
      expect(r.title, contains('연구원'));
      expect(r.name, isEmpty);
    });

    test('이미 찾은 한글 이름은 덮지 않는다', () {
      final r = parse(['홍길동', '개발협력부 김수 진', '010-0000-0000']);
      expect(r.name, '홍길동');
    });
  });
}
