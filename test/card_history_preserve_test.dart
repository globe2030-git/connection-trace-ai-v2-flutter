import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/card_history_note.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨 **이력이 저장하면 사라지던 것**을 막는다(2026-08-28).
///
/// ## 무엇이 새고 있었나
///
/// 편집 화면이 메모 칸에 **이력 줄까지 통째로** 띄우고, 저장할 때 그 텍스트를
/// 그대로 덮어썼다. **이용자가 메모를 정리하며 `[이전 정보 · …]` 줄을 지우면
/// 이력이 영영 사라졌다.**
///
/// ⭐ [CardHistoryNote.userMemo]가 정확히 그것을 막으려고 있었는데 **부르는
/// 곳이 없었다** — `grep -rn "userMemo" lib` 로 확인했을 때 정의 한 줄뿐이었다.
/// CLAUDE.md 4절 표의 *"서비스는 정상, 부르는 쪽이 없음"* 과 같은 자리다.
///
/// 🚨 **그리고 합치기 경로에는 더 조용한 것이 있었다** — 합쳐지는 상대
/// (`existing`)의 이력이 어디에도 안 실려서, **두 번째 이직부터 첫 이력이
/// 사라졌다.** 이력이 늘 한 벌만 남았다.
void main() {
  const line1 = '[이전 정보 · 2026-08-19] 옛회사 / 옛직함 / 010-1111-2222';
  const line2 = '[이전 정보 · 2026-05-02] 더옛회사 / 더옛직함';
  const user = '골프 좋아하심\n2026-03 세미나에서 만남';

  group('🚨 이력과 이용자 메모를 가른다', () {
    test('⭐ 이력만 골라낸다 — 원문 그대로', () {
      expect(
        CardHistoryNote.historyLines('$line1\n$line2\n$user'),
        '$line1\n$line2',
        reason: 'parse()는 머리표를 떼어 버려 원문 복원에 못 쓴다',
      );
    });

    test('⭐ 이용자 메모만 골라낸다', () {
      expect(CardHistoryNote.userMemo('$line1\n$line2\n$user'), user);
    });

    test('⭐ 갈랐다 다시 이으면 원래대로', () {
      const memo = '$line1\n$line2\n$user';
      expect(
        CardHistoryNote.join(
          history: CardHistoryNote.historyLines(memo),
          userMemo: CardHistoryNote.userMemo(memo),
        ),
        memo,
        reason: '이 왕복이 깨지면 저장할 때마다 메모가 조금씩 달라진다',
      );
    });
  });

  group('🚨 이력이 없는 명함은 지금과 똑같이 동작한다', () {
    test('⭐ 메모만 있는 명함', () {
      expect(CardHistoryNote.historyLines(user), '');
      expect(CardHistoryNote.userMemo(user), user);
      expect(CardHistoryNote.join(history: '', userMemo: user), user);
    });

    test('⭐ 메모가 아예 없는 명함 → null', () {
      expect(CardHistoryNote.historyLines(null), '');
      expect(CardHistoryNote.userMemo(null), '');
      expect(
        CardHistoryNote.join(history: '', userMemo: ''),
        isNull,
        reason: '빈 문자열이 아니라 null이어야 "메모 없음"으로 저장된다',
      );
    });
  });

  group('🚨 이력만 있고 메모가 빈 명함', () {
    test('⭐ 이력이 살아남는다', () {
      expect(CardHistoryNote.userMemo(line1), '');
      expect(
        CardHistoryNote.join(history: line1, userMemo: ''),
        line1,
        reason: '메모를 비워 저장해도 이력은 남아야 한다 — 이것이 원래 결함이다',
      );
    });

    test('⭐ 이용자가 메모를 통째로 지워도 이력은 남는다', () {
      const memo = '$line1\n$user';
      // 이용자가 메모 칸을 비우고 저장한 상황
      expect(
        CardHistoryNote.join(
          history: CardHistoryNote.historyLines(memo),
          userMemo: '',
        ),
        line1,
      );
    });
  });

  group('🚨 배선 — 화면이 실제로 부르는가', () {
    String code(String path) => File(path)
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    final edit = code(
      'lib/presentation/features/wallet/views/add_card_modal_view.dart',
    );

    test('⭐ 메모 칸에 이력을 안 띄운다', () {
      expect(
        edit.contains('CardHistoryNote.userMemo(c?.memo)'),
        isTrue,
        reason: '`c?.memo`를 그대로 띄우면 이용자가 이력 줄을 지울 수 있다 — '
            '그것이 원래 결함이다',
      );
    });

    test('⭐ 저장할 때 이력을 다시 붙인다', () {
      expect(
        edit.contains('CardHistoryNote.join(') &&
            edit.contains('history: _cardHistoryLines'),
        isTrue,
        reason: '안 붙이면 화면에서 뺀 이력이 저장에서 사라진다 — '
            '고치려다 더 나빠지는 자리다',
      );
    });

    test('🚨 합치기에서 상대의 이력도 잇는다', () {
      expect(
        edit.contains('CardHistoryNote.historyLines(existing.memo)'),
        isTrue,
        reason: '안 이으면 두 번째 이직부터 첫 이력이 사라진다 — '
            '이력이 늘 한 벌만 남는다',
      );
    });

    test('⭐ 「삭제」를 골라도 이용자 메모는 남긴다', () {
      expect(
        edit.contains('existingUserMemo'),
        isTrue,
        reason: '지우기로 한 것은 명함 정보이지 이용자가 쓴 메모가 아니다',
      );
    });
  });
}
