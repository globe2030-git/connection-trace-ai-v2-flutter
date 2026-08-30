// 회사명 안에서 벌어진 띄어쓰기 (추가 614).
//
// 부서 쪽에는 `_tidyDepartment` 로 같은 규칙이 있었는데 **회사 칸에는 없었다.**
//
// ⚠️ 이 검사의 반은 **하지 않기로 한 것**을 지킨다. 정답지가 띄어쓰기까지
// 그대로 요구하는 장이 있다(`(주) 잇팩`).
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String join(String s) =>
    OcrScannerService.joinBrokenCompanySpacesForTesting(s);

void main() {
  group('⭐ 한 글자로 벌어진 조각은 붙인다', () {
    test('라움소프 트 → 라움소프트 (card_104)', () {
      expect(join('라움소프 트'), '라움소프트');
    });
    test('라움 소 프트 → 라움소프트 (card_114) — 되풀이해서 닫는다', () {
      expect(join('라움 소 프트'), '라움소프트');
    });
    test('영문 머리와 한글 사이도 붙인다 — SK 텔레콤 (IMG_4239)', () {
      expect(join('SK 텔레콤'), 'SK텔레콤');
    });
  });

  group('🚨 뜻이 있는 띄어쓰기는 붙이지 않는다', () {
    test('법인 표기가 있으면 손대지 않는다 — 주식회사 디엠지그룹', () {
      expect(join('주식회사 디엠지그룹'), '주식회사 디엠지그룹');
    });
    test('정답지가 띄어쓰기까지 요구하는 장이 있다 — (주) 잇팩 (IMG_4259)', () {
      expect(join('(주) 잇팩'), '(주) 잇팩');
    });
    test('온전한 낱말 사이는 붙이지 않는다 — 법무법인 동률', () {
      expect(join('법무법인 동률'), '법무법인 동률');
    });
  });

  test('⭐ 쉼표 낀 영문 로고보다 한글 회사명을 고른다 — card2', () {
    // `Souloreoul, FC SEOUL` 은 로고(`Soul of Seoul`)를 잘못 읽은 것이다.
    // ⚠️ **낱말 사이에 쉼표·마침표가 낀 것만** 로고로 본다 — `LG CNS`·
    //    `TWINS LG` 같은 진짜 영문 회사명은 여기 안 걸린다.
    final r = OcrScannerService.parseLinesForTesting([
      'Souloreoul, FC SEOUL',
      'GS 스포츠',
      '김인 준',
      '마케팅팀 대리',
      'FC서울프로축구단 | GS칼텍스서울kixx배구단',
      '서울시 마포구 윌드컵로 240 서울월드컵경기장',
    ]);
    expect(r.company, 'GS스포츠');
  });
}
