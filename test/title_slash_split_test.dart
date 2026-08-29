/// **`/`·`|` 로 묶여 들어온 직함을 가른다**(2026-08-29, 52장 실측).
///
/// ## 무엇이 문제였나
///
/// 명함은 `직함 / 부서`나 `직함 / 영문직함`으로 인쇄되는 일이 흔한데, **그 줄을
/// 통째로 직함 칸에 넣고 있었다.**
///
/// ✅ **실측(globe2030님 명함 52장)**: 직함 칸은 **100% 채워졌는데 19장이
/// 이상**했고 **그중 10장이 이 모양**이었다. 🚨 **채움률로는 안 보이는 결함**이다
/// (추가 198에서 이미 데인 자리 — 빈 값을 정상으로 세면 «오분류 0장»이 나온다).
///
/// 📌 **부서 칸은 21%만 차 있었다** — 잘려 나간 조각 상당수가 부서였다.
///
/// ## 결과
///
/// ```
/// 52장   직함이 이상한 장수  19 → 11      부서 채워진 장수  11 → 16
/// 100장  19장이 바뀌었고 나빠진 것은 없었다(회귀 표본)
/// ```
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

({String title, String dept}) parse(String titleLine) {
  final r = OcrScannerService.parseLinesForTesting([
    '(주)가상상사',
    '홍길동',
    titleLine,
    '010-0000-0000',
  ]);
  return (title: r.title, dept: r.department);
}

void main() {
  group('⭐ 직함 / 부서 로 묶인 줄', () {
    test('부서를 부서 칸으로 옮긴다', () {
      final r = parse('부장 / 정보안전부');
      expect(r.title, '부장');
      expect(r.dept, '정보안전부');
    });

    test('순서가 반대여도(부서 / 직함)', () {
      final r = parse('영업부 / 차장');
      expect(r.title, '차장');
      expect(r.dept, '영업부');
    });

    test('셋으로 묶여도 — 실측에 있던 모양', () {
      final r = parse('전략사업부/기술지원팀/대리');
      expect(r.title, '대리');
      expect(r.dept, isNotEmpty);
    });

    test('「파트」로 끝나는 부서도 — 실측(card_08)', () {
      final r = parse('디지털 커뮤니케이션 파트 / 책임');
      expect(r.title, '책임');
      expect(r.dept, contains('디지털'));
    });
  });

  group('영문 표기는 버린다 — 같은 직함의 다른 표기다', () {
    test('대표이사 / CEO', () => expect(parse('대표이사 / CEO').title, '대표이사'));
    test('부사장 / R&D Center', () => expect(parse('부사장 / R&D Center').title, '부사장'));
  });

  group('🚨 가르면 안 되는 것', () {
    test('한글 직함이 둘이면 그대로 둔다 — 직급과 직책을 나란히 찍은 명함', () {
      final r = parse('이사|본부장');
      expect(r.title, contains('이사'));
      expect(r.title, contains('본부장'));
    });

    test('직함 키워드가 없으면 손대지 않는다', () {
      final r = parse('디자인 / 기획');
      expect(r.title, contains('/'));
    });

    test('구분자가 없으면 그대로', () {
      expect(parse('선임 Architect').title, '선임 Architect');
    });
  });

  group('부서가 이미 있으면 덮지 않는다', () {
    test('먼저 찾은 부서를 지킨다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '(주)가상상사',
        '홍길동',
        '마케팅팀 | 대리',
        '010-0000-0000',
      ]);
      expect(r.department, '마케팅팀');
      expect(r.title, '대리');
    });
  });
}
