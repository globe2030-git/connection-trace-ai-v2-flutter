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
}
