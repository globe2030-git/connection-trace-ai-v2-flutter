// **부서를 얻었을 때도 직함의 나머지 반쪽을 지킨다**(2026-08-30).
//
// ## [추가 600] 이 절반만 고쳤다
//
// 600 은 **부서를 못 얻었을 때** 원래 직함을 지키도록 고쳤다. 그런데 **부서를
// 얻은 줄**에서는 여전히 `head` 만 남기고 나머지를 버리고 있었다.
//
// ```
// 과장 / 정보안전부 / Section Manager
//   →  직함 「과장」 · 부서 「정보안전부」   ← Section Manager 를 버렸다
//   정답: 직함 「과장 / Section Manager」 · 부서 「정보안전부」
// ```
//
// 📌 **버릴 것과 남길 것을 가르는 근거는 「직함 낱말이 있는가」다.**
// `Section Manager` 는 직함 낱말(`Manager`)을 가졌으니 **직함의 다른 표기**이고
// `정보안전부` 는 부서다. 셋을 각자 제자리로 보낸다.
//
// ## 잰 것 — 기기 원문 96장
//
// ```
// 직함 66% → 67%     부서 75% 그대로 · 회사·이름 그대로 · 깨진 장 0
// ```
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  test('직함·부서·직함이 한 줄에 있으면 셋을 제자리로 — card_204', () {
    final r = parse([
      'KYWA 한국청소년활동진흥원',
      '과장/ 정보안전부 / Section Manager',
      '김태우 Kim Tae Woo',
      '02-1234-5678',
    ]);
    expect(r.department, '정보안전부');
    expect(r.title, '과장 / Section Manager');
  });

  test('⚠️ 부서만 있고 다른 직함이 없으면 예전 그대로', () {
    final r = parse(['홍길동', '부사장 / R&D Center', '주식회사 알로이스', '010-1234-5678']);
    expect(r.title, '부사장');
    expect(r.department, 'R&D Center');
  });

  test('🚨 [추가 600] 이 살린 것은 그대로 — 부서를 못 얻으면 안 가른다', () {
    expect(
      parse(['홍길동', '대표이사 | CEO', '(주)한빛정보기술']).title,
      '대표이사 | CEO',
    );
    expect(
      parse(['홍봉표', '대표/공인중개사', '아이클래스 부동산']).title,
      '대표/공인중개사',
    );
  });
}
