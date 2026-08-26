/// 소급 업로드 대상 선정 규칙(추가 508).
///
/// ⚠️ 여기서 확인하는 것은 **무엇을 고르는가**까지다. 실제로 올라갔는지는
/// Cloud Storage를 열어 세야 한다 — "올린다고 코드에 썼다"와 "올라갔다"는
/// 다르고, 이 저장소는 오늘 그 자리에서 구멍을 찾았다(백업을 부르고 있는데
/// 사진은 안 보고 있었다).
library;

import 'package:connection_trace_ai_flutter/core/services/card_photo_backup_state.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_photo_backfill.dart';
import 'package:flutter_test/flutter_test.dart';

CardPhotoBackupStateMap ledgerOf(Map<String, CardPhotoBackupState> states) {
  var map = const CardPhotoBackupStateMap({});
  states.forEach((id, state) {
    map = map.withState(id, state);
  });
  return map;
}

List<String> pick(
  List<String> local, [
  Map<String, CardPhotoBackupState> states = const {},
]) => selectCardPhotoBackfillTargets(
  localContactIds: local,
  ledger: ledgerOf(states),
);

void main() {
  test('장부가 비었으면 기기에 있는 것을 전부 올린다', () {
    // 백업을 켜기 전에 등록한 명함이 정확히 이 상태다 — 파일은 있는데
    // 장부에는 아무 기록이 없다.
    expect(pick(['a', 'b', 'c']), ['a', 'b', 'c']);
  });

  test('이미 올라간 것은 건너뛴다', () {
    expect(
      pick(['a', 'b'], {'a': CardPhotoBackupState.synced}),
      ['b'],
    );
  });

  test('지난번에 실패한 것은 다시 시도한다', () {
    expect(pick(['a'], {'a': CardPhotoBackupState.failed}), ['a']);
  });

  // 📌 한도는 서버 값이라 바뀐다(2026-08-26에 실제로 200 → 2,000이 됐다).
  // 한 번 막혔다고 영영 빼면 한도가 올라도 그 사진들은 영영 안 올라간다.
  test('한도에 막혔던 것도 다시 넣는다 — 한도는 올라갈 수 있다', () {
    expect(pick(['a'], {'a': CardPhotoBackupState.quotaExceeded}), ['a']);
  });

  test('기기에 파일이 없으면 장부에 뭐가 있든 대상이 아니다', () {
    expect(pick([], {'a': CardPhotoBackupState.failed}), isEmpty);
  });

  test('전부 올라가 있으면 아무것도 안 고른다', () {
    expect(
      pick(['a', 'b'], {
        'a': CardPhotoBackupState.synced,
        'b': CardPhotoBackupState.synced,
      }),
      isEmpty,
    );
  });

  // 중간에 끊겨도 다음 실행이 같은 순서로 집어야 어디까지 됐는지 예측된다.
  // 파일 시스템이 주는 순서는 보장이 없다.
  test('결과는 항상 같은 순서다', () {
    expect(pick(['c', 'a', 'b']), ['a', 'b', 'c']);
    expect(pick(['b', 'c', 'a']), ['a', 'b', 'c']);
  });

  test('같은 id가 두 번 와도 한 번만 올린다', () {
    expect(pick(['a', 'a', 'b']), ['a', 'b']);
  });

  test('빈 id·공백 id는 버린다', () {
    expect(pick(['', '   ', 'a']), ['a']);
  });

  // 내 명함 사진도 같은 경로로 보관한다(예약 id는 밑줄로 시작).
  // 규칙이 두 벌이 되면 서버 백업에서 한쪽이 빠진다.
  test('내 명함 예약 id도 똑같이 대상이 된다', () {
    expect(pick(['_my_profile', 'a']), ['_my_profile', 'a']);
  });
}
