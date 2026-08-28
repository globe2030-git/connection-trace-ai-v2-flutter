/// **장부와 서버 실물을 맞춘다**(2026-08-28, 추가 558).
///
/// ## 무엇이 문제였나 — 장부가 사실인지 아무도 확인하지 않았다
///
/// 이 장부는 *"내가 올렸다고 생각한 것"*이지 *"서버에 있는 것"*이 아니다. 둘이
/// 갈라져도 **대조하는 코드가 없었다.**
///
/// ✅ **실물**: 폴드는 장부 `104장 백업됨` · 서버 **0장**. 아이폰은 `130장`인데
/// 그 130은 **앞 계정 서버의 사진 수**였다. 화면이 두 숫자를 나란히 띄우고
/// 나서야 드러났다(추가 551) — 그런데 화면은 *"어긋납니다"*라고 **말할 뿐
/// 바로잡지 못한다.**
///
/// 🚨 **되살리는 코드는 있었지만 「장부가 비었을 때만」 돌았다.** 그래서
/// **틀린 채로 차 있으면 영영 안 고쳐졌다** — 두 기기가 정확히 그 상태였다.
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';
import 'package:flutter_test/flutter_test.dart';

CardPhotoBackupStateMap ledgerOf(Map<String, CardPhotoBackupState> s) {
  var m = const CardPhotoBackupStateMap({});
  s.forEach((id, st) => m = m.withState(id, st));
  return m;
}

void main() {
  group('실물이 이긴다', () {
    test('⭐ 장부는 백업됐다는데 서버에 없으면 기록을 지운다 — 폴드가 이 경우였다', () {
      final out = reconcileWithServer(
        ledgerOf({'a': CardPhotoBackupState.synced}),
        <String>{},
      );
      expect(out.stateOf('a'), isNull, reason: '"모른다"가 되어 다시 시도된다');
      expect(out.syncedCount, 0);
    });

    test('서버에 있으면 사유가 무엇이든 synced 로 바로잡는다', () {
      final out = reconcileWithServer(
        ledgerOf({
          'a': CardPhotoBackupState.failed,
          'b': CardPhotoBackupState.quotaExceeded,
        }),
        {'a', 'b'},
      );
      expect(out.stateOf('a'), CardPhotoBackupState.synced);
      expect(out.stateOf('b'), CardPhotoBackupState.synced);
    });

    test('장부에 없는데 서버에 있으면 넣는다 — 재설치 뒤 한도 천장이 이걸로 선다', () {
      final out = reconcileWithServer(const CardPhotoBackupStateMap({}), {'a'});
      expect(out.stateOf('a'), CardPhotoBackupState.synced);
    });
  });

  group('🚨 건드리면 안 되는 것', () {
    test('carriedOver 는 서버에 없어도 그대로 둔다 — 지우면 남의 계정으로 올라간다', () {
      final out = reconcileWithServer(
        ledgerOf({'a': CardPhotoBackupState.carriedOver}),
        <String>{},
      );
      expect(out.stateOf('a'), CardPhotoBackupState.carriedOver);
    });

    test('failed·quotaExceeded 는 사유를 지키다 — 그쪽이 더 자세하다', () {
      final out = reconcileWithServer(
        ledgerOf({
          'a': CardPhotoBackupState.failed,
          'b': CardPhotoBackupState.quotaExceeded,
        }),
        <String>{},
      );
      expect(out.stateOf('a'), CardPhotoBackupState.failed);
      expect(out.stateOf('b'), CardPhotoBackupState.quotaExceeded);
    });
  });

  group('섞여 있을 때', () {
    test('폴드+아이폰 모양 — 앞 계정 기록만 걷히고 나머지는 남는다', () {
      final out = reconcileWithServer(
        ledgerOf({
          'carried1': CardPhotoBackupState.carriedOver,
          'stale1': CardPhotoBackupState.synced,
          'stale2': CardPhotoBackupState.synced,
          'real': CardPhotoBackupState.synced,
          'retry': CardPhotoBackupState.failed,
        }),
        {'real'},
      );
      expect(out.raw.keys.toSet(), {'carried1', 'real', 'retry'});
      expect(out.syncedCount, 1);
    });
  });

  group('부르는 곳 — 규칙만 맞고 안 부르면 소용이 없다', () {
    final src = File(
      'lib/core/services/contact_image_service.dart',
    ).readAsStringSync();

    test('🚨 「장부가 비었을 때만」 돌던 이른 반환이 사라졌다', () {
      expect(
        src.contains("if ((await _backupState.load()).raw.isNotEmpty) return;"),
        isFalse,
        reason: '이 줄 때문에 틀린 채로 차 있는 장부가 영영 안 고쳐졌다',
      );
    });

    test('대조를 부르고, 결과로 장부를 갈아 끼운다', () {
      expect(src.contains('reconcileWithServer'), isTrue);
      expect(src.contains('replaceAll'), isTrue);
    });

    test('⚠️ 서버 목록을 못 읽으면(null) 아무것도 하지 않는다', () {
      expect(src.contains('if (onServer == null) return;'), isTrue);
    });

    test('이름이 하는 일과 맞는다 — 옛 이름은 「비었을 때만」을 뜻했다', () {
      expect(src.contains('_restoreBackupStateIfEmpty'), isFalse);
      expect(src.contains('_reconcileBackupStateWithServer'), isTrue);
    });
  });
}
