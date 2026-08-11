import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/korean_initial.dart';

void main() {
  group('KoreanInitial.of — 그룹 라벨', () {
    test('한글 초성', () {
      expect(KoreanInitial.of('김철수'), 'ㄱ');
      expect(KoreanInitial.of('나영희'), 'ㄴ');
      expect(KoreanInitial.of('홍길동'), 'ㅎ');
    });

    test('된소리는 기본 자음으로 접는다', () {
      expect(KoreanInitial.of('까치'), 'ㄱ'); // ㄲ→ㄱ
      expect(KoreanInitial.of('땅콩'), 'ㄷ'); // ㄸ→ㄷ
      expect(KoreanInitial.of('빵집'), 'ㅂ'); // ㅃ→ㅂ
      expect(KoreanInitial.of('싸움'), 'ㅅ'); // ㅆ→ㅅ
      expect(KoreanInitial.of('짜장'), 'ㅈ'); // ㅉ→ㅈ
    });

    test('영문은 대문자 A~Z', () {
      expect(KoreanInitial.of('John'), 'J');
      expect(KoreanInitial.of('alice'), 'A');
      expect(KoreanInitial.of('Zebra'), 'Z');
    });

    test('숫자·기호·빈 문자열은 #', () {
      expect(KoreanInitial.of('3M'), '#');
      expect(KoreanInitial.of('@handle'), '#');
      expect(KoreanInitial.of(''), '#');
      expect(KoreanInitial.of('   '), '#');
    });

    test('앞뒤 공백은 무시', () {
      expect(KoreanInitial.of('  김철수 '), 'ㄱ');
    });
  });

  group('KoreanInitial.rank — 정렬 순서: 한글 → 영문 → #', () {
    test('한글끼리는 가나다 순위', () {
      expect(
        KoreanInitial.rank('가나') < KoreanInitial.rank('다라'),
        isTrue,
      );
      expect(
        KoreanInitial.rank('하늘') > KoreanInitial.rank('바다'),
        isTrue,
      );
    });

    test('모든 한글이 모든 영문보다 앞', () {
      expect(
        KoreanInitial.rank('힣') < KoreanInitial.rank('Apple'),
        isTrue,
      );
    });

    test('영문끼리는 알파벳 순위', () {
      expect(
        KoreanInitial.rank('Apple') < KoreanInitial.rank('Banana'),
        isTrue,
      );
    });

    test('# 는 맨 뒤', () {
      expect(
        KoreanInitial.rank('Zzz') < KoreanInitial.rank('3M'),
        isTrue,
      );
      expect(
        KoreanInitial.rank('홍길동') < KoreanInitial.rank('#tag'),
        isTrue,
      );
    });
  });

  group('KoreanInitial.rankOfGroup — 그룹 라벨 직접 환산(점프 버그 회귀 방지)', () {
    test('초성 라벨 "ㄱ"은 이름 "가나"와 같은 순위(0)여야 한다', () {
      // 예전엔 인덱스 바에서 rank("ㄱ")를 호출해 of("ㄱ")가 호환 자모라 '#'로
      // 오판 → targetRank가 40이 되어 점프가 안 먹었다. rankOfGroup은 라벨을
      // 직접 환산해 이 문제를 없앤다.
      expect(KoreanInitial.rankOfGroup('ㄱ'), KoreanInitial.rank('가나'));
      expect(KoreanInitial.rankOfGroup('ㅎ'), KoreanInitial.rank('하늘'));
    });

    test('영문 라벨 "J"는 이름 "John"과 같은 순위', () {
      expect(KoreanInitial.rankOfGroup('J'), KoreanInitial.rank('John'));
    });

    test('"#" 라벨은 맨 뒤 순위', () {
      expect(
        KoreanInitial.rankOfGroup('#') > KoreanInitial.rankOfGroup('Z'),
        isTrue,
      );
    });
  });
}
