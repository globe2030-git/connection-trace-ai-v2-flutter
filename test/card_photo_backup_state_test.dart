// 명함 사진 백업 상태 검사(2026-08-16).
//
// 무엇을 지키려는 검사인가: **"모른다"와 "안 올라갔다"를 구분하는 것.**
// 백업 기능을 켜기 전에 등록한 명함은 기록이 없고(= 모른다), 한도를 넘거나
// 업로드가 실패한 것은 기록이 있다(= 안 올라갔다, 이유도 안다). 이 구분이
// 무너지면 사용자에게 잘못된 안내를 하게 된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';

void main() {
  group('상태 지도 — 읽고 쓰기', () {
    test('기록이 없으면 null — "모른다"와 "안 올라갔다"는 다르다', () {
      const map = CardPhotoBackupStateMap({});
      expect(map.stateOf('c1'), isNull);
    });

    test('기록하면 그대로 읽힌다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('c1', CardPhotoBackupState.synced)
          .withState('c2', CardPhotoBackupState.quotaExceeded)
          .withState('c3', CardPhotoBackupState.failed);
      expect(map.stateOf('c1'), CardPhotoBackupState.synced);
      expect(map.stateOf('c2'), CardPhotoBackupState.quotaExceeded);
      expect(map.stateOf('c3'), CardPhotoBackupState.failed);
    });

    test('덮어쓰면 마지막 값이 남는다 — 실패 후 성공하면 성공이다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('c1', CardPhotoBackupState.failed)
          .withState('c1', CardPhotoBackupState.synced);
      expect(map.stateOf('c1'), CardPhotoBackupState.synced);
    });

    test('명함을 지우면 기록도 지운다 — 같은 id 재사용 시 오염 방지', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('c1', CardPhotoBackupState.synced)
          .without('c1');
      expect(map.stateOf('c1'), isNull);
    });
  });

  group('syncedCount — 한도 판정의 재료', () {
    test('올라간 것만 센다. 실패·한도초과는 안 센다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('a', CardPhotoBackupState.synced)
          .withState('b', CardPhotoBackupState.synced)
          .withState('c', CardPhotoBackupState.failed)
          .withState('d', CardPhotoBackupState.quotaExceeded);
      expect(map.syncedCount, 2);
    });
  });

  group('저장 형식', () {
    test('encode → decode 하면 그대로 돌아온다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('c1', CardPhotoBackupState.synced)
          .withState('c2', CardPhotoBackupState.failed);
      final back = CardPhotoBackupStateMap.decode(map.encode());
      expect(back.stateOf('c1'), CardPhotoBackupState.synced);
      expect(back.stateOf('c2'), CardPhotoBackupState.failed);
    });

    test('깨진 값이면 빈 상태로 시작한다 — 저장을 막지 않는다', () {
      expect(CardPhotoBackupStateMap.decode('{깨짐').raw, isEmpty);
      expect(CardPhotoBackupStateMap.decode('[1,2,3]').raw, isEmpty);
      expect(CardPhotoBackupStateMap.decode(null).raw, isEmpty);
      expect(CardPhotoBackupStateMap.decode('').raw, isEmpty);
    });

    test('저장 이름이 고정돼 있다 — enum 이름을 바꿔도 저장값은 안 깨진다', () {
      // 이 값이 바뀌면 이미 기기에 저장된 상태를 못 읽는다.
      expect(stateToName(CardPhotoBackupState.synced), 'synced');
      expect(stateToName(CardPhotoBackupState.quotaExceeded), 'quota');
      expect(stateToName(CardPhotoBackupState.failed), 'failed');
      expect(stateFromName('synced'), CardPhotoBackupState.synced);
      expect(stateFromName('없는값'), isNull);
    });
  });

  _summaryTests();

  group('⚠️ 개인정보 — contactId와 상태만 저장한다', () {
    test('저장 문자열에 이름·전화·이메일이 들어갈 자리가 없다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('contact-123', CardPhotoBackupState.synced);
      final encoded = map.encode();
      // 키는 contactId, 값은 고정된 상태 이름뿐이다.
      expect(encoded, '{"contact-123":"synced"}');
    });
  });
}

// 백업 현황 요약 — 안내와 관측이 같은 재료를 쓴다(2026-08-16).
//
// ⚠️ 관측이 없으면 "낮게 시작해 나중에 올린다"는 전략이 성립하지 않는다.
// 올릴 시점을 알 수단이 없기 때문이다.
void _summaryTests() {
  group('summarize — 상태별로 센다', () {
    test('올라간 것·한도 초과·실패를 각각 센다', () {
      final map = const CardPhotoBackupStateMap({})
          .withState('a', CardPhotoBackupState.synced)
          .withState('b', CardPhotoBackupState.synced)
          .withState('c', CardPhotoBackupState.quotaExceeded)
          .withState('d', CardPhotoBackupState.failed);
      final s = summarize(map, 200);
      expect(s.synced, 2);
      expect(s.quotaExceeded, 1);
      expect(s.failed, 1);
      expect(s.remaining, 198);
    });
  });

  group('⚠️ "곧 찹니다"와 "찼습니다"는 다른 안내다', () {
    CardPhotoBackupSummary at(int synced) => CardPhotoBackupSummary(
      synced: synced, quotaExceeded: 0, failed: 0, quota: 200,
    );

    test('159장까지는 조용하다', () {
      expect(at(159).isNearFull, isFalse);
      expect(at(159).isFull, isFalse);
      expect(at(159).needsAttention, isFalse);
    });

    test('160장(80%)부터 미리 알린다', () {
      expect(at(160).isNearFull, isTrue);
      expect(at(160).isFull, isFalse);
    });

    test('200장이면 "찼다" — "곧 찹니다"가 아니다', () {
      expect(at(200).isFull, isTrue);
      expect(at(200).isNearFull, isFalse);
      expect(at(200).remaining, 0);
    });
  });

  group('needsAttention — 조용히 넘어가면 안 되는 경우', () {
    test('한도를 넘어 못 올린 것이 있으면 알린다', () {
      const s = CardPhotoBackupSummary(
        synced: 10, quotaExceeded: 3, failed: 0, quota: 200,
      );
      expect(s.needsAttention, isTrue);
    });

    test('업로드가 실패한 것이 있으면 알린다', () {
      const s = CardPhotoBackupSummary(
        synced: 10, quotaExceeded: 0, failed: 1, quota: 200,
      );
      expect(s.needsAttention, isTrue);
    });

    test('전부 정상이고 여유가 있으면 조용하다', () {
      const s = CardPhotoBackupSummary(
        synced: 10, quotaExceeded: 0, failed: 0, quota: 200,
      );
      expect(s.needsAttention, isFalse);
    });
  });
}
