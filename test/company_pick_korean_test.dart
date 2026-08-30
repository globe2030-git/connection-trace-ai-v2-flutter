// 영문 로고와 한글 회사명이 함께 있을 때 무엇을 고르나 (추가 614).
//
// 🚨 **고르기는 점수가 아니라 순서였다.** `_pickCompanyFromLeftover` 는
// `indexWhere` 사슬이라 **줄 순서상 먼저 나온 것**을 집는데, 명함은 로고를 맨
// 위에 박으므로 **영문 로고가 한글 회사명보다 늘 먼저 온다.**
//
// ⚠️ **이 검사의 반은 「하지 않기로 한 것」을 지킨다.** 처음에 순수 영문을
// 전부 뒤로 밀었더니 **한 장 얻고 네 장 잃었다** — `LG CNS`·`TWINS LG`·
// `LEWIS EXPERT` 는 진짜 영문 회사명이다. 그래서 **한 낱말 + 전부 대문자**
// 일 때만 민다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('⭐ 한 낱말 대문자 로고보다 한글 회사명을 고른다 — card_123', () {
    final r = OcrScannerService.parseLinesForTesting([
      '조남국',
      'SAMSUNG',
      '팀장 서울사업팀 서울동부지사',
      'M010-8955-8259',
      '05020 서울특별시 광진구 동일로 120',
      '에스원 namkook.cho@samsung.com',
    ]);
    expect(r.company, '에스원');
  });

  group('🚨 진짜 영문 회사명은 밀지 않는다 — 넓게 밀었다가 네 장 잃었다', () {
    // ⚠️ **아래 셋은 실제 명함 줄이다.** 처음에는 지어낸 줄로 검사를 짰는데,
    // 190장 자에서는 안 깨지는 것이 검사에서는 깨졌다 — 지어낸 줄에는 실제
    // 명함에 있는 다른 줄이 없어서 **다른 경로로 흘러갔다.** 규칙이 실제로
    // 무엇을 지키는지 보려면 실물 줄이어야 한다.

    test('낱말이 둘이면 밀지 않는다 — LG CNS (card_216)', () {
      final r = OcrScannerService.parseLinesForTesting([
        '조원창',
        'DT Optimization사업부 경영관리사업담당',
        'LG경영정보팀 / 선임',
        'GLG',
        'LG CNS',
        '05500',
        '서울특별시 송파구 올림픽로 25 (잠실동) 잠실 종합운동장 LG스포츠',
      ]);
      expect(r.company, 'LG CNS');
    });

    test('한글 줄이 여럿 있어도 영문 회사명을 지킨다 — LG CNS (card_109)', () {
      final r = OcrScannerService.parseLinesForTesting([
        '전영환 YOUNGWVHAN CHUN',
        'AI 아키텍처팀 | 선임 Architect',
        'LG CNS',
        '07795 서울특별시 강서구 마곡중앙8로 71',
        'LG사이언스파크',
      ]);
      expect(r.company, 'LG CNS');
    });

    test('잇달아 두 번 박힌 것은 로고이면서 회사명이다 — LEWIS EXPERT (card_01)', () {
      // 추가 601이 세운 규칙이다. 여기서 함께 밀면 그 회귀가 되살아난다.
      final r = OcrScannerService.parseLinesForTesting([
        'LEWIS EXPERT',
        'LEWIS EXPERT',
        'E.PD Kwak Yonghwan',
        '실장 곽용환',
      ]);
      expect(r.company, 'LEWIS EXPERT');
    });
  });
}
