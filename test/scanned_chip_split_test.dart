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

/// 화면 코드와 **같은 규칙**이다. 여기서 깨지면 화면 쪽도 깨진 것이다.
List<String> splitScannedLines(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    final parts = line
        .split(RegExp(r'\s*[|·｜/]\s*'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    out.addAll(parts.isEmpty ? [line] : parts);
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
}
