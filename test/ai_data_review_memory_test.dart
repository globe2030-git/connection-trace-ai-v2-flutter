// F-08 — "AI에 보낼 정보"가 직전에 고른 것을 어떻게 기억하는지 검증한다.
//
// 왜 이걸 따로 보나: 이 기억은 **다음 번 AI 요청에 무엇이 실려 나가는지**를
// 정한다. 규칙이 틀리면 사용자가 지운 문장이 다시 전송되거나, 앞 계정의
// 메모가 뒷사람 화면에 뜬다 — 둘 다 화면상으로는 아무 이상이 없어 눈으로는
// 못 잡는다(CLAUDE.md 4절 "코드는 맞는데 실물이 틀린" 유형).
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/models/ai_data_review_memory.dart';

void main() {
  setUp(AiDataReviewMemory.clear);

  group('처음 열 때', () {
    test('아무것도 기억된 것이 없으면 빈 상태로 시작한다 — 기본 제외(opt-in)', () {
      expect(AiDataReviewMemory.selectionFor('c1'), isEmpty);
      expect(AiDataReviewMemory.noteFor('c1'), '');
    });
  });

  group('기억하기', () {
    test('고른 기록과 적은 메모를 인맥별로 기억한다', () {
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: {'log-1', 'log-2'},
        note: '지난주에 만기 얘기 나눔',
      );

      expect(AiDataReviewMemory.selectionFor('c1'), {'log-1', 'log-2'});
      expect(AiDataReviewMemory.noteFor('c1'), '지난주에 만기 얘기 나눔');
    });

    test('다른 인맥의 기억이 섞이지 않는다', () {
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: {'log-1'},
        note: 'c1 메모',
      );
      AiDataReviewMemory.remember(
        contactId: 'c2',
        selectedLogIds: {'log-9'},
        note: 'c2 메모',
      );

      expect(AiDataReviewMemory.selectionFor('c1'), {'log-1'});
      expect(AiDataReviewMemory.noteFor('c1'), 'c1 메모');
      expect(AiDataReviewMemory.selectionFor('c2'), {'log-9'});
      expect(AiDataReviewMemory.noteFor('c2'), 'c2 메모');
    });

    test('메모의 앞뒤 공백은 떼고 기억한다', () {
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '  만기 8월  ',
      );
      expect(AiDataReviewMemory.noteFor('c1'), '만기 8월');
    });

    test('돌려준 집합을 밖에서 고쳐도 기억이 바뀌지 않는다', () {
      // 호출자가 받은 집합에 add 해서 기억이 조용히 바뀌면, 사용자가 안 고른
      // 기록이 다음 전송에 실린다.
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: {'log-1'},
        note: '',
      );
      AiDataReviewMemory.selectionFor('c1').add('log-침입');

      expect(AiDataReviewMemory.selectionFor('c1'), {'log-1'});
    });

    test('넘긴 집합을 나중에 고쳐도 기억이 따라 바뀌지 않는다', () {
      final selected = {'log-1'};
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: selected,
        note: '',
      );
      selected.add('log-나중');

      expect(AiDataReviewMemory.selectionFor('c1'), {'log-1'});
    });
  });

  group('지운 것은 지운 채로 남는다', () {
    test('메모를 비우면 다음에 되살아나지 않는다', () {
      // ⚠️ 이게 이 파일에서 가장 중요한 검사다. 사용자가 지운 문장이 다음
      // 요청에 다시 실리면, 그건 **동의하지 않은 내용을 보내는 것**이 된다.
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '보내면 안 되는 내용',
      );
      expect(AiDataReviewMemory.noteFor('c1'), '보내면 안 되는 내용');

      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '',
      );
      expect(AiDataReviewMemory.noteFor('c1'), '');
    });

    test('공백만 남긴 것도 비운 것으로 본다', () {
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '뭔가 적었다',
      );
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '   ',
      );
      expect(AiDataReviewMemory.noteFor('c1'), '');
    });

    test('선택을 모두 해제하면 다음에 되살아나지 않는다', () {
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: {'log-1', 'log-2'},
        note: '',
      );
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: const {},
        note: '',
      );
      expect(AiDataReviewMemory.selectionFor('c1'), isEmpty);
    });
  });

  group('계정이 바뀔 때', () {
    test('clear()가 모든 인맥의 기억을 비운다', () {
      // 로그아웃·계정 삭제 뒤 같은 실행 안에서 다른 계정으로 들어가면, 앞
      // 사람이 제3자에 대해 쓴 문장이 뒷사람 화면에 뜨면 안 된다.
      AiDataReviewMemory.remember(
        contactId: 'c1',
        selectedLogIds: {'log-1'},
        note: '앞 계정이 쓴 메모',
      );
      AiDataReviewMemory.remember(
        contactId: 'c2',
        selectedLogIds: {'log-2'},
        note: '앞 계정이 쓴 다른 메모',
      );

      AiDataReviewMemory.clear();

      expect(AiDataReviewMemory.noteFor('c1'), '');
      expect(AiDataReviewMemory.noteFor('c2'), '');
      expect(AiDataReviewMemory.selectionFor('c1'), isEmpty);
      expect(AiDataReviewMemory.selectionFor('c2'), isEmpty);
    });
  });
}
