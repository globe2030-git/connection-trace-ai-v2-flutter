// 회사명 앞에 붙어 온 영문 로고를 떼는 규칙 (추가 612).
//
// 🚨 **왜 있나**: `_stripCompanyLogoPrefix` 주석은 99장 자를 근거로 `KYWA`·
// `SSiS` 같은 3~4자를 **일부러 남겨 뒀다**. 그런데 자가 190장으로 넓어지자
// 같은 모양이 여섯 장 나왔고, 정답지는 전부 **떼라**고 했다.
//
// ⚠️ 이 검사는 **양쪽을 다 고정한다** — 떼야 할 것이 안 떼지는 것도, 두어야 할
// 브랜드 접두(`GS 스포츠`·`SK telecom`)가 잘리는 것도 회귀다. 예전에 상한만
// 넓혔다가 **9장을 잃은 적이 있다.**
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _card(String companyLine) => [
  companyLine,
  '박병학 가치센터팀/ 팀장',
  '05540 서울특별시 송파구 올림픽로 424 Tel 02.410.1403',
  'Mobile 010.5245.1833 E-mail a@b.or.kr',
];

void main() {
  group('영문 로고 + 한글 기관 이름 → 로고를 뗀다', () {
    for (final c in const [
      ('KYWA 한국청소년활동진흥원', '한국청소년활동진흥원'),
      ('SSiS 한국사회보장정보원', '한국사회보장정보원'),
      ('KSPO 국민체육진흥공단', '국민체육진흥공단'),
      // 붙여 쓴 것도 같다 — IMG_4265는 띄어쓰기가 없었다.
      ('KSPO국민체육진흥공단', '국민체육진흥공단'),
    ]) {
      test('${c.$1} → ${c.$2}', () {
        expect(OcrScannerService.stripCompanyLogoPrefixForTesting(c.$1), c.$2);
      });
    }
  });

  group('🚨 브랜드 접두는 회사명의 일부다 — 자르면 안 된다', () {
    // 꼬리가 기관 이름이 아니면 앞의 영문은 브랜드다. 「보험」·「전자」·「스포츠」를
    // 꼬리 목록에 넣지 않은 이유가 이것이다.
    for (final c in const [
      ('GS 스포츠', 'GS 스포츠'),
      ('AXA 손해보험', 'AXA 손해보험'),
      ('NH농협손해보험', 'NH농협손해보험'),
    ]) {
      test('${c.$1} 는 그대로', () {
        expect(OcrScannerService.stripCompanyLogoPrefixForTesting(c.$1), c.$2);
      });
    }
  });

  group('같은 로고가 두 번 찍힌 것', () {
    test('LG LG CNS → LG CNS', () {
      expect(
        OcrScannerService.stripCompanyLogoPrefixForTesting('LG LG CNS'),
        'LG CNS',
      );
    });

    // ⚠️ 되풀이는 **낱말 단위**로 본다. 앞자리만 보면 아래가 「smetics」가 된다.
    test('CO Cosmetics 는 그대로 — 낱말 경계가 없다', () {
      expect(
        OcrScannerService.stripCompanyLogoPrefixForTesting('CO Cosmetics'),
        'CO Cosmetics',
      );
    });
  });

  test('🚨 로고를 떼도 그 줄이 부서로 딸려 오면 안 된다', () {
    // 회사 칸에서 로고를 떼자 **부서 칸이 무너졌다**(IMG_4265·4267). 부서 윗줄
    // 규칙이 「회사로 고른 줄」을 **글자 완전일치**로 가려내고 있었기 때문이다.
    final r = OcrScannerService.parseLinesForTesting(_card('KSPO국민체육진흥공단'));
    expect(r.company, '국민체육진흥공단');
    expect(r.department, '가치센터팀');
  });
}
