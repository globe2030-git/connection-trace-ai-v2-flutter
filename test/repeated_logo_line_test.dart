// **잇달아 두 번 인쇄된 줄은 로고다** — 사람 이름이 아니다(2026-08-30).
//
// ## 무엇을 고쳤나
//
// `card_01` 의 회사가 `LEWIS EXPERT` 인데 `E.PD Kwak Yonghwan`(영문 이름)이
// 들어갔다. **#691 이 낸 회귀다.**
//
// 그 PR 은 `전영환 YOUNGWHAN CHUN` 의 영문 이름을 회사 후보에서 미루려고
// *「모든 낱말 3자 이상 + 하나가 5자 이상」* 으로 선을 그었는데,
// `LEWIS`(5)·`EXPERT`(6) 가 그대로 걸렸다. **선이 굵었다.**
//
// ## 🚨 선을 다시 긋지 않았다 — 근거를 하나 더 봤다
//
// 선을 풀면 `card_109`(전영환)가 다시 깨진다. **좁힐 것은 그물이지 목적이
// 아니다**(#706 에서 배운 것과 같은 모양).
//
// 길이로는 회사 약자와 사람 이름을 못 가르지만, **되풀이**는 가른다.
//
// ```
// 0: LEWIS EXPERT        ← 크게 두 번 박혀 있다
// 1: LEWIS EXPERT
// 3: E.PD Kwak Yonghwan  ← 사람 이름은 한 번뿐이다
// ```
//
// ## ⚠️ 가설이 아니라 재고 넣었다 — 그리고 재서 좁혔다
//
// 다른 세션이 *"그 실마리는 가설이지 실측이 아니다. 되풀이가 사람 이름인
// 명함이 하나라도 있으면 못 쓴다"* 고 경고했다. **재 봤더니 실제로 있었다.**
//
// ```
// 표본 198장 중 되풀이가 있는 장  4장
//   그중 IMG_4540 은 **명함 여러 장이 한 사진에 든 것**이라
//   「문정순 이사」·「안해인」 같은 **사람 이름도 두 번** 나온다
// ```
//
// 📌 그래서 **바로 이웃한 줄**일 때만 로고로 본다 — 로고는 위아래로 붙여
// 박고, 떨어져 나오는 되풀이는 **다른 명함의 글자**다.
//
// ## 잰 것 — 기기 원문 96장
//
// ```
// 회사 63% → 64%     card_01 ✅ 잡힘 · card_109 ✅ 그대로 · 깨진 장 0
// ```
//
// **장 단위로 대조했다** — #691 이 «회사 21 → 24장, 깨진 장 0» 이라고 적고도
// `card_01` 을 깨뜨린 것은 **합계만 봤기 때문**이다(추가 595).
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  test('잇달아 두 번 박힌 줄은 회사다 — card_01', () {
    final r = parse([
      'LEWIS EXPERT',
      'LEWIS EXPERT',
      '+82-10-1234-5678',
      'E.PD Kwak Yonghwan +82-2-1234-5678',
      'a@example.com',
      '실장 곽용환',
    ]);
    expect(r.company, 'LEWIS EXPERT');
    expect(r.name, '곽용환');
  });

  test('🚨 되돌리지 않았다 — 전부 대문자 영문 이름은 그대로 미룬다 (card_109)', () {
    final r = parse([
      '전영환 YOUNGWHAN CHUN',
      'AI아키텍처팀 | 선임 Architect',
      'LG CNS',
      '010-1234-5678',
    ]);
    expect(r.company, 'LG CNS');
    expect(r.name, '전영환');
  });

  group('⚠️ 이웃한 되풀이만 본다 — 이 조건이 규칙의 절반이다', () {
    test('떨어져 있는 되풀이는 로고로 안 본다', () {
      // 명함 여러 장이 한 사진에 들면 **사람 이름도 두 번** 나온다
      // (실측: IMG_4540 의 「안해인」·「문정순 이사」).
      final r = parse([
        'Andy Park',
        '(주)한빛정보기술',
        '010-1234-5678',
        'Andy Park',
      ]);
      // 되풀이됐다는 이유만으로 사람 이름이 회사로 올라오면 안 된다.
      expect(r.company, contains('한빛'));
    });

    test('한 번만 인쇄된 영문 이름은 예전 그대로', () {
      final r = parse([
        'YOUNGWHAN CHUN',
        '(주)한빛정보기술',
        '홍길동',
        '010-1234-5678',
      ]);
      expect(r.company, contains('한빛'));
    });
  });
}
