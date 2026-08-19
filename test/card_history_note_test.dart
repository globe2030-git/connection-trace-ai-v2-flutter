// 메모에 쌓인 이전 명함 기록을 날짜별로 가르는 것(추가 333).
//
// ⚠️ 이 테스트가 지키는 것은 **가르기**지 **되살리기**가 아니다. 칸을 추측해
// 붙이지 않는다는 것 자체가 요구사항이라, 그것도 함께 못박아 둔다.
import 'package:connection_trace_ai_flutter/core/utils/card_history_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('이력 가르기', () {
    test('빈 메모·null이면 빈 목록', () {
      expect(CardHistoryNote.parse(null), isEmpty);
      expect(CardHistoryNote.parse(''), isEmpty);
    });

    test('이력이 없는 메모에서는 아무것도 안 나온다', () {
      expect(CardHistoryNote.parse('점심 같이 먹기로 함'), isEmpty);
    });

    test('한 건을 날짜와 내용으로 가른다', () {
      final r = CardHistoryNote.parse('[이전 정보 · 2026-08-19] 옛회사 / 과장');
      expect(r, hasLength(1));
      expect(r.first.date, '2026-08-19');
      expect(r.first.content, '옛회사 / 과장');
    });

    test('여러 건은 적힌 순서 그대로 — 새 기록이 위에 붙으므로 최신이 앞', () {
      final r = CardHistoryNote.parse(
        '[이전 정보 · 2026-08-19] 새회사 / 부장\n'
        '[이전 정보 · 2026-05-02] 옛회사 / 과장',
      );
      expect(r.map((e) => e.date), ['2026-08-19', '2026-05-02']);
    });

    test('사용자가 쓴 메모가 섞여 있어도 이력만 골라낸다', () {
      final memo = '[이전 정보 · 2026-08-19] 옛회사 / 과장\n'
          '소개해 준 사람: 김팀장\n'
          '커피 좋아함';
      expect(CardHistoryNote.parse(memo), hasLength(1));
      expect(CardHistoryNote.userMemo(memo), '소개해 준 사람: 김팀장\n커피 좋아함');
    });

    test('⚠️ 내용이 빈 이력 줄은 버린다 — 보여 줄 것이 없다', () {
      expect(CardHistoryNote.parse('[이전 정보 · 2026-08-19] '), isEmpty);
    });

    test('날짜 모양이 아니면 이력으로 보지 않는다', () {
      expect(CardHistoryNote.parse('[이전 정보 · 어제] 옛회사'), isEmpty);
    });

    group('⚠️ 칸을 되살리려 하지 않는다 — 되살릴 수 없기 때문이다', () {
      test('조각 개수가 명함마다 다르다 (빈 칸은 통째로 빠져서 기록됐다)', () {
        // 실제 기록 방식: 값이 없는 칸은 아예 안 들어간다.
        // 그래서 "세 번째 조각 = 부서"라고 말할 수 없다.
        final many = CardHistoryNote.parse(
          '[이전 정보 · 2026-08-19] 회사 / 부장 / 영업팀 / 010-0000-0001',
        ).first;
        final few = CardHistoryNote.parse(
          '[이전 정보 · 2026-08-19] 회사 / 부장',
        ).first;
        expect(many.content.split(' / '), hasLength(4));
        expect(few.content.split(' / '), hasLength(2));
        // 내용은 **적힌 그대로**다 — 칸 이름이 붙어 나오지 않는다.
        expect(many.content, isNot(contains('부서')));
        expect(many.content, isNot(contains('회사명')));
      });

      test('값 안에 구분자가 들어가도 건드리지 않는다', () {
        // 주소에 `/`가 흔하다. 쪼개려 들면 여기서 어긋난다.
        const raw = '회사 / 부장 / 서울시 강남구 A로 1/2';
        final r = CardHistoryNote.parse('[이전 정보 · 2026-08-19] $raw').first;
        expect(r.content, raw);
      });
    });
  });
}
