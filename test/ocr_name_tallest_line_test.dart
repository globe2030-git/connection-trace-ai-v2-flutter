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

    test('높이를 모르면 예전 그대로 첫 줄이다', () {
      // 높이 정보가 없는 입력에서는 동작이 바뀌면 안 된다.
      final r = OcrScannerService.parseLinesForTesting(const [
        '영업부',
        '김철수',
      ]);
      expect(r.name.replaceAll(' ', ''), '영업부');
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
