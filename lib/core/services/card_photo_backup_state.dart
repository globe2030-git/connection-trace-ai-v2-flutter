import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 명함 사진이 **서버에 올라갔는지**를 명함별로 기록한다(2026-08-16).
///
/// ## 왜 필요한가 — 안내를 하려면 먼저 알아야 한다
///
/// 사진 백업은 **조용히 실패할 수 있는 경로가 셋**이다.
///
/// | 왜 안 올라가나 | 사용자가 아는가 |
/// |---|---|
/// | 백업 기능을 켜기 전에 등록했다 | ❌ |
/// | 한도(2,000장)를 넘었다 | ❌ |
/// | **업로드가 실패했다**(네트워크 끊김 등) | ❌ |
///
/// 셋 다 지금은 **아무도 모른다.** 업로드가 fire-and-forget이고 실패를 삼키기
/// 때문이다(`ContactImageService`). 그래서 **기기를 바꾼 뒤에야** 사진이
/// 없다는 것을 알게 된다 — 이 기능을 만든 이유가 정확히 그 상황을 없애는
/// 것이었는데 말이다.
///
/// ⚠️ 이 저장소가 반복해 다친 유형이다: **"의도한 실패도 사용자 눈에는
/// 결함이다"**(HANDOFF 0-21).
///
/// ## 무엇을 저장하나 — **`contactId`와 상태뿐**
///
/// 이름·전화번호 같은 값은 **넣지 않는다.** `contactId`는 앱이 만든 식별자라
/// 그 자체로 개인정보가 아니므로, 암호화되지 않는 `shared_preferences`에
/// 두어도 CLAUDE.md 개인정보 원칙에 걸리지 않는다.
///
/// ## 왜 기기 로컬인가
///
/// **"이 기기가 올렸나"**를 묻는 것이라 기기별로 답하면 된다. 서버에 무엇이
/// 있는지는 복원 시점에 **목록을 대조**하면 알 수 있으므로, 여기 기록을 서버로
/// 동기화할 이유가 없다. 동기화하면 `toBackupJson` 구조가 바뀌어 **전체
/// 테스트 등급**이 되는데(F-10 전례), 얻는 것이 없다.
enum CardPhotoBackupState {
  /// 서버에 올라갔다.
  synced,

  /// 한도를 넘어 **올리지 않았다**. 실패가 아니라 정책이다.
  quotaExceeded,

  /// 올리려다 **실패했다**(네트워크 등). 나중에 다시 시도할 수 있다.
  failed,

  /// **다른 계정에서 이 기기에 남아 있던 명함**이라 이 계정으로는 올리지
  /// 않는다(2026-08-28, 추가 555).
  ///
  /// 계정을 갈아탈 때 "유지"를 고르면 명함 본문은 새 계정 서버로 **일부러
  /// 올리지 않는다**([mayMigrateToServer]) — 제3자 개인정보가 두 계정에
  /// 이중으로 존재하기 때문이다. 사진도 같은 이유로 올리면 안 된다.
  ///
  /// ⚠️ **그런데 화면은 그 명함들을 「백업됨」이라고 말하고 있었다.** 앞
  /// 계정의 장부가 그대로 남았기 때문이다(같은 기기, 같은 contactId).
  /// 실제로는 새 계정 서버에 한 장도 없다 — **기기를 잃으면 못 되살린다.**
  ///
  /// 📌 그래서 **올리는 쪽이 아니라 말하는 쪽을 고쳤다.** 이 상태는
  /// "실패"가 아니라 "대상이 아님"이다. 다시 시도하지 않는다.
  carriedOver,
}

/// 보관본이 **실제로 축소됐는지**와 그 크기 구간(2026-08-16).
///
/// ## 왜 이것까지 남기나
///
/// `downscaleForArchive`는 **긴 변이 1,600을 "넘을 때만"** 줄인다. 작은 사진을
/// 다시 구우면 화질만 깎이므로 맞는 설계인데, **정확히 1,600이거나 그 아래면
/// 원본이 그대로 올라간다.** 그 원본은 `encodeJpg(quality: 100)`이라
/// **계획값(0.3MB)의 3배 이상**이다.
///
/// ⚠️ **화면비·화소가 다른 기기에서 크롭 긴 변이 1,600 근처로 내려가면 그
/// 기기 사용자만 조용히 축소를 안 받는다.** 실패도 안 나고 로그도 없어
/// **아무도 모른다** — 이 저장소가 반복해 다친 유형이다.
///
/// 손익/원가 세션이 실제 함수를 표본 103장에 돌려 찾았다(평균 264KB).
///
/// ⚠️ 개인정보가 아니다 — **불리언과 크기 구간뿐**이고 사진 내용과 무관하다.
enum CardPhotoSizeBand {
  /// 축소를 거쳤고 결과가 계획값 안(≤ 400KB).
  downscaledSmall,

  /// 축소를 거쳤는데 결과가 크다(> 400KB). 표본 P90이 371KB이므로 드물어야 한다.
  downscaledLarge,

  /// **축소를 건너뛰었다** — 긴 변이 1,600 이하였다. 위 경고에 해당한다.
  notDownscaled,
}

/// 바이트 수와 축소 여부로 구간을 정한다.
CardPhotoSizeBand sizeBandOf({required bool downscaled, required int bytes}) {
  if (!downscaled) return CardPhotoSizeBand.notDownscaled;
  return bytes <= 400 * 1024
      ? CardPhotoSizeBand.downscaledSmall
      : CardPhotoSizeBand.downscaledLarge;
}

/// 저장 값 ↔ 이름. `enum.name`을 그대로 쓰면 이름을 바꿀 때 저장된 값이
/// 깨지므로 문자열을 고정한다.
const Map<CardPhotoBackupState, String> _stateNames = {
  CardPhotoBackupState.synced: 'synced',
  CardPhotoBackupState.quotaExceeded: 'quota',
  CardPhotoBackupState.failed: 'failed',
  CardPhotoBackupState.carriedOver: 'carried',
};

CardPhotoBackupState? stateFromName(String? raw) {
  for (final e in _stateNames.entries) {
    if (e.value == raw) return e.key;
  }
  return null;
}

String stateToName(CardPhotoBackupState s) => _stateNames[s]!;

/// 상태 지도를 읽고 쓰는 순수 계산. 저장소(prefs) 없이 검사할 수 있게 뺐다.
class CardPhotoBackupStateMap {
  const CardPhotoBackupStateMap(this._raw);

  factory CardPhotoBackupStateMap.decode(String? json) {
    if (json == null || json.isEmpty) return const CardPhotoBackupStateMap({});
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const CardPhotoBackupStateMap({});
      return CardPhotoBackupStateMap({
        for (final e in decoded.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      });
    } catch (_) {
      // 깨진 값이면 빈 상태로 시작한다 — 백업 상태는 편의 정보라
      // 못 읽는다고 저장을 막을 이유가 없다.
      return const CardPhotoBackupStateMap({});
    }
  }

  final Map<String, String> _raw;

  /// 기록이 없으면 `null`. **"모른다"와 "안 올라갔다"는 다르다** —
  /// 백업 기능을 켜기 전에 등록한 명함이 여기 해당한다.
  CardPhotoBackupState? stateOf(String contactId) =>
      stateFromName(_raw[contactId]);

  CardPhotoBackupStateMap withState(
    String contactId,
    CardPhotoBackupState state,
  ) =>
      CardPhotoBackupStateMap({..._raw, contactId: stateToName(state)});

  /// 명함을 지우면 기록도 지운다. 남겨 두면 같은 id가 재사용될 때
  /// 엉뚱한 상태가 따라붙는다.
  CardPhotoBackupStateMap without(String contactId) =>
      CardPhotoBackupStateMap({..._raw}..remove(contactId));

  /// 서버에 올라간 것으로 기록된 명함 수. 한도 판정의 재료다.
  int get syncedCount =>
      _raw.values.where((v) => v == _stateNames[CardPhotoBackupState.synced]).length;

  Map<String, String> get raw => Map.unmodifiable(_raw);

  String encode() => jsonEncode(_raw);
}

/// 기기에 상태를 보관한다.
class CardPhotoBackupStateService {
  static const String _prefsKey = 'card_photo_backup_state_v1';

  Future<CardPhotoBackupStateMap> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return CardPhotoBackupStateMap.decode(prefs.getString(_prefsKey));
    } catch (e) {
      debugPrint('사진 백업 상태 읽기 실패: ${e.runtimeType}');
      return const CardPhotoBackupStateMap({});
    }
  }

  Future<void> _save(CardPhotoBackupStateMap map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, map.encode());
    } catch (e) {
      debugPrint('사진 백업 상태 쓰기 실패: ${e.runtimeType}');
    }
  }

  Future<void> record(String contactId, CardPhotoBackupState state) async =>
      _save((await load()).withState(contactId, state));

  /// 서버 실물에서 알아낸 것들을 `synced`로 한꺼번에 적는다(2026-08-16,
  /// 추가 256).
  ///
  /// 재설치하면 이 저장소가 통째로 비어 한도 카운터가 0이 된다. 서버에는
  /// 사진이 그대로 있으므로 **한도를 또 처음부터 채울 수 있다** — 한도가
  /// 천장 구실을 못 하게 된다.
  ///
  /// ⚠️ **덮어쓰지 않고 덧붙인다.** 기존 기록이 있으면 그쪽이 더 자세하다
  /// (`failed`·`quota` 같은 사유까지 들어 있다). 여기서 지우면 그 사유가
  /// 사라진다.
  Future<void> markSyncedAll(Iterable<String> contactIds) async {
    final ids = contactIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    var map = await load();
    for (final id in ids) {
      map = map.withState(id, CardPhotoBackupState.synced);
    }
    await _save(map);
  }

  /// 계정 전환에서 "유지"를 고른 명함들을 **백업 대상 아님**으로 적는다
  /// (2026-08-28, 추가 555).
  ///
  /// ⚠️ [markSyncedAll]과 달리 **덮어쓴다.** 여기서 고치려는 것이 바로
  /// 앞 계정이 남긴 `synced` 기록이기 때문이다 — 덧붙이기만 하면 그 거짓말이
  /// 그대로 남는다.
  ///
  /// 서버를 부르지 않는다. 이 함수가 하는 일은 **장부가 사실을 말하게 하는
  /// 것**뿐이고, 사진을 옮기지도 지우지도 않는다.
  Future<void> markCarriedOverAll(Iterable<String> contactIds) async {
    final ids = contactIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    var map = await load();
    for (final id in ids) {
      map = map.withState(id, CardPhotoBackupState.carriedOver);
    }
    await _save(map);
  }

  /// 「넘어온 것」 표시가 하나라도 있나(추가 562).
  ///
  /// 🚨 소급 표시가 **돌아야 하는지 판단하는 데 쓴다.** 본문 장부만 보고
  /// 판단하면, **본문은 이미 표시됐고 사진은 아직인 기기**에서 영영 안 돈다 —
  /// 실제로 그 상태의 기기가 둘 있었다(추가 561을 넣은 직후).
  Future<bool> hasCarriedOver() async {
    final map = await load();
    return map.raw.values.contains(stateToName(CardPhotoBackupState.carriedOver));
  }

  /// 대조 결과로 장부를 **통째로 갈아 끼운다**(추가 558).
  ///
  /// ⚠️ [markSyncedAll]처럼 덧붙이지 않는다 — 대조의 요점이 **틀린 기록을
  /// 지우는 것**이라, 덧붙이기만 하면 아무것도 못 고친다.
  Future<void> replaceAll(CardPhotoBackupStateMap map) async => _save(map);

  Future<void> forget(String contactId) async =>
      _save((await load()).without(contactId));

  /// 계정을 갈아탈 때 비운다. 앞 사람의 백업 상태가 뒷사람 화면에 뜨면 안 된다.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('사진 백업 상태 삭제 실패: ${e.runtimeType}');
    }
  }
}

/// 백업 현황 한 묶음 — **안내와 관측이 같은 재료를 쓴다**(2026-08-16).
///
/// ## 왜 하나로 묶나
///
/// 사용자에게 보여줄 것("2,000장 중 160장 백업됨")과 우리가 알아야 할 것
/// ("한도에 닿은 사람이 있나")이 **같은 숫자**다. 따로 만들면 어긋난다.
///
/// ⚠️ **관측이 없으면 "낮게 시작해 나중에 올린다"가 성립하지 않는다.** 올릴
/// 시점을 알 수단이 없기 때문이다(손익/원가 세션 조건 ①). 지금은 **기기 안에서만**
/// 센다 — 서버로 집계를 보내려면 방침을 먼저 봐야 한다(오늘 "AI 이용 일별 집계"를
/// 뺀 것과 같은 구조: **하지도 않는 처리를 고지하지 않듯, 고지 없이 집계를
/// 보내지도 않는다**).
class CardPhotoBackupSummary {
  const CardPhotoBackupSummary({
    required this.synced,
    required this.quotaExceeded,
    required this.failed,
    required this.quota,
    this.carriedOver = 0,
  });

  /// 서버에 올라간 장수.
  final int synced;

  /// 한도를 넘어 **올리지 않은** 장수. 실패가 아니라 정책이다.
  final int quotaExceeded;

  /// 올리려다 **실패한** 장수. 다시 시도할 수 있다.
  final int failed;

  /// 다른 계정에서 옮겨와 **올리지 않는** 장수(추가 555).
  final int carriedOver;

  /// 이 이용자의 한도(서버 값 또는 기본값).
  final int quota;

  /// 남은 장수.
  int get remaining => quota - synced < 0 ? 0 : quota - synced;

  /// **한도에 닿았나.** 닿으면 새 사진이 안 올라간다.
  bool get isFull => synced >= quota;

  /// **미리 알려야 하는 구간인가**(80% 이상, 아직 한도 안).
  ///
  /// ⚠️ 한도에 닿은 뒤에는 false다 — **"곧 찹니다"와 "찼습니다"는 다른 안내**다.
  bool get isNearFull => !isFull && synced >= (quota * 0.8).floor();

  /// 사용자에게 알릴 것이 있나(경고 구간이거나, 안 올라간 것이 있거나).
  bool get needsAttention =>
      isNearFull || isFull || quotaExceeded > 0 || failed > 0 || carriedOver > 0;
}

/// **서버 실물과 장부를 맞춘다**(2026-08-28, 추가 558).
///
/// ## 왜 필요한가 — 장부가 사실인지 아무도 확인하지 않았다
///
/// 이 장부는 *"내가 올렸다고 생각한 것"*이지 *"서버에 있는 것"*이 아니다. 둘이
/// 갈라져도 **대조하는 코드가 없었다.**
///
/// ✅ **실물**: 폴드는 장부가 `104장 백업됨`인데 서버에는 **0장**이었고,
/// 아이폰은 `130장`인데 그 130은 **앞 계정 서버의 사진 수**였다. 화면이 두
/// 숫자를 나란히 띄우기 시작하고 나서야 드러났다(추가 551) — 그런데 화면은
/// *"어긋납니다"*라고 **말할 뿐 바로잡지는 못한다.** 그 자리를 메운다.
///
/// ## 규칙
///
/// ```
/// 서버에 있음                     → synced      (사유가 무엇이든 실물이 이긴다)
/// 서버에 없음 + carriedOver       → 그대로      (🚨 올리면 안 되는 것이다)
/// 서버에 없음 + synced            → 기록을 지운다 ("모른다" = 다시 시도 대상)
/// 서버에 없음 + failed·quota      → 그대로      (사유 쪽이 더 자세하다)
/// ```
///
/// 🚨 **`carriedOver`를 건드리면 안 되는 이유**: 그 명함들은 **서버에 없는 것이
/// 정상**이다(다른 계정에서 넘어와 올리지 않기로 한 것). 여기서 기록을 지우면
/// 소급 업로드가 **제3자 개인정보를 남의 계정 서버로 올린다** — 대조가 오히려
/// 사고를 만드는 방향이다.
///
/// ⚠️ **서버 목록을 못 읽었을 때는 절대 부르지 말 것.** "못 읽었다"와 "없다"를
/// 섞으면 장부가 통째로 지워지고, 한도 천장이 사라진다.
CardPhotoBackupStateMap reconcileWithServer(
  CardPhotoBackupStateMap ledger,
  Set<String> onServer,
) {
  final next = <String, String>{};
  ledger.raw.forEach((id, raw) {
    final state = stateFromName(raw);
    if (onServer.contains(id)) {
      next[id] = stateToName(CardPhotoBackupState.synced);
      return;
    }
    if (state == CardPhotoBackupState.synced) return; // 기록을 지운다
    next[id] = raw;
  });
  // 장부에 없는데 서버에 있는 것 — 재설치로 장부가 비었을 때가 여기다.
  for (final id in onServer) {
    next[id] = stateToName(CardPhotoBackupState.synced);
  }
  return CardPhotoBackupStateMap(next);
}

/// 상태 지도와 한도로 현황을 만든다.
CardPhotoBackupSummary summarize(CardPhotoBackupStateMap map, int quota) {
  var synced = 0, quotaExceeded = 0, failed = 0, carriedOver = 0;
  for (final raw in map.raw.values) {
    switch (stateFromName(raw)) {
      case CardPhotoBackupState.synced:
        synced++;
      case CardPhotoBackupState.quotaExceeded:
        quotaExceeded++;
      case CardPhotoBackupState.failed:
        failed++;
      case CardPhotoBackupState.carriedOver:
        carriedOver++;
      case null:
        break;
    }
  }
  return CardPhotoBackupSummary(
    synced: synced,
    quotaExceeded: quotaExceeded,
    failed: failed,
    carriedOver: carriedOver,
    quota: quota,
  );
}
