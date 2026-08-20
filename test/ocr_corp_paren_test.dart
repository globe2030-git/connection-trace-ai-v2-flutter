// OCR이 놓친 **여는 괄호**를 되살리는 것(추가 340).
//
// ## 왜 이 파일이 따로 있나
//
// 2026-08-20 실측에서 **한 장이 두 가지 이유로 틀리고 있었다.**
//
// ```
// 원문     주)드림시큐리티        ← OCR이 '(' 를 놓쳤다
// 결과     회사=보안기술연구소     직함=주)드림시큐리티
// ```
//
// `주)`가 회사 키워드 목록에 없어서 **회사 후보로 인식조차 안 됐고**, 그래서
// 회사 칸은 다음 줄을, 직함 칸은 이 줄을 집었다.
//
// ⚠️ **키워드만 고쳤을 때는 채점이 안 올랐다.** 줄은 제대로 골랐는데 값이
// `주)…`라 정답 `(주)…`와 달랐기 때문이다.
//
// > **고르기와 표기는 따로 손봐야 한다.** 자리를 바로잡는 것만으로는 부족하다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('깨진 법인 표기', () {
    test('여는 괄호를 놓친 회사명을 회사 칸에 넣는다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '주)어디어디',
        '홍길동',
        '보안기술연구소 / 연구개발1부 / 과장',
      ]);
      expect(r.company, '(주)어디어디');
      expect(r.title, isNot(contains('어디어디')), reason: '회사가 직함으로 가면 안 된다');
    });

    test('괄호가 온전하면 예전 그대로', () {
      final r = OcrScannerService.parseLinesForTesting([
        '(주)어디어디',
        '홍길동',
        '과장',
      ]);
      expect(r.company, '(주)어디어디');
    });

    test('㈜도 예전 그대로', () {
      final r = OcrScannerService.parseLinesForTesting([
        '㈜어디어디',
        '홍길동',
      ]);
      expect(r.company, '㈜어디어디');
    });

    test('재단법인 표기도 되살린다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '재)어디어디재단',
        '홍길동',
      ]);
      expect(r.company, '(재)어디어디재단');
    });

    group('⚠️ 함부로 붙이지 않는다', () {
      test('맨 앞이 아니면 건드리지 않는다 — 문장 가운데 `주)`는 다른 뜻일 수 있다', () {
        // 짝 없는 닫는 괄호를 앞에서 떼는 기존 규칙(추가 318)과 부딪히지
        // 않아야 한다.
        final r = OcrScannerService.parseLinesForTesting([
          '어디어디 주식회사',
          '홍길동',
        ]);
        expect(r.company, isNot(startsWith('(')));
      });

      test('법인 표기가 아예 없으면 아무것도 안 붙인다', () {
        final r = OcrScannerService.parseLinesForTesting([
          '어디어디컴퍼니 Inc.',
          '홍길동',
        ]);
        expect(r.company, isNot(startsWith('(')));
      });
    });
  });
}
