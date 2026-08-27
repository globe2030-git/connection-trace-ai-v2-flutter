import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/contact_model.dart';
import '../utils/address_region.dart';

/// 명함 하나가 **주변 화면에서 어떤 상태인지**.
///
/// 화면이 안내를 띄울지, 띄운다면 **무슨 말을 할지**를 이것으로 가른다.
enum GeoNoticeState {
  /// 좌표가 있다 — 거리로 보인다. 안내가 필요 없다.
  located,

  /// 좌표는 없지만 **주소에서 지역을 뽑을 수 있다.**
  ///
  /// ⚠️ **이 상태에 *"확인할 수 없습니다"* 라고 말하면 거짓이다** — 화면에서
  /// 사라지지 않았고 지역 묶음으로 잘 보인다. 2026-08-21 실측에서 좌표 없는
  /// 30건이 **전부** 이 상태였다.
  ///
  /// 📌 그래도 안내할 값이 있다 — **주소를 고치면 거리로 보인다.**
  regionOnly,

  /// 좌표도 없고 **지역도 못 뽑는다.** 주변 화면에서 실제로 사라진다.
  hidden,

  /// 주소 자체가 없다. 지오코딩이 실패한 것이 아니라 **입력이 없는 것**이라
  /// 성격이 다르다 — 화면이 다르게 다뤄야 한다.
  noAddress,
}

/// 좌표를 못 얻은 명함이 **왜 그런지**를 화면에 알려 주는 읽기 전용 통로.
///
/// ## 🚨 왜 이것이 따로 필요한가
///
/// P1-25(명함 상세 안내)가 여태 안 된 이유는 **안내를 안 만들어서가 아니라
/// 만들 재료가 화면에 없었기 때문**이다.
///
/// ```
/// ContactModel            geo 하나만 들고 있다 — 실패 이유·시도 횟수가 없다
/// GeoBackfillService      시도 횟수를 shared_preferences 에 보관한다
/// 화면                    그 값을 볼 통로가 없었다
/// ```
///
/// ## ⚠️ 읽기만 한다. 아무것도 쓰지 않는다
///
/// `shared_preferences` 는 **암호화되지 않는다.** 지금 그 키에 들어 있는 것은
/// **명함 id · 주소 해시 · 실패 횟수**뿐이고 **주소 원문이 아니다.** 이 클래스는
/// 그 상태를 그대로 두기 위해 **읽기만** 한다 — 쓰기 메서드를 두지 않는다.
///
/// 📌 기록을 만들고 지우는 것은 [GeoBackfillService] 하나뿐이다. 여기서 함께
/// 쓰기 시작하면 **같은 키를 두 곳이 만지게 되고, 어느 쪽이 마지막인지 알 수
/// 없어진다.**
class GeoFailureLookup {
  /// [GeoBackfillService] 가 쓰는 키. **같은 값을 두 곳에 적지 않도록** 여기서
  /// 다시 정의하지 말아야 하지만, 그쪽이 private 이라 부득이 맞춰 둔다.
  ///
  /// ⚠️ **한쪽을 바꾸면 다른 쪽도 바꿔야 한다.** 어긋나면 이 통로가 **조용히
  /// 빈 값을 돌려준다** — 오늘 `firestore.rules` 에서 겪은 것과 같은 모양이다
  /// (추가 533). 그래서 테스트로 고정했다.
  static const String prefsKey = 'geo_backfill_attempts_v1';

  /// [GeoBackfillService.maxAttemptsPerContact] 와 같아야 한다. 위와 같은 이유로
  /// 테스트가 둘을 견준다.
  static const int maxAttempts = 3;

  /// 명함 id → 실패 횟수. **그 명함의 지금 주소로 실패한 횟수만** 센다.
  ///
  /// 주소가 바뀌면 이전 기록은 의미가 없다 — [GeoBackfillService] 도 같은
  /// 이유로 주소 해시를 함께 저장하고, 여기서도 그 규칙을 그대로 따른다.
  Future<Map<String, int>> loadFailureCounts(
    Iterable<ContactModel> contacts,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};

      final addressHashById = {
        for (final c in contacts)
          if ((c.address?.trim().isNotEmpty ?? false))
            c.id: hashAddress(c.address!.trim()),
      };

      final result = <String, int>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final storedHash = value['h'] as String? ?? '';
        final count = (value['n'] as num?)?.toInt() ?? 0;
        // 지금 주소로 실패한 것만 센다.
        if (addressHashById[key] == storedHash) result[key] = count;
      });
      return result;
    } catch (e) {
      // ⚠️ 주소·이름을 로그에 남기지 않는다. 종류만 찍는다.
      debugPrint('좌표 실패 기록 조회 실패: ${e.runtimeType}');
      return const {};
    }
  }

  /// [GeoBackfillService] 와 **같은 방식**으로 주소를 해시한다.
  ///
  /// 🚨 이 계산이 달라지면 저장된 기록과 하나도 안 맞아 **조용히 "실패한 적
  /// 없음"이 된다.** 테스트로 고정했다.
  static String hashAddress(String address) =>
      sha256.convert(utf8.encode(address)).toString().substring(0, 12);
}

/// 명함 하나의 상태를 정한다. **화면이 무슨 말을 할지가 여기서 갈린다.**
///
/// [failureCount] 는 [GeoFailureLookup.loadFailureCounts] 가 준 값이고, 기록이
/// 없으면 `null` 이다.
///
/// ⚠️ **아직 포기하지 않은 명함에는 안내를 띄우지 않는다.** 다음 실행에서 좌표를
/// 얻을 수 있는데 *"찾지 못했습니다"* 라고 하면 **틀린 말**이 된다.
GeoNoticeState geoNoticeStateOf(ContactModel c, int? failureCount) {
  if (c.geo != null) return GeoNoticeState.located;
  if (!(c.address?.trim().isNotEmpty ?? false)) return GeoNoticeState.noAddress;
  if ((failureCount ?? 0) < GeoFailureLookup.maxAttempts) {
    // 아직 시도할 여지가 있다 — 말하지 않는다.
    return GeoNoticeState.located;
  }
  return regionOf(c.address).shortLabel == null
      ? GeoNoticeState.hidden
      : GeoNoticeState.regionOnly;
}
