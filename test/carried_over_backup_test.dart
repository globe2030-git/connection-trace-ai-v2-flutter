/// 계정 전환에서 "유지"를 고른 명함은 **백업 대상이 아니다**(2026-08-28, 추가 555).
///
/// ## 무엇이 문제였나
///
/// 계정을 갈아탈 때 "유지"를 고르면 명함 본문은 새 계정 서버로 **일부러 올리지
/// 않는다** — 제3자 개인정보가 두 계정에 이중으로 존재하기 때문이다. 사진도
/// 같은 이유로 올리면 안 되고, 실제로 안 올라간다. **그런데 화면이 그 명함들을
/// 「백업됨」이라고 말하고 있었다** — 앞 계정의 장부가 같은 기기에 그대로
/// 남았기 때문이다(같은 contactId).
///
/// ✅ 실물로 확인한 것: 아이폰 장부 130장 · 새 계정 서버 0장이었고, 그 130은
/// **앞 계정 서버의 사진 수와 정확히 같았다.** 기기에 남은 계정 전환 이력도
/// `choice: keep` 두 건이었다.
///
/// ⚠️ **처음 낸 안(장부를 비워 다시 올린다)은 틀렸다.** 본문을 안 올리는
/// 자리에서 사진만 올리는 꼴이 되고, 암호화 키가 계정마다 달라 새 계정은
/// 그 파일을 열지도 못한다. 그래서 **올리는 쪽이 아니라 말하는 쪽을 고쳤다.**
///
/// 여기서 확인하는 것은 규칙까지다 — 화면에 실제로 그렇게 뜨는지는 실기기가
/// 봐야 한다.
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_photo_backfill.dart';
import 'package:flutter_test/flutter_test.dart';

CardPhotoBackupStateMap ledgerOf(Map<String, CardPhotoBackupState> states) {
  var map = const CardPhotoBackupStateMap({});
  states.forEach((id, state) => map = map.withState(id, state));
  return map;
}

void main() {
  group('소급 업로드 대상에서 빠진다', () {
    test('carriedOver 는 올리지 않는다', () {
      expect(
        selectCardPhotoBackfillTargets(
          localContactIds: const ['a', 'b'],
          ledger: ledgerOf({'a': CardPhotoBackupState.carriedOver}),
        ),
        ['b'],
      );
    });

    test('failed·quotaExceeded 는 여전히 다시 시도한다 — 이유가 다르다', () {
      expect(
        selectCardPhotoBackfillTargets(
          localContactIds: const ['a', 'b', 'c'],
          ledger: ledgerOf({
            'a': CardPhotoBackupState.failed,
            'b': CardPhotoBackupState.quotaExceeded,
            'c': CardPhotoBackupState.carriedOver,
          }),
        ),
        ['a', 'b'],
      );
    });
  });

  group('현황 집계', () {
    test('carriedOver 를 따로 센다 — synced 로 새지 않는다', () {
      final s = summarize(
        ledgerOf({
          'a': CardPhotoBackupState.carriedOver,
          'b': CardPhotoBackupState.carriedOver,
          'c': CardPhotoBackupState.synced,
        }),
        2000,
      );
      expect(s.carriedOver, 2);
      expect(s.synced, 1);
    });

    test('옮겨온 것이 있으면 알릴 것이 있다', () {
      final s = summarize(
        ledgerOf({'a': CardPhotoBackupState.carriedOver}),
        2000,
      );
      expect(s.needsAttention, isTrue);
    });

    test('한도 판정에 carriedOver 를 넣지 않는다 — 안 올라간 것이다', () {
      final s = summarize(
        ledgerOf({
          for (var i = 0; i < 10; i++) 'c$i': CardPhotoBackupState.carriedOver,
        }),
        10,
      );
      expect(s.isFull, isFalse);
      expect(s.remaining, 10);
    });
  });

  group('저장 값', () {
    test('상태 이름이 바뀌면 기기에 남은 기록을 못 읽는다 — 고정한다', () {
      expect(stateToName(CardPhotoBackupState.carriedOver), 'carried');
      expect(
        stateFromName('carried'),
        CardPhotoBackupState.carriedOver,
      );
    });

    test('덮어쓴다 — 앞 계정이 남긴 synced 를 고치는 것이 목적이다', () {
      var map = ledgerOf({'a': CardPhotoBackupState.synced});
      map = map.withState('a', CardPhotoBackupState.carriedOver);
      expect(map.stateOf('a'), CardPhotoBackupState.carriedOver);
      expect(map.syncedCount, 0);
    });
  });

  group('부르는 곳이 있나 — 규칙만 맞고 아무도 안 부르면 소용이 없다', () {
    test('계정 전환에서 "유지" 갈래가 표시를 고친다', () {
      final src = File('lib/presentation/common/auth_gate.dart')
          .readAsStringSync();
      expect(
        src.contains('markCarriedOverAll'),
        isTrue,
        reason: '"유지"를 골랐을 때 장부를 사실에 맞게 적어야 한다',
      );
    });

    test('서버를 부르지 않는다 — 이 수정은 말하는 쪽만 고친다', () {
      final src = File(
        'lib/core/services/card_photo_backup_state.dart',
      ).readAsStringSync();
      final body = src.substring(src.indexOf('markCarriedOverAll'));
      final fn = body.substring(0, body.indexOf('\n  Future<void> forget'));
      expect(fn.contains('upload'), isFalse);
      expect(fn.contains('CardPhotoBackupService'), isFalse);
    });

    test('설정 화면이 옮겨온 장수를 말한다', () {
      final src = File(
        'lib/presentation/features/settings/views/settings_view.dart',
      ).readAsStringSync();
      expect(src.contains('다른 계정에서 옮겨온'), isTrue);
      expect(src.contains('백업되지 않습니다'), isTrue);
    });
  });
}
