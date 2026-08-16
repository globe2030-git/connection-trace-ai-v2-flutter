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
/// | 한도(무료 300·충전 2,000)를 넘었다 | ❌ |
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
