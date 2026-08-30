// `(주)` 가 **앞에 붙는 표기**를 집는다 (추가 617).
//
// 🚨 **왜 있나**: `_trimCompanyAroundKeyword` 가 키워드 **앞 토큰**만 회사명으로
// 봤다. `가나다 (주)` 에는 맞지만 `(주) 가나다` 에서는 엉뚱한 낱말을 집는다.
//
// ```
// The DMP Company (주) TG360°   →  「Company (주)」   실물은 (주) TG360   (card_02)
// ```
//
// ⚠️ 아래 두 묶음이 경계다 — 뒤를 보는 규칙이 앞을 보는 경우를 깨뜨리면 안 된다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String? company(List<String> lines) =>
    OcrScannerService.parseLinesForTesting(lines).company;

void main() {
  test('앞에 붙은 (주) — 뒤의 이름을 집는다 (card_02 실물 줄)', () {
    expect(
      company([
        'Molecule 박병건 | Andy Park',
        '대표이사 | CEO',
        'The DMP Company (주) TG360°',
      ]),
      '(주) TG360',
    );
  });

  test('🚨 뒤에 붙은 (주) 는 그대로 — 여기가 무너지면 옛 동작이 깨진다', () {
    expect(company(['홍길동', '대표', '가나다소프트 (주)']), '가나다소프트 (주)');
  });

  test('🚨 로고 장식은 끝에 홀로 붙은 것만 뗀다 — 이름 속 기호는 안 건드린다', () {
    expect(
      OcrScannerService.joinBrokenCompanySpacesForTesting('M&A 파트너스'),
      'M&A 파트너스',
    );
  });
}
