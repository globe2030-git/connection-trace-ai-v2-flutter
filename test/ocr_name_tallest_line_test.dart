import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 추가 405 — 한글 2~4자 줄이 여럿이면 **가장 큰 줄**을 이름으로 본다.
///
/// 명함에는 부서명·브랜드어처럼 **이름과 형태가 똑같은 한글 2~4자 줄**이 이름보다
/// 위에 있는 경우가 흔하다. 예전에는 규칙에 걸리는 **첫 줄**을 썼기 때문에 그때
/// 이름을 영영 못 찾았다.
///
/// 실측(정답지 대조 95장, 2026-08-22): 첫 줄 70% → 가장 큰 줄 82%.
void main() {
  group('이름: 후보가 여럿이면 가장 큰 줄', () {
    test('이름보다 위에 있는 같은 형태의 줄에 뺏기지 않는다', () {
      final r = OcrScannerService.parseLinesForTestingWithHeights(const [
        (text: '영업부', height: 30), // 이름과 형태가 같다(한글 3자)
        (text: '김철수', height: 90), // 실제 이름 — 훨씬 크게 인쇄된다
        (text: '010-1234-5678', height: 28),
      ]);
      expect(r.name.replaceAll(' ', ''), '김철수');
    });

    test('⚠️ 살짝 큰 정도로는 안 바꾼다 — 잡음일 수 있다', () {
      // 여유 1.1배는 글자 크기 폴백(fontSizePreferred)이 쓰던 값과 같다.
      final r = OcrScannerService.parseLinesForTestingWithHeights(const [
        (text: '홍길동', height: 100),
        (text: '박영희', height: 105), // 5%만 크다 → 첫 줄 유지
      ]);
      expect(r.name.replaceAll(' ', ''), '홍길동');
    });

    test('⭐ 높이를 몰라도 성씨로 시작하는 쪽을 고른다 (추가 413에서 바뀜)', () {
      // **이 테스트는 원래 `영업부`를 기대했다.** 높이 정보가 없으면 첫 줄이
      // 이긴다는, 그때의 동작을 그대로 못 박아 둔 것이었다.
      //
      // 추가 413에서 그 동작이 실제로 틀렸다는 것이 실물로 드러났다. 기관명
      // (`통일부`)이 한글 2~4자라 이름 규칙을 그대로 통과하고, 하필 진짜
      // 이름보다 위에 인쇄돼 있어서 이름 자리를 차지했다. 그리고 **밀려난
      // 진짜 이름이 회사 칸으로 들어갔다** — 테스터 B가 8/20에 보고한 증상이
      // 바로 이것이다.
      //
      // 기기 측정본 96장 전후 대조에서 **이름 +2 · 회사 +1 · 깨짐 0**이었다.
      // 그래서 기대값을 바꾼다 — 예전 동작이 옳아서 잠가 둔 것이 아니라,
      // 바뀌지 않는지 보려고 잠가 둔 것이었기 때문이다.
      final r = OcrScannerService.parseLinesForTesting(const [
        '영업부',
        '김철수',
      ]);
      expect(r.name.replaceAll(' ', ''), '김철수');
    });

    test('⚠️ 성씨 목록에 없어도 대안이 없으면 그대로 쓴다', () {
      // 성씨 목록은 79개라 드문 성을 놓칠 수 있다. 그때 이름이 통째로
      // 사라지면 훨씬 나쁘므로, **성씨로 시작하는 다른 후보가 있을 때만**
      // 미룬다(영문 사람 이름 판정의 안전판과 같은 방식).
      final r = OcrScannerService.parseLinesForTesting(const [
        '가나다',
        '주식회사 어디',
      ]);
      expect(r.name.replaceAll(' ', ''), '가나다');
    });

    test('후보가 하나뿐이면 그대로 쓴다', () {
      final r = OcrScannerService.parseLinesForTestingWithHeights(const [
        (text: '김철수', height: 90),
        (text: '주식회사 어디', height: 40),
      ]);
      expect(r.name.replaceAll(' ', ''), '김철수');
    });

    test('밀려난 줄은 사라지지 않고 회사명 후보로 남는다', () {
      // 이름 자리를 뺏긴 줄을 버리면 회사명이 빈 값이 되는 회귀가 있었다.
      final r = OcrScannerService.parseLinesForTestingWithHeights(const [
        (text: '가나다', height: 30),
        (text: '김철수', height: 95),
      ]);
      expect(r.name.replaceAll(' ', ''), '김철수');
      expect(r.company.replaceAll(' ', ''), '가나다');
    });

    test('공백을 벌려 인쇄한 이름도 같은 규칙을 탄다', () {
      final r = OcrScannerService.parseLinesForTestingWithHeights(const [
        (text: '기획팀', height: 32),
        (text: '최 태 웅', height: 96),
      ]);
      expect(r.name.replaceAll(' ', ''), '최태웅');
    });
  });
}
