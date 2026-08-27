import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/contact_model.dart';
import '../utils/geo_utils.dart';
import 'address_geocoding_service.dart';
import 'juso_geocoding_service.dart';

/// 주소는 있는데 좌표(`ContactModel.geo`)가 없는 명함들의 좌표를 주소로부터
/// 다시 계산해 채워 넣는다.
///
/// **왜 필요한가**(backlog 추가 75, C안): 좌표는 서버에 백업하지 않는다.
/// 좌표는 명함에 적힌 주소를 지오코딩한 **파생값**이라 보관할 이유가 없고,
/// 보관하면 "회사가 위치정보를 보유한다"는 해석 여지가 생기기 때문이다.
/// 대신 기기를 바꾸거나 계정을 다시 연결해서 서버에서 명함을 복원하면 좌표가
/// 비어 있는 상태로 내려오므로, 그때 이 서비스가 주소로 좌표를 다시 만든다.
/// 명함 등록 시점에 쓰는 것과 **똑같은 경로**([AddressGeocodingService])라
/// 결과도 같다.
///
/// 좌표는 계산된 뒤 기기(`shared_preferences`, 암호화됨)에만 저장되므로 이
/// 작업은 기기당 한 번씩만 일어난다.
///
/// ### 설계상 신경 쓴 것
/// - **순차 + 간격**: OS 지오코더(iOS CLGeocoder / Android Geocoder)는 짧은
///   시간에 몰아치면 조용히 실패하거나 차단한다. 한 건씩, 사이에 간격을 두고
///   호출한다.
/// - **1회 실행 상한**: 명함이 많아도 한 번에 다 처리하지 않는다. 남은 건
///   다음 실행에서 이어서 채운다.
/// - **오프라인 조기 중단**: 연속으로 여러 건 실패하면 네트워크가 없다고
///   보고 그 회차를 즉시 접는다(10초 타임아웃 × N건을 낭비하지 않기 위함).
/// - **시도 횟수 제한**: OCR이 잘못 읽은 주소처럼 영영 지오코딩되지 않는
///   값이 있을 수 있다. 앱을 켤 때마다 무한히 재시도하지 않도록 명함별 시도
///   횟수를 세고 [maxAttemptsPerContact]회를 넘으면 포기한다. 단 **주소가
///   바뀌면 횟수를 초기화**해서 사용자가 주소를 고치면 다시 시도한다.
/// - **주소를 평문으로 남기지 않는다**: 시도 기록은 일반
///   `shared_preferences`(암호화되지 않음)에 저장되므로 주소 원문 대신
///   SHA-256 해시 앞부분만 넣는다. 추가 72에서 명함 데이터가 평문으로 읽히던
///   문제를 고쳤는데, 여기서 다시 흘리면 의미가 없다.
class GeoBackfillService {
  /// 한 명함에 대해 이 횟수만큼 실패하면 더 시도하지 않는다(주소가 바뀌면
  /// 초기화).
  static const int maxAttemptsPerContact = 3;

  /// 한 번 실행할 때 처리할 최대 건수.
  static const int maxContactsPerRun = 30;

  /// 지오코딩 호출 사이의 간격.
  static const Duration gapBetweenRequests = Duration(milliseconds: 400);

  /// 이만큼 연속으로 **통신 문제**([GeoFailureReason.communicationError])가
  /// 나면 네트워크가 없다고 보고 이번 회차를 중단한다.
  ///
  /// ⚠️ **"주소가 안 풀림"([GeoFailureReason.noResult])은 여기 안 낀다**(추가
  /// 434). 예전엔 실패 사유를 안 가리고 다 셌는데, 그러면 목록 앞쪽에 안
  /// 풀리는 주소가 3장만 몰려 있어도 회차가 거기서 죽어 뒤의 풀 수 있는
  /// 명함에 영원히 도달하지 못했다(실기기 실측: 진행 배너가 4~6/30에서 매번
  /// 멈춤).
  static const int consecutiveFailuresToAbort = 3;

  /// 시도 기록을 이만큼 실패할 때마다 도중 저장한다(추가 434). 매 건마다
  /// 저장하면 I/O가 과해지고, 회차 끝에서만 저장하면 도중에 죽었을 때 전부
  /// 사라진다 — 그 사이 균형점.
  static const int _attemptsSaveEvery = 5;

  static const String _attemptsKey = 'geo_backfill_attempts_v1';
  static const String _shapeStatsKey = 'geo_backfill_fail_shapes_v1';

  /// 마지막 백필 회차의 단계별 집계(추가 435 계측) — 값은 항상 **이전 회차를
  /// 덮어쓴다**("누적"이 아니라 "최근 한 회차"). 개수만 담고 주소는 없다.
  static const String _stageStatsKey = 'geo_backfill_stage_stats_v1';

  /// 테스트에서 실제 지오코더를 타지 않도록 주입할 수 있게 열어 둔다.
  final Future<AddressValidationResult> Function(String address) _geocode;
  final Duration _gap;

  GeoBackfillService({
    Future<AddressValidationResult> Function(String address)? geocode,
    Duration? gapBetweenRequests,
  }) : _geocode = geocode ?? AddressGeocodingService.validateAndConvert,
       _gap = gapBetweenRequests ?? GeoBackfillService.gapBetweenRequests;

  /// [contacts] 중 좌표를 채워야 하고 아직 포기하지 않은 명함 목록.
  ///
  /// 실제 채우기 전에 "할 일이 있는지"만 싸게 확인하고 싶을 때도 쓴다.
  Future<List<ContactModel>> pendingContacts(
    List<ContactModel> contacts,
  ) async {
    final attempts = await _loadAttempts();
    return contacts
        .where((c) => _needsGeo(c) && !_isGivenUp(c, attempts))
        .toList();
  }

  /// 이 명함이 **주소 지오코딩을 [maxAttemptsPerContact]회 모두 실패해 포기된**
  /// 상태인지. true면 주소로 위치를 찾지 못해 주변 인맥 목록(레이더)에 안 뜬다
  /// — 화면에서 "주소를 확인해 주세요" 안내를 띄우는 근거로 쓴다(P1-25).
  ///
  /// 좌표가 이미 있거나 주소가 비어 있으면(=계산 대상이 아님) false. 주소가
  /// 바뀌면 이전 실패 기록은 무효라 false(다시 시도 대상).
  Future<bool> hasGivenUpGeo(ContactModel c) async {
    if (!_needsGeo(c)) return false;
    final attempts = await _loadAttempts();
    return _isGivenUp(c, attempts);
  }

  /// [contacts] 중 **주소는 있는데 지오코딩을 포기한**(좌표를 못 만든) 명함
  /// id 집합. 시도 기록을 한 번만 읽어 목록 전체를 판정한다 — 명함 목록에서
  /// "위치값 없음" 아이콘을 카드마다 붙일 때 쓴다. `geo == null`만으로 판정하면
  /// 로그인 직후 backfill이 도는 동안 아직 안 채워진 명함까지 잡혀 아이콘이
  /// 깜빡이므로, "여러 번 시도하고도 못 찾은" 확정 상태만 넣는다.
  Future<Set<String>> resolveGivenUpIds(List<ContactModel> contacts) async {
    final attempts = await _loadAttempts();
    return {
      for (final c in contacts)
        if (_needsGeo(c) && _isGivenUp(c, attempts)) c.id,
    };
  }

  /// [contactIds]의 시도 기록을 지워 다시 시도 대상으로 되돌린다(추가 434 —
  /// 진단 화면 "좌표 다시 시도"). 포기(3회 실패)된 명함뿐 아니라 아직 포기
  /// 전인 명함의 기록도 지운다 — 어차피 다음 [backfill] 회차에서 다시
  /// 시도되므로 해가 없고, "포기분만 골라 지운다"는 조건을 따로 두지 않아도
  /// 된다.
  ///
  /// 이 메서드 자체는 [backfill]을 부르지 않는다 — 호출자가 필요하면 이어서
  /// 부른다(주소를 외부로 보내는 시점을 호출자가 통제할 수 있어야 한다).
  Future<void> resetAttempts(Iterable<String> contactIds) async {
    final ids = contactIds.toSet();
    if (ids.isEmpty) return;
    final attempts = await _loadAttempts();
    final changed = ids.where(attempts.containsKey).isNotEmpty;
    if (!changed) return;
    for (final id in ids) {
      attempts.remove(id);
    }
    await _saveAttempts(attempts);
  }

  /// 좌표가 비어 있는 명함들의 좌표를 채운다.
  ///
  /// 반환값은 `명함 id -> 새로 얻은 좌표` 맵이다. 호출자가 이 값으로
  /// 명함을 갱신하고 기기에 저장하면 된다. **서버에 다시 올릴 필요는 없다**
  /// — 좌표는 애초에 백업 대상이 아니기 때문이다.
  ///
  /// 실패한 건은 결과에 담기지 않고, 다음 실행에서 다시 시도된다
  /// ([maxAttemptsPerContact] 이내인 동안).
  ///
  /// [onResolved]는 한 건이 풀릴 **때마다** 즉시 불린다(추가 434). 반환 맵은
  /// 회차가 끝나야 받을 수 있는데, 도중에 앱이 죽으면(실기기 실측:
  /// `am force-stop`으로 재현) 그 회차의 성공분이 통째로 사라진다 — 호출자가
  /// 이 콜백에서 명함을 즉시 갱신·저장하면 "도중에 죽어도 이미 성공한 것은
  /// 남는다"가 성립한다. 콜백이 끝나기를 기다렸다가 다음 건으로 넘어간다
  /// (저장이 실제로 끝난 뒤 진행해야 순서가 어긋나지 않는다).
  ///
  /// [knownGeoByAddress]는 **주소 원문 → 이미 아는 좌표**다. 여기 있는 주소는
  /// 통신을 하지 않고 그 값을 그대로 쓴다 — 자세한 것은 아래 "같은 주소는
  /// 다시 안 물어본다" 참고.
  Future<Map<String, GeoPosition>> backfill(
    List<ContactModel> contacts, {
    Map<String, GeoPosition>? knownGeoByAddress,
    void Function(int done, int total)? onProgress,
    FutureOr<void> Function(String contactId, GeoPosition geo)? onResolved,
  }) async {
    final attempts = await _loadAttempts();
    final targets = contacts
        .where((c) => _needsGeo(c) && !_isGivenUp(c, attempts))
        .take(maxContactsPerRun)
        .toList();
    if (targets.isEmpty) return const {};

    final resolved = <String, GeoPosition>{};
    // ## 같은 주소는 다시 안 물어본다 (2026-08-28, globe2030님 지적)
    //
    // 예전에는 명함 단위로 돌았다 — 같은 회사 명함이 5장이면 **똑같은 주소를
    // 5번** 물어봤다. globe2030님이 짚었다: "회사별 좌표는 한번만 확인되면
    // 저장되는데 명함마다 계속 검색할 이유가 없지 않나."
    //
    // 📌 **새 저장소를 만들지 않는다.** 좌표는 이미 명함에 들어 있으므로
    // 명함 목록 자체가 캐시다. 호출자가 그 목록에서 map을 만들어 넘긴다.
    //
    // ⚠️ **주소 글자가 정확히 같을 때만** 빌려온다. 정규화는 하지 않는다 —
    // "서울 강남구"와 "서울특별시 강남구"를 같다고 보려면 주소를 정규화해야
    // 하는데, **잘못 묶으면 엉뚱한 좌표가 붙는다.** 조금이라도 다르면 평소대로
    // 물어본다: 안 되는 쪽으로 안전하다.
    //
    // ⭐ **정규화 없이도 쓸 만한 이유**: `address`와 `addressDetail`이 따로
    // 저장된다(층·호수는 다른 칸에 들어간다). 그래서 같은 회사 명함이면
    // `address`가 글자 그대로 같을 가능성이 높다.
    final known = <String, GeoPosition>{...?knownGeoByAddress};
    // 이번 회차의 단계별 집계(추가 435 계측) — "행안부 검색 실패/좌표 실패/
    // 성공, OS 폴백 성공, 둘 다 실패"를 개수로만 남긴다. `result.stage`가
    // null이면(주입된 테스트 더미 등, 계측을 안 채운 경우) 그 시도는 세지
    // 않는다 — 계측 공백이지 오류로 취급하지 않는다.
    final stageCounts = <GeoStage, int>{};
    var consecutiveFailures = 0;
    var failuresSinceSave = 0;
    var done = 0;

    for (final contact in targets) {
      final address = contact.address!.trim();

      // 이미 아는 주소면 통신하지 않는다.
      final borrowed = known[address];
      if (borrowed != null) {
        resolved[contact.id] = borrowed;
        // 이 명함의 옛 실패 기록도 지운다 — 좌표를 얻었으니 실패가 아니다.
        attempts.remove(contact.id);
        stageCounts[GeoStage.reusedFromSameAddress] =
            (stageCounts[GeoStage.reusedFromSameAddress] ?? 0) + 1;
        if (onResolved != null) {
          await onResolved(contact.id, borrowed);
        }
        done++;
        onProgress?.call(done, targets.length);
        // ⚠️ 여기서는 [_gap]을 기다리지 않는다 — 그 간격은 주소 서버를
        // 몰아치지 않으려는 것인데, 이 건은 서버를 부르지 않았다.
        continue;
      }

      GeoFailureReason? failureReason;
      try {
        final result = await _geocode(address);
        final stage = result.stage;
        if (stage != null) {
          stageCounts[stage] = (stageCounts[stage] ?? 0) + 1;
        }
        final geo = result.geoPosition;
        if (result.isValid && geo != null) {
          resolved[contact.id] = geo;
          // 이 회차의 다음 명함이 같은 주소면 빌려 쓴다.
          known[address] = geo;
          attempts.remove(contact.id);
          consecutiveFailures = 0;
          if (onResolved != null) {
            await onResolved(contact.id, geo);
          }
        } else {
          failureReason = result.failureReason;
          _recordFailure(attempts, contact.id, address);
          failuresSinceSave++;
        }
      } catch (e) {
        // validateAndConvert는 자체적으로 예외를 삼키지만, 주입된 구현이
        // 던질 수도 있으니 여기서도 막는다 — 한 건 때문에 회차 전체가
        // 죽으면 안 된다. 여기서 던졌다는 것 자체가 통신·구현 문제라
        // 통신 실패로 취급한다.
        debugPrint('좌표 재계산 실패(${contact.id}): $e');
        failureReason = GeoFailureReason.communicationError;
        _recordFailure(attempts, contact.id, address);
        failuresSinceSave++;
      }

      // ⚠️ 실패 사유를 가려서 센다(추가 434) — "주소가 안 풀림"은 이 명함
      // 하나로 끝나는 문제라 카운터를 되레 초기화한다(질의가 끝까지 갔다
      // 왔다는 것 자체가 통신은 살아 있다는 증거). "통신 문제"만 쌓는다.
      if (failureReason == GeoFailureReason.communicationError) {
        consecutiveFailures++;
      } else if (failureReason != null) {
        consecutiveFailures = 0;
      }

      if (failuresSinceSave >= _attemptsSaveEvery) {
        await _saveAttempts(attempts);
        failuresSinceSave = 0;
      }

      done++;
      onProgress?.call(done, targets.length);

      if (consecutiveFailures >= consecutiveFailuresToAbort) {
        // 네트워크가 없거나 지오코더가 막힌 상황으로 본다. 남은 건은
        // 다음 실행에서 처리한다.
        debugPrint('좌표 재계산 중단 — 연속 $consecutiveFailures건 통신 실패');
        break;
      }

      if (done < targets.length) {
        await Future<void>.delayed(_gap);
      }
    }

    await _saveAttempts(attempts);
    await _saveStageStats(stageCounts);
    return resolved;
  }

  /// 좌표를 채워야 하는 명함인지. 주소가 없으면 애초에 계산할 근거가 없다.
  static bool _needsGeo(ContactModel c) =>
      c.geo == null && (c.address?.trim().isNotEmpty ?? false);

  bool _isGivenUp(ContactModel c, Map<String, _AttemptRecord> attempts) {
    final record = attempts[c.id];
    if (record == null) return false;
    // 주소가 바뀌었으면 이전 실패 기록은 의미가 없다 — 다시 시도한다.
    if (record.addressHash != _hashAddress(c.address!.trim())) return false;
    return record.count >= maxAttemptsPerContact;
  }

  void _recordFailure(
    Map<String, _AttemptRecord> attempts,
    String contactId,
    String address,
  ) {
    final hash = _hashAddress(address);
    final existing = attempts[contactId];
    final firstFailureForThisAddress =
        existing == null || existing.addressHash != hash;
    attempts[contactId] = firstFailureForThisAddress
        ? _AttemptRecord(hash, 1)
        : _AttemptRecord(hash, existing.count + 1);

    // C안(2026-08-10): 어떤 주소가 좌표 변환에 실패하는지 **패턴**을 남긴다.
    // 왜 실패하는지(예: 건물명만 있고 지번이 없는 주소가 잘 실패한다)를 알아야
    // 지오코딩을 개선할 근거가 생긴다. 같은 주소를 재시도할 때마다 중복
    // 집계하지 않도록 그 주소의 **첫 실패**에서만 기록한다.
    //
    // ⚠️ 주소 원문은 절대 남기지 않는다(개인정보). 형태 신호(불리언)만 남긴다.
    if (firstFailureForThisAddress) {
      unawaited(_recordFailureShape(address));
    }
  }

  /// 실패한 주소의 **형태**를 집계에 더한다. 원문은 남기지 않는다.
  Future<void> _recordFailureShape(String address) async {
    final shape = _addressShape(address);
    debugPrint('[GeoBackfill] 좌표 변환 실패 · 형태=$shape');
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shapeStatsKey);
      final Map<String, dynamic> stats = raw == null || raw.isEmpty
          ? {}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();
      stats[shape] = ((stats[shape] as num?)?.toInt() ?? 0) + 1;
      await prefs.setString(_shapeStatsKey, jsonEncode(stats));
    } catch (e) {
      debugPrint('실패 형태 집계 저장 실패: $e');
    }
  }

  /// 주소를 **개인정보가 아닌 형태 코드**로 축약한다. 예: "road=1;jibun=0;
  /// digit=1;bldg=1;len=M". 내용(동 이름·번지·건물명)은 담지 않는다.
  static String _addressShape(String address) {
    final a = address.trim();
    // 도로명 주소: "…로 123" / "…길 45" 처럼 로/길 뒤에 번호.
    final hasRoad = RegExp(r'(로|길)\s*\d').hasMatch(a);
    // 지번 주소: "…동/리 12-3" 처럼 동/리 뒤에 번지.
    final hasJibun = RegExp(r'(동|리|가)\s*\d').hasMatch(a);
    final hasAnyDigit = RegExp(r'\d').hasMatch(a);
    // 건물명 후보: 흔한 건물 접미어. 있으면 "번지 없이 건물명만" 유형을
    // 가려내는 데 도움이 된다.
    final hasBldg = RegExp(r'(빌딩|타워|센터|플라자|하우스|오피스텔|아파트)').hasMatch(a);
    final len = a.length < 12
        ? 'S'
        : a.length < 25
        ? 'M'
        : 'L';
    return 'road=${hasRoad ? 1 : 0};jibun=${hasJibun ? 1 : 0};'
        'digit=${hasAnyDigit ? 1 : 0};bldg=${hasBldg ? 1 : 0};len=$len';
  }

  /// 지금까지 쌓인 실패 형태 집계를 읽는다(진단 화면용). `{형태코드: 건수}`.
  static Future<Map<String, int>> readFailureShapeStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_shapeStatsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e) {
      debugPrint('실패 형태 집계 로드 실패: $e');
      return const {};
    }
  }

  /// 행안부 검색·좌표 키가 **둘 다** 빌드에 실려 있는지(추가 435 계측).
  /// 값 자체(키 원문)는 절대 노출하지 않는다 — 탑재 여부만.
  ///
  /// ⚠️ 왜 여기 필요한가: 실기기에서 좌표 백필이 하나도 안 붙는 원인이
  /// "키가 실은 안 실렸다"인지 아닌지를 화면에서 바로 가를 수 있어야 한다.
  /// APK를 내려받아 `strings`로 뒤지는 것은 QA마다 못 하는 일이라, 앱
  /// 스스로 답할 수 있게 한다.
  static bool isJusoConfigured() => JusoGeocodingService().isConfigured;

  /// 이번 회차의 단계별 집계를 저장한다. **덮어쓰기**다 — 누적이 아니라
  /// "가장 최근 회차" 스냅샷만 남긴다(추가 435).
  Future<void> _saveStageStats(Map<GeoStage, int> counts) async {
    if (counts.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _stageStatsKey,
        jsonEncode({for (final e in counts.entries) e.key.name: e.value}),
      );
    } catch (e) {
      debugPrint('행안부 단계별 집계 저장 실패: $e');
    }
  }

  /// 마지막 백필 회차의 단계별 집계를 읽는다(진단 화면용, 추가 435).
  /// 키는 [GeoStage.name]("jusoSearchFailed" 등), 값은 그 단계로 끝난 시도
  /// 건수 — 주소 원문은 담지 않는다.
  static Future<Map<String, int>> readStageStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_stageStatsKey);
      if (raw == null || raw.isEmpty) return const {};
      final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (e) {
      debugPrint('행안부 단계별 집계 로드 실패: $e');
      return const {};
    }
  }

  /// **주소는 있는데 좌표가 없는 명함 수**와 **주소가 있는 명함 수**를 센다
  /// (추가 344).
  ///
  /// ## 왜 필요한가
  ///
  /// 진단 화면이 실패 **건수**만 보여 줘서 *"11건이 많은 건가 적은 건가"*를
  /// 말할 수 없었다(추가 343). 분모가 있어야 판단이 선다 — 주소 있는 명함
  /// 20장 중 11건이면 시급하고, 150장 중이면 뒤로 미뤄도 된다.
  ///
  /// ## ⚠️ 새 카운터를 두지 않은 이유
  ///
  /// 시도 횟수를 세는 카운터를 새로 넣으면 **0부터 시작한다.** 이미 쌓인 실패
  /// 11건과 짝이 안 맞아, 한동안 *"실패 11건 / 시도 0건"*이라는 말이 안 되는
  /// 숫자가 뜬다.
  ///
  /// **지금 명함 목록에서 세면 그 문제가 없다** — 상태를 직접 보는 것이라
  /// 기록이 언제 시작됐는지와 무관하다.
  static ({int withAddress, int missingGeo}) countGeoCoverage(
    List<ContactModel> contacts,
  ) {
    var withAddress = 0;
    var missingGeo = 0;
    for (final c in contacts) {
      if (!(c.address?.trim().isNotEmpty ?? false)) continue;
      withAddress++;
      if (c.geo == null) missingGeo++;
    }
    return (withAddress: withAddress, missingGeo: missingGeo);
  }

  /// **좌표가 없는 명함들의 주소 형태**를 지금 상태로 센다(추가 404).
  ///
  /// ## ⚠️ 왜 따로 세나 — [readFailureShapeStats]로는 못 본다
  ///
  /// 2026-08-22 실기기에서 **좌표 없는 명함이 67장인데 형태 집계는 비어
  /// 있었다.** 버그가 아니라 **설계의 공백**이었다.
  ///
  /// ```
  /// 형태 기록   그 주소의 **첫 실패**에서만 쌓는다(중복 집계를 피하려고)
  /// 포기 규칙   3회 실패하면 재시도 대상에서 **아예 뺀다**
  /// 계측 도입   2026-08-10 — 나중에 붙었다
  /// ```
  ///
  /// 셋이 겹치면 **그 전에 이미 실패한 것은 영원히 집계에 못 들어온다.** 첫
  /// 실패가 아니라 안 쌓이고, 재시도조차 안 해서 쌓일 기회도 없다.
  ///
  /// 📌 **집계는 시도 시점에 쌓이는데, 알고 싶은 것은 시도가 끝난 것들이다.**
  ///
  /// 그래서 추가 344와 같은 손을 쓴다 — 새 카운터를 두지 않고 **지금 명함
  /// 목록에서 센다.** 기록이 언제 시작됐는지와 무관해진다.
  ///
  /// ## ⚠️ 값의 뜻이 다르다
  ///
  /// [readFailureShapeStats]는 *"실패로 기록된 형태"*이고 이것은 *"좌표가 없는
  /// 주소의 형태"*다. **엄밀히 다른 값**이라 화면 문구도 그렇게 적어야 한다 —
  /// 아직 시도조차 안 한 명함도 여기에는 들어온다.
  ///
  /// 주소 원문은 세고 **버린다.** 형태 코드만 남는다.
  static Map<String, int> countShapesWithoutGeo(List<ContactModel> contacts) {
    final counts = <String, int>{};
    for (final c in contacts) {
      final address = c.address?.trim() ?? '';
      if (address.isEmpty) continue;
      if (c.geo != null) continue;
      final shape = _addressShape(address);
      counts[shape] = (counts[shape] ?? 0) + 1;
    }
    return counts;
  }

  /// 형태 코드를 **사람이 읽을 말로 푼다**(추가 342).
  ///
  /// ⚠️ **만드는 쪽([_addressShape])과 같은 파일에 둔다.** 코드 모양이 바뀌면
  /// 푸는 쪽도 같이 바뀌어야 하는데, 떨어져 있으면 한쪽만 고치고 만다.
  ///
  /// 화면에 `road=1;jibun=0;digit=1;bldg=1;len=M`을 그대로 띄우면 **아무도 못
  /// 읽는다** — 푸는 것까지가 진단의 일이다.
  static String describeFailureShape(String shape) {
    final m = <String, String>{};
    for (final part in shape.split(';')) {
      final kv = part.split('=');
      if (kv.length == 2) m[kv[0]] = kv[1];
    }
    if (m.isEmpty) return shape;
    return <String>[
      // ⚠️ 도로명이 있어도 **지번을 감추지 않는다.** 예전에는 road=1이면
      // jibun을 안 보여 줘, 서로 다른 두 코드가 똑같이 "도로명"으로 풀렸다
      // (추가 406에서 "도로명·보통"이 52장·1장 두 줄로 갈라져 보인 원인).
      if (m['road'] == '1')
        m['jibun'] == '1' ? '도로명+지번 섞임' : '도로명'
      else if (m['jibun'] == '1')
        '지번'
      else
        '둘 다 아님',
      if (m['digit'] == '0') '번호 없음',
      if (m['bldg'] == '1') '건물명 있음',
      switch (m['len']) { 'S' => '짧음', 'L' => '긺', _ => '보통' },
    ].join(' · ');
  }

  /// 주소 원문을 저장하지 않기 위한 축약 해시. 충돌해도 "재시도를 한 번 더
  /// 하거나 덜 하는" 정도의 영향뿐이라 12자면 충분하다.
  static String _hashAddress(String address) =>
      sha256.convert(utf8.encode(address)).toString().substring(0, 12);

  Future<Map<String, _AttemptRecord>> _loadAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_attemptsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(
          key as String,
          _AttemptRecord(
            (value as Map)['h'] as String? ?? '',
            (value['n'] as num?)?.toInt() ?? 0,
          ),
        ),
      );
    } catch (e) {
      debugPrint('좌표 재계산 시도 기록 로드 실패: $e');
      return {};
    }
  }

  Future<void> _saveAttempts(Map<String, _AttemptRecord> attempts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (attempts.isEmpty) {
        await prefs.remove(_attemptsKey);
        return;
      }
      await prefs.setString(
        _attemptsKey,
        jsonEncode(
          attempts.map(
            (key, value) =>
                MapEntry(key, {'h': value.addressHash, 'n': value.count}),
          ),
        ),
      );
    } catch (e) {
      debugPrint('좌표 재계산 시도 기록 저장 실패: $e');
    }
  }
}

class _AttemptRecord {
  final String addressHash;
  final int count;

  const _AttemptRecord(this.addressHash, this.count);
}
