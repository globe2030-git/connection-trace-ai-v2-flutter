/// **직함이 아닌 것을 직함 칸에서 걷어낸다**(2026-08-29, 94장 실측).
///
/// ## 무엇이 들어와 있었나
///
/// ```
/// Yang, Se Yeol · Sim, Jeongwoo    영문 이름(성, 이름)
/// ###, Itaewon-ro, Yongsan-gu      주소
/// 이주배경청소년지원재단.             기관 이름
/// ```
///
/// 🚨 **빈 칸이 낫다.** 직함 칸이 채워져 있으면 이용자는 **맞게 읽혔다고
/// 생각하고 넘어간다** — 이름 칸에서와 같은 판단이다.
///
/// ⚠️ **멀쩡한 영문 직함은 건드리지 않는다.** 길이로 자르면 `Deputy general
/// manager`·`Team Leader`·`선임 Architect`가 함께 죽는다.
///
/// 🚨 **초안이 한 번 틀렸다** — 기관 접미사에 `연구원`을 넣었더니 **`책임연구원`·
/// `수석연구원`이 지워졌다.** 94장 측정이 잡았다. **기관 하나를 놓치는 것이
/// 흔한 직함 둘을 잃는 것보다 낫다.**
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String titleOf(String line) => OcrScannerService.parseLinesForTesting([
  '(주)가상상사',
  '홍길동',
  line,
  '010-0000-0000',
]).title;

void main() {
  group('🚨 걷어내는 것', () {
    test('주소가 들어온 경우 — 도로명 영문 표기', () {
      expect(titleOf('12, Itaewon-ro, Yongsan-gu'), isEmpty);
    });

    test('영문 이름 표기(성, 이름)', () {
      expect(titleOf('Yang, Se Yeol'), isEmpty);
      expect(titleOf('Sim, Jeongwoo'), isEmpty);
    });

    test('기관 이름이 통째로', () {
      expect(titleOf('이주배경청소년지원재단.'), isEmpty);
    });
  });

  group('⭐ 멀쩡한 직함은 그대로 — 회귀 확인', () {
    test('긴 영문 직함', () {
      expect(titleOf('Deputy general manager'), 'Deputy general manager');
    });

    test('Team Leader — 조직 낱말이 들어 있어도 직함이다', () {
      expect(titleOf('Team Leader'), 'Team Leader');
    });

    test('한글 + 영문', () {
      expect(titleOf('선임 Architect'), '선임 Architect');
    });

    test('🚨 「연구원」으로 끝나는 직함 — 초안이 지웠던 것', () {
      expect(titleOf('책임연구원'), '책임연구원');
      expect(titleOf('수석연구원'), '수석연구원');
    });

    test('짧은 한글 직함', () {
      expect(titleOf('대리'), '대리');
    });
  });
}
