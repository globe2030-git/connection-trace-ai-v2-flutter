// 원문 줄을 **명함에 인쇄된 구분자**에서 쪼개는 규칙을 고정한다(추가 325).
//
// 왜: 한 줄에 둘이 들어 있는 명함이 흔해서(`A아키텍처팀 | 선임 Architect`)
// 퀵 매핑으로 어느 칸에 보내도 나머지가 딸려 갔다.
//
// ⚠️ **파서 판단으로 나누지 않는다.** 파서가 놓친 값은 조각으로도 안 나오게
// 되어 원문이 안전망 노릇을 못 한다. 인쇄된 구분자에서만 자른다.
//
// ⚠️ **공백·한글↔영문 경계로는 안 자른다.** 실측 103장에서 칩이 평균 8.2 →
// 24개(최대 147)로 폭증했다. 주소 줄이 조각조각 나는데 주소는 통째로 옮겨야
// 하는 값이다.
import 'package:flutter_test/flutter_test.dart';

final _valueShape = RegExp(
  r'[\w.+-]+@[\w.-]+\.\w+'
  r'|(?:https?://|www\.)[\w./\-]+'
  r'|\d{2,4}[-. ]\d{3,4}[-. ]\d{4}'
  r'|01\d{9}|0\d{9,10}',
);

/// 화면 코드와 **같은 규칙**이다. 여기서 깨지면 화면 쪽도 깨진 것이다.
List<String> splitScannedLines(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    final pieces = line
        .split(RegExp(r'\s*[|·｜/]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    for (final piece in (pieces.isEmpty ? [line] : pieces)) {
      final values = _valueShape.allMatches(piece).toList();
      // 값 하나라도, **값 아닌 자리에 한글이 있으면** 떼어낸다.
      // `이현석 M 010-9354-5742`처럼 이름과 전화가 한 덩어리로 읽히는
      // 명함이 흔하다 — 그대로 두면 이름 칸으로 보낼 때 전화가 딸려 간다.
      // 영문 라벨(`T` `F` `Mobile.`)은 한글이 아니라 안 걸린다 — 그건
      // 떼어내면 쓸모없는 칩만 늘어난다(추가 327).
      final restHasHangul =
          RegExp(r'[가-힣]').hasMatch(piece.replaceAll(_valueShape, ' '));
      if (values.length < 2 && !(values.length == 1 && restHasHangul)) {
        out.add(piece);
        continue;
      }
      var last = 0;
      for (final m in values) {
        final head = piece.substring(last, m.start).trim();
        if (head.isNotEmpty) out.add(head);
        out.add(m.group(0)!);
        last = m.end;
      }
      final tail = piece.substring(last).trim();
      if (tail.isNotEmpty) out.add(tail);
    }
  }
  return out;
}

void main() {
  group('원문 칩 쪼개기 (추가 325)', () {
    test('⭐ 세로줄로 나뉜 부서·직함이 갈라진다', () {
      expect(splitScannedLines(['A아키텍처팀 | 선임 Architect']),
          ['A아키텍처팀', '선임 Architect']);
    });

    test('⭐ 슬래시·가운뎃점도 구분자다', () {
      expect(splitScannedLines(['영업대표/부장']), ['영업대표', '부장']);
      expect(splitScannedLines(['이사 · 연구소장']), ['이사', '연구소장']);
    });

    test('⚠️ 구분자가 없으면 줄 그대로다 — 공백으로는 안 자른다', () {
      expect(splitScannedLines(['전영환 YOUNGWHAN CHUN']),
          ['전영환 YOUNGWHAN CHUN']);
    });

    test('⚠️ 주소는 통째로 남는다 — 조각내면 옮길 수가 없다', () {
      expect(splitScannedLines(['07795 서울특별시 강서구 마곡중앙8로 71']),
          ['07795 서울특별시 강서구 마곡중앙8로 71']);
    });

    test('빈 조각은 버린다', () {
      expect(splitScannedLines(['팀장 |']), ['팀장']);
      expect(splitScannedLines(['| | |']), ['| | |']);
    });
  });

  // ── 값이 둘 이상 든 줄 (추가 326) ──────────────────────────────────
  group('값이 둘 이상 든 줄은 값 경계에서도 쪼갠다 (추가 326)', () {
    test('⭐ 전화 셋이 한 줄에 있으면 셋으로 갈라진다', () {
      expect(
        splitScannedLines(['T 02-6360-6910 F 02-6360-6930 M 010-9354-5742']),
        ['T', '02-6360-6910', 'F', '02-6360-6930', 'M', '010-9354-5742'],
      );
    });

    test('⭐ 이메일 둘도 갈라진다', () {
      expect(splitScannedLines(['a@sto.or.kr b@sto.or.kr']),
          ['a@sto.or.kr', 'b@sto.or.kr']);
    });

    // ⚠️ 여기가 ④(전부 쪼개기)와 갈리는 자리다. 값이 하나뿐인 줄까지 자르면
    // 'T' 같은 라벨이 쓸모없는 칩으로 떨어져 나온다. 전화 칸에 넣을 때는
    // 포맷터가 숫자만 뽑으므로 라벨이 붙어 있어도 상관없다.
    test('⚠️ 값이 하나면 안 쪼갠다 — 라벨이 붙은 채로 둔다', () {
      expect(splitScannedLines(['T 02-6360-6910']), ['T 02-6360-6910']);
      expect(splitScannedLines(['Mobile. 010-1234-5678']),
          ['Mobile. 010-1234-5678']);
    });

    test('⚠️ 값이 없는 줄은 그대로다', () {
      expect(splitScannedLines(['서울특별시 강서구 마곡중앙8로 71']),
          ['서울특별시 강서구 마곡중앙8로 71']);
    });

    test('구분자로 먼저 자르고, 그 조각 안에서 값을 본다', () {
      expect(
        splitScannedLines(['팀장 | T 02-111-2222 F 02-111-3333']),
        ['팀장', 'T', '02-111-2222', 'F', '02-111-3333'],
      );
    });
  });

  // ── 값 옆에 한글이 있으면 떼어낸다 (2026-08-19 실기기 제보, 추가 327) ──
  group('이름과 전화가 한 덩어리로 읽힌 줄 (추가 327)', () {
    test('⭐ 이름 + 라벨 + 전화가 갈라진다', () {
      expect(splitScannedLines(['이현석 M 010-9354-5742']),
          ['이현석 M', '010-9354-5742']);
    });

    test('⭐ 회사명 + 전화도 갈라진다', () {
      expect(splitScannedLines(['크림하우스 02-508-2712']),
          ['크림하우스', '02-508-2712']);
    });

    // ⚠️ 영문 라벨만 있으면 안 떼어낸다 — 떼면 'T' 같은 쓸모없는 칩이 는다.
    // 전화 칸에 넣을 때 어차피 숫자만 뽑히므로 붙어 있어도 상관없다.
    test('⚠️ 영문 라벨만 붙은 줄은 그대로다', () {
      expect(splitScannedLines(['T 02-6360-6910']), ['T 02-6360-6910']);
      expect(splitScannedLines(['Mobile. 010-1234-5678']),
          ['Mobile. 010-1234-5678']);
    });

    test('⚠️ 한글이 있어도 값이 없으면 그대로다', () {
      expect(splitScannedLines(['서울특별시 강서구 마곡중앙8로']),
          ['서울특별시 강서구 마곡중앙8로']);
    });
  });
}
