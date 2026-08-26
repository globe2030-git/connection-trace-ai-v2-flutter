/// "기기에 있는 명함 사진 중 **무엇을 서버로 올려야 하는가**" 판정(추가 508).
///
/// ## 왜 이것이 따로 있나
///
/// 소급 업로드 자체는 파일을 읽고 네트워크를 타는 일이라 자동 테스트로
/// 확인하기 어렵다. 그런데 **무엇을 고르는가**는 순수한 규칙이고, 틀리면
/// 조용히 틀린다 — 빠뜨리면 사진이 안 올라가고, 넘치면 이미 올라간 것을
/// 다시 올린다. 둘 다 화면에 아무 표시가 없다.
///
/// 그래서 규칙만 여기로 뺀다. `card_form_validation.dart`·`call_target.dart`와
/// 같은 이유다.
library;

import '../services/card_photo_backup_state.dart';

/// 올려야 할 명함 id를 고른다.
///
/// ## 규칙
///
/// ```
/// 장부에 synced          건너뛴다 — 이미 올라갔다
/// 장부에 failed          올린다 — 지난번에 실패했으니 다시 해 본다
/// 장부에 quotaExceeded   올린다 — 한도가 올랐거나 다른 사진이 지워졌을 수 있다
///                        (실제 한도 판정은 올리는 쪽이 다시 한다)
/// 장부에 없음            올린다 — 백업을 켜기 전에 등록한 명함이 여기 해당한다
/// ```
///
/// 📌 **`quotaExceeded`를 다시 시도하는 것이 요점이다.** 한도는 서버 값이라
/// 바뀔 수 있는데, 한 번 막혔다고 영영 빼면 한도가 올라도 그 사진들은
/// 영영 안 올라간다. 다시 넣어도 올리는 쪽이 한도를 확인하므로 넘치지 않는다.
///
/// 결과는 **정렬해서 돌려준다.** 중간에 끊겨도 다음 실행이 같은 순서로 집어
/// 어디까지 됐는지가 예측 가능해진다 — 파일 시스템이 주는 순서는 보장이 없다.
List<String> selectCardPhotoBackfillTargets({
  required Iterable<String> localContactIds,
  required CardPhotoBackupStateMap ledger,
}) {
  final targets = localContactIds
      .where((id) => id.trim().isNotEmpty)
      .toSet()
      .where((id) => ledger.stateOf(id) != CardPhotoBackupState.synced)
      .toList();
  targets.sort();
  return targets;
}
