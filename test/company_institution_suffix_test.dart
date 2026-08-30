// 공공기관 이름 꼬리가 회사 후보에 들어가는지 본다 (추가 610).
//
// 🚨 **왜 있나**: `서울관광재단` 은 회사 키워드 어디에도 안 걸려 **후보로
// 검토조차 안 됐다.** 그래서 회사 칸이 빈 채로 나왔다 — 190장 자에서 회사를
// 못 찾은 17장 중 **일곱 장이 이 모양**이었고, 원문에는 이름이 그대로
// 찍혀 있었다.
//
// ⚠️ 이 검사는 **낱말 목록이 좁아지는 것**을 막는다. 「원」·「회」 같은 한 글자를
// 넣지 않는 이유는 목록 주석에 적어 뒀다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('공공기관 이름을 회사로 집는다', () {
    for (final c in const [
      ('서울관광재단', ['이현아', '서울컨벤션뷰로 MICE지원팀 | 주임', '서울관광재단']),
      ('한국사회보장정보원', ['안희원', '건강보건사업부 | 주임', '한국사회보장정보원']),
      ('한국통신사업자연합회', ['김미정', '대외협력실 / 과장', '한국통신사업자연합회']),
      ('대한간호협회', ['이상철', 'ICT 팀장', '대한간호협회']),
    ]) {
      test(c.$1, () {
        final r = OcrScannerService.parseLinesForTesting(c.$2);
        expect(r.company, c.$1);
      });
    }

    test('한 글자 꼬리는 안 걸린다 — 부서·직함을 회사로 끌고 오면 안 된다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '기획조정실 / 전문위원',
        '(주)가나다',
      ]);
      expect(r.company, '(주)가나다');
    });
  });
}
