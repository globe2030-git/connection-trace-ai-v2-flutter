/// **전화 구분자를 한 글자만 보던 것을 넓힌다**(2026-08-29, 94장 실측).
///
/// ## 무엇이 문제였나
///
/// ```
/// 0(2|[3-6][0-9]|70) [-.\s,)]? \d{3,4} …
///                     └ 구분자를 한 글자만 봤다
/// ```
///
/// `Fax 02) 21888508`처럼 **`)` 다음에 공백**이 오면 **두 글자**라 안 걸렸다.
/// `FAX : (02) 3706-6101`도 같다. 🚨 그래서 **팩스가 빈 채로 저장**됐다.
///
/// 🚨 **`050x`(안심번호·팩스 서비스)도 지역번호 목록에 없었다.**
///
/// ✅ **실측**: 명함에 `fax` 라벨이 있는 **32장 중 6장**을 못 채웠는데
/// **그중 4장이 이 둘**이었다(나머지 2장은 번호가 아예 안 읽힘).
///
/// ```
/// 94장   팩스 채움 26 → 30장 · 사무실 78 → 80장
/// 100장  10장이 바뀌었고 **전부 빈 칸이 채워지는 방향** — 값을 잃은 것 없음
/// ```
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

({String office, String fax}) parse(List<String> extra) {
  final r = OcrScannerService.parseLinesForTesting([
    '(주)가상상사',
    '홍길동',
    '대리',
    ...extra,
    'M 010-0000-0000',
  ]);
  return (office: r.officePhone, fax: r.fax);
}

void main() {
  group('⭐ 괄호 지역번호 뒤에 공백이 와도 잡는다', () {
    test('전화 : (02) 3706-5775 · FAX : (02) 3706-6101', () {
      final r = parse(['전화 : (02) 3706-5775', 'FAX : (02) 3706-6101']);
      expect(r.office, contains('3706-5775'));
      expect(r.fax, contains('3706-6101'));
    });

    test('T (02) 3459-2900 · F (02) 3459-2899', () {
      final r = parse(['T (02) 3459-2900', 'F (02) 3459-2899']);
      expect(r.office, contains('3459-2900'));
      expect(r.fax, contains('3459-2899'));
    });

    test('하이픈 없이 붙여 쓴 것 — 02) 21888508', () {
      final r = parse(['Tel 02) 2188 8500 Fax 02) 21888508']);
      expect(r.fax, contains('2188'));
    });
  });

  group('⭐ 050x 안심번호도 잡는다', () {
    test('Fax 0504-984-9907', () {
      final r = parse(['Tel 070-7595-1062', 'Fax 0504-984-9907']);
      expect(r.fax.replaceAll('-', ''), '05049849907');
    });
  });

  group('멀쩡하던 것은 그대로 — 회귀 확인', () {
    test('보통 표기', () {
      final r = parse(['Tel 02-1234-5678', 'Fax 02-1234-5679']);
      expect(r.office, '02-1234-5678');
      expect(r.fax, '02-1234-5679');
    });

    test('지역번호 세 자리', () {
      final r = parse(['Tel 031-123-4567']);
      expect(r.office, contains('031'));
    });
  });
}
