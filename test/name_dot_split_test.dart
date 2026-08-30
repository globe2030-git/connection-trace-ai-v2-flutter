// **`그룹장` 의 `그룹` 이 회사 키워드에 걸리던 것**을 고친다(2026-08-30).
//
// ## 증상
//
// ```
// 임준석.그룹장/상무   →  줄 전체가 **회사 칸**으로 갔다
//                        이름은 옆줄의 영문(`LIM JUNSEOK`)이 차지했다
//   정답: 이름 「임준석」 · 직함 「그룹장/상무」 · 회사 **빈칸**
// ```
//
// 같은 명함의 `안민식.이사` 는 제대로 갈렸다. 차이는 **`그룹장`** 하나였다.
//
// ## 원인 — 이 파일이 네 번째로 겪는 부분 문자열 함정
//
// `그룹` 은 회사 키워드(`삼성그룹`)인데 **`그룹장` 은 직함**이다. 회사 줄로
// 판정되는 순간 직함 키워드 매칭 자체를 건너뛰고 회사 후보로 흘러간다.
//
// ```
// SK telecom 의 tel      추가 178·180
// .co.kr 의 Co.          추가 183
// ceonitios 의 ceo       추가 592
// 그룹장 의 그룹           ← 이번
// ```
//
// > **회사 낱말 뒤에 `장` 이 붙으면 그것은 사람의 직함이지 회사가 아니다.**
//
// ## ⚠️ 이름을 얻고 부서를 잃을 뻔했다
//
// 고치자 `UX Group. Executive Leader` 가 **직함 줄로 안 잡히면서 부서를 통째로
// 잃었다**(부서 75% → 73%). 영문 조직 줄에서도 부서를 집도록 넓혀 되찾았다.
//
// 그런데 그 규칙이 이번엔 **`Head of R&D Dept.` 를 부서로** 집었다(오검출 2장).
// **조직 꼬리로 끝나도 앞에 직함 낱말이 있으면 그 사람의 자리**다.
//
// 📌 **한 칸을 고치면 옆 칸이 움직인다. 장 단위로 안 보면 합계 뒤에 숨는다.**
//
// ## 잰 것 — 기기 원문 96장
//
// ```
// 이름   84% → 85%     일치 81 → 82
// 부서   75% → 75%     회사 64% · 직함 67% 그대로 · 오검출 0
// ```
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  test('`그룹장` 은 직함이다 — 줄이 회사 칸으로 가지 않는다', () {
    final r = parse([
      '임준석.그룹장/상무',
      'LIM JUNSEOK',
      'UX Group. Executive Leader',
      '010 1234 5678',
    ]);
    expect(r.name, '임준석');
    expect(r.title, '그룹장/상무');
  });

  test('띄어 쓴 것도 같다', () {
    final r = parse(['임준석 그룹장/상무', 'LIM JUNSEOK', '010 1234 5678']);
    expect(r.name, '임준석');
    expect(r.title, '그룹장/상무');
  });

  test('⚠️ `그룹` 이 진짜 회사일 때는 그대로 — 회귀 확인', () {
    final r = parse(['홍길동', '대리', '삼성그룹', '010-1234-5678']);
    expect(r.company, '삼성그룹');
  });

  group('영문 조직 줄에서도 부서를 집는다', () {
    test('한글 부서가 있는 줄과 나란히 있으면 영문 조직도 부서로 간다', () {
      final r = parse([
        '홍길동',
        '대리',
        '(주)한빛정보기술',
        'BX Center. Business Manager',
        '010-1234-5678',
      ]);
      expect(r.department, 'BX Center');
    });

    // ⬜ **`card_214` 는 이 검사로 못 덮는다 — 알고 비워 둔다.**
    //
    // 그 명함은 **회사명이 인쇄돼 있지 않아**(정답 회사 = 빈칸) 좌표 없이
    // 줄만 주면 `UX Group.` 이 **회사 후보로 먼저** 잡혀 부서까지 오지 않는다.
    // 실제 채점 경로(`parseLinesForTestingWithBoxes`)는 **좌표를 함께** 먹여
    // 회사 고르기가 달라지고, 거기서는 부서 `UX Group` 이 나온다(96장 실측).
    //
    // 📌 **검사에서 되는 것처럼 꾸미지 않는다.** 좌표가 필요한 자리는 코퍼스
    //    측정이 덮고, 이 파일은 좌표 없이도 성립하는 것만 잠근다.

    test('🚨 `Head of R&D Dept.` 는 부서가 아니라 직함이다', () {
      // 조직 꼬리로 끝나도 **앞에 직함 낱말이 있으면** 그 사람의 자리다.
      // 실측에서 2장이 부서 칸에 들어갔다.
      final r = parse([
        '홍길동',
        'Head of R&D Dept. Urban Air Mobility',
        '(주)한빛정보기술',
        '010-1234-5678',
      ]);
      expect(r.department, isEmpty);
    });
  });
}
