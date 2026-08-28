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
/// 장부에 carriedOver     건너뛴다 — 다른 계정에서 남은 명함이라 **올리면 안 된다**
/// ```
///
/// 🚨 **`carriedOver`를 건너뛰는 것은 `synced`를 건너뛰는 것과 이유가 다르다**
/// (2026-08-28, 추가 555). `synced`는 *"이미 있으니 또 올릴 필요가 없다"*이고,
/// `carriedOver`는 *"올리면 제3자 개인정보가 두 계정에 이중으로 존재한다"*이다.
/// 앞의 것은 효율이고 뒤의 것은 **하면 안 되는 일**이다 — 나중에 "이미 있는 것도
/// 다시 올려 보자"는 최적화를 넣더라도 이쪽은 따라 풀지 말 것.
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
      .where(
        (id) =>
            ledger.stateOf(id) != CardPhotoBackupState.synced &&
            ledger.stateOf(id) != CardPhotoBackupState.carriedOver,
      )
      .toList();
  targets.sort();
  return targets;
}
