/// **다른 계정에서 이 기기에 남아 있던 명함**의 id를 기억한다(2026-08-28, 추가 556).
///
/// ## 왜 필요한가 — 「유지」 보호 장치가 반쪽만 막고 있었다
///
/// 계정을 갈아탈 때 「유지」를 고르면 명함 본문을 새 계정 서버로 **일부러
/// 올리지 않는다**([mayMigrateToServer]) — 제3자(명함 주인) 개인정보가 두
/// 계정에 이중으로 존재하는 것을 막기 위해서다.
///
/// 🚨 **그런데 그 보호는 「일회성 마이그레이션」 하나에만 걸려 있었다.**
/// 전환하는 그 실행에서는 안 올리지만, 그때 *"마지막으로 로그인한 계정"*이
/// 새 계정으로 갱신되므로 **다음에 앱을 켜면 평범한 로그인 동기화 경로로
/// 들어간다.** 거기서 `syncWithServer`가 *"서버에 없는 로컬 명함"*을 전부
/// 올린다 — **그 함수는 「유지로 넘어온 명함」이라는 개념 자체를 모른다.**
///
/// ✅ **실물로 확인했다**(2026-08-28, 서버 실물 조회 · 건수만):
///
/// ```
/// 폴드   08-28 02:09(UTC) 「유지」 전환 → 같은 시간대에 서버 명함 103건
/// 아이폰 02:08·02:45 「유지」 2회        → 02~03시에 195건
/// ```
///
/// **폴드에는 그동안 새 명함을 하나도 등록하지 않았다**(사용자 확인). 즉 올라간
/// 103건은 전부 **앞 계정에서 넘어온 것**이다.
///
/// ## 왜 명함 자체에 넣지 않고 따로 두나
///
/// 이 표시는 **이 기기에서만 의미가 있다.** 서버 문서에 넣으면 그 값이 다른
/// 기기로 퍼지는데, "어느 계정에서 넘어왔나"는 기기마다 다른 사실이다.
/// 사진 장부([CardPhotoBackupStateService])와 같은 판단이다.
///
/// 담는 것은 **명함 id뿐**이라 개인정보가 아니다.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CarriedOverContactsService {
  static const String _prefsKey = 'carried_over_contact_ids_v1';

  /// 다른 계정에서 넘어온 명함 id들. 못 읽으면 **빈 집합**이다.
  ///
  /// ⚠️ 못 읽는 것과 없는 것을 구분하지 않는다 — 여기서 실패하면 "안 올린다"가
  /// 아니라 "올린다" 쪽으로 틀리는데, 그건 이 클래스가 막으려는 바로 그
  /// 방향이다. 그래서 **읽기 실패를 조용히 넘기지 않고 로그를 남긴다.**
  Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsKey) ?? const []).toSet();
    } catch (e) {
      debugPrint('넘어온 명함 표시 읽기 실패: ${e.runtimeType}');
      return <String>{};
    }
  }

  /// 「유지」를 고른 순간의 로컬 명함들을 표시한다. **덧붙인다** — 전환을 여러 번
  /// 하면 앞서 표시한 것이 사라지면 안 된다.
  Future<void> markAll(Iterable<String> contactIds) async {
    final ids = contactIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = {...(prefs.getStringList(_prefsKey) ?? const []), ...ids};
      await prefs.setStringList(_prefsKey, merged.toList()..sort());
    } catch (e) {
      debugPrint('넘어온 명함 표시 쓰기 실패: ${e.runtimeType}');
    }
  }

  /// 「교체」를 골랐거나 탈퇴했을 때 비운다 — 로컬 명함이 이 계정 것으로
  /// 갈아 끼워졌으므로 표시가 남으면 **자기 명함을 안 올리게** 된다.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('넘어온 명함 표시 비우기 실패: ${e.runtimeType}');
    }
  }
}

/// 전환 시각보다 **오래된** 명함 id를 고른다 — 소급 표시용(추가 556).
///
/// 🚨 표시는 전환하는 순간에 붙는데, **그 코드가 생기기 전에 전환한 기기에는
/// 표시가 없다.** 그 기기들이 바로 이번에 샌 기기들이다.
///
/// ```
/// 전환보다 오래된 명함        → 앞 계정에서 넘어온 것  → 표시한다
/// 전환 뒤에 손댄 명함          → 이 계정에서 만든 것    → 표시하지 않는다
/// 시각을 모르는 명함(null)     → 손댄 적이 없다는 뜻    → 표시한다
/// ```
///
/// ⚠️ **"전부 넘어온 것으로 친다"로 하면 자기 명함의 백업이 조용히 멈춘다.**
/// 실제로 아이폰 계정에는 전환 뒤에 손댄 명함이 5건 있었다(서버 기록 시각으로
/// 확인). 그 5건까지 묶으면 그 명함들은 어디에도 백업되지 않는다.
List<String> selectCarriedOverByTime<T>(
  Iterable<T> contacts, {
  required DateTime switchedAt,
  required String Function(T) idOf,
  required DateTime? Function(T) updatedAtOf,
}) => contacts
    .where((c) {
      final at = updatedAtOf(c);
      return at == null || at.isBefore(switchedAt);
    })
    .map(idOf)
    .toList();

/// 서버로 올릴 명함을 고른다 — **넘어온 명함은 뺀다**(2026-08-28, 추가 556).
///
/// 순수 함수로 뺀 이유는 [selectCardPhotoBackfillTargets]와 같다: 올리는 일
/// 자체는 네트워크라 자동 검사로 확인하기 어렵지만, **무엇을 고르는가**는
/// 규칙이고 틀리면 **조용히** 틀린다. 그리고 이 규칙이 틀리면 제3자
/// 개인정보가 남의 계정 서버로 나간다 — 되돌리기 어려운 방향이다.
List<T> selectPushTargets<T>(
  Iterable<T> candidates,
  Set<String> carriedOverIds, {
  required String Function(T) idOf,
}) => candidates.where((c) => !carriedOverIds.contains(idOf(c))).toList();
