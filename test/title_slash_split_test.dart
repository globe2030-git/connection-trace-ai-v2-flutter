/// **`/`·`|` 로 묶여 들어온 직함을 가른다**(2026-08-29, 52장 실측).
///
/// ## 무엇이 문제였나
///
/// 명함은 `직함 / 부서`나 `직함 / 영문직함`으로 인쇄되는 일이 흔한데, **그 줄을
/// 통째로 직함 칸에 넣고 있었다.**
///
/// ✅ **실측(globe2030님 명함 52장)**: 직함 칸은 **100% 채워졌는데 19장이
/// 이상**했고 **그중 10장이 이 모양**이었다. 🚨 **채움률로는 안 보이는 결함**이다
/// (추가 198에서 이미 데인 자리 — 빈 값을 정상으로 세면 «오분류 0장»이 나온다).
///
/// 📌 **부서 칸은 21%만 차 있었다** — 잘려 나간 조각 상당수가 부서였다.
///
/// ## 결과
///
/// ```
/// 52장   직함이 이상한 장수  19 → 11      부서 채워진 장수  11 → 16
/// 100장  19장이 바뀌었고 나빠진 것은 없었다(회귀 표본)
/// ```
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

({String title, String dept}) parse(String titleLine) {
  final r = OcrScannerService.parseLinesForTesting([
    '(주)가상상사',
    '홍길동',
    titleLine,
    '010-0000-0000',
  ]);
  return (title: r.title, dept: r.department);
}

void main() {
  group('⭐ 직함 / 부서 로 묶인 줄', () {
    test('부서를 부서 칸으로 옮긴다', () {
      final r = parse('부장 / 정보안전부');
      expect(r.title, '부장');
      expect(r.dept, '정보안전부');
    });

    test('순서가 반대여도(부서 / 직함)', () {
      final r = parse('영업부 / 차장');
      expect(r.title, '차장');
      expect(r.dept, '영업부');
    });

    test('셋으로 묶여도 — 실측에 있던 모양', () {
      final r = parse('전략사업부/기술지원팀/대리');
      expect(r.title, '대리');
      expect(r.dept, isNotEmpty);
    });

    test('「파트」로 끝나는 부서도 — 실측(card_08)', () {
      final r = parse('디지털 커뮤니케이션 파트 / 책임');
      expect(r.title, '책임');
      expect(r.dept, contains('디지털'));
    });
  });

  group('🚨 「영문 표기는 버린다」를 뒤집었다 (2026-08-30)', () {
    // ## 왜 뒤집었나
    //
    // 이 묶음의 옛 이름은 *「영문 표기는 버린다 — 같은 직함의 다른 표기다」*
    // 였고, `대표이사 / CEO` → `대표이사` 를 지키고 있었다. **그런데 명함에는
    // 그렇게 인쇄돼 있지 않다.**
    //
    // ```
    // card_02 실물   이름 아래 한 줄로  「대표이사 | CEO」
    // card_133 실물  「대표/공인중개사」 — 공인중개사는 **자격**이다
    // ```
    //
    // 기기 채점에서 직함 회귀 셋(`card_02`·`19`·`133`)이 전부 이 규칙 때문에
    // 났다. 정답지도 통째로 적고 있다(사람이 실물을 보고 적은 것이다).
    //
    // 📌 **가르기의 목적은 「부서를 건져 내는 것」이지 「직함을 줄이는 것」이
    //    아니다.** 그래서 **부서를 못 얻으면 원래 직함을 그대로 돌려준다.**
    //
    // ⚠️ **버릴 것이 없어진 것은 아니다** — `대표 ceo / HEE-JUNG JOO` 처럼
    //    사람 이름이 붙어 오는 줄은 여전히 있다. 다만 그런 줄은 이 경로까지
    //    오지 않는다(기기 원문 96장 실측에서 되살아난 장 0). 되살아나면
    //    **버릴 것을 가리는 규칙**을 따로 만들어야지, 이 규칙을 되돌리면
    //    회귀 셋이 다시 난다.
    test('부서를 못 얻으면 원래 직함을 지킨다 — `대표이사 / CEO`', () {
      expect(parse('대표이사 / CEO').title, '대표이사 / CEO');
    });

    test('자격 표기도 지킨다 — `대표/공인중개사`', () {
      expect(parse('대표/공인중개사').title, '대표/공인중개사');
    });

    test('⭐ 부서를 얻으면 그때는 가른다 — `부사장 / R&D Center`', () {
      final r = parse('부사장 / R&D Center');
      expect(r.title, '부사장');
      expect(r.dept, 'R&D Center');
    });
  });

  group('🚨 가르면 안 되는 것', () {
    test('한글 직함이 둘이면 그대로 둔다 — 직급과 직책을 나란히 찍은 명함', () {
      final r = parse('이사|본부장');
      expect(r.title, contains('이사'));
      expect(r.title, contains('본부장'));
    });

    test('직함 키워드가 없으면 손대지 않는다', () {
      final r = parse('디자인 / 기획');
      expect(r.title, contains('/'));
    });

    test('구분자가 없으면 그대로', () {
      expect(parse('선임 Architect').title, '선임 Architect');
    });
  });

  group('부서가 이미 있으면 덮지 않는다', () {
    test('먼저 찾은 부서를 지킨다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '(주)가상상사',
        '홍길동',
        '마케팅팀 | 대리',
        '010-0000-0000',
      ]);
      expect(r.department, '마케팅팀');
      expect(r.title, '대리');
    });
  });
}
