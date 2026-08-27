import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/geo_utils.dart';
import 'juso_geocoding_service.dart';

/// 지오코딩이 **왜** 실패했는지(추가 434).
///
/// 백필 장치(`GeoBackfillService`)의 연속 실패 중단 규칙이 이 값을 근거로
/// 삼는다 — "네트워크가 없다"와 "이 주소는 정말 안 풀린다"는 뒤에 남은
/// 명함들에 대해 전혀 다른 함의를 갖는다. 앞쪽 몇 장이 안 풀리는 주소일
/// 뿐인데 회차 전체가 죽어서는 안 된다(실기기 실측: 4~6/30에서 매번 멈춤).
enum GeoFailureReason {
  /// 질의(검색·역지오코딩)는 끝까지 다녀왔지만 일치하는 위치가 없었다 —
  /// 주소 자체의 문제. 이 명함 하나가 안 풀릴 뿐, 뒤에 있는 다른 명함이
  /// 풀릴 가능성과는 무관하다.
  noResult,

  /// 타임아웃·예외 등 통신이 끝까지 가지 못했다 — 네트워크나 서버 쪽 문제라
  /// 뒤에 있는 명함도 같은 이유로 실패할 가능성이 높다.
  communicationError,
}

/// 이 시도가 **어느 공급자로 끝났는지**(추가 435 계측). [GeoFailureReason]이
/// "왜 실패했나"라면 이건 "누가 처리했나"에 가깝다 — 진단 화면이 회차별로
/// "행안부 검색 실패 N · 행안부 좌표 실패 N · 행안부 성공 N · OS 폴백 성공 N ·
/// 둘 다 실패 N"을 보여줄 근거가 이 값이다.
///
/// 다섯 값은 **서로 배타적인 하나의 결과 태그**다 — 판정 순서:
/// 1. 행안부가 좌표까지 얻었으면 [jusoSuccess].
/// 2. 아니면 OS 지오코더가 얻었으면 [osFallbackSuccess](행안부가 왜 안 됐는지는
///    안 가린다 — "OS로 살아남았다"가 더 실용적인 신호라서).
/// 3. 둘 다 실패했는데 행안부가 **키가 있어 시도라도 했다면** 그 단계를
///    남긴다([jusoSearchFailed]/[jusoCoordFailed]) — 원인 자리를 좁힐 수 있다.
/// 4. 행안부를 아예 시도 못 했으면(키 없음) [bothFailed] — "키 탑재 여부"는
///    화면에 별도로 뜨므로 여기서 더 쪼개지 않는다.
/// 좌표 한 건이 **어떻게 끝났는지**(추가 435 계측).
///
/// ⚠️ [reusedFromSameAddress] 만 성격이 다르다 — 나머지 넷은 *"어느 공급자가
/// 답했나"* 인데 이것은 **아무에게도 안 물어봤다**는 뜻이다. 한 표에 함께
/// 두는 이유는 화면이 묻는 것이 *"이 회차에 30건이 어떻게 처리됐나"* 라서다.
enum GeoStage {
  jusoSearchFailed,
  jusoCoordFailed,
  jusoSuccess,
  osFallbackSuccess,
  bothFailed,

  /// 같은 주소를 가진 다른 명함이 **이미 좌표를 갖고 있어 그대로 썼다.**
  /// 통신을 하지 않았다(2026-08-28).
  reusedFromSameAddress,
}

class AddressValidationResult {
  final bool isValid;
  final String originalAddress;
  final String? roadNameAddress;
  final GeoPosition? geoPosition;
  final String? message;

  /// 실패했을 때만 의미가 있다. 성공(`isValid == true`)이면 항상 null.
  /// 실패인데 null이면 "구분 안 됨"(구버전 호출부·주소 공백 등 드문 경로)
  /// 이라는 뜻 — 호출부는 이 경우 "통신 문제로 확신할 수 없다"로 취급해야
  /// 한다(안전한 쪽으로: 회차를 함부로 중단하지 않는다).
  final GeoFailureReason? failureReason;

  /// 이 시도가 어느 공급자로 끝났는지(추가 435 계측). 이 클래스를 직접 만드는
  /// 옛 호출부·테스트가 많아 **nullable + 기본값 없음**으로 둔다 — 값이 없으면
  /// [GeoBackfillService]가 그 시도는 집계에서 빼고 지나간다(계측 공백이지
  /// 오류는 아니다).
  final GeoStage? stage;

  const AddressValidationResult({
    required this.isValid,
    required this.originalAddress,
    this.roadNameAddress,
    this.geoPosition,
    this.message,
    this.failureReason,
    this.stage,
  });
}

/// 주소 끝에 붙은 참고항목 괄호를 떼어낸다.
///
/// 예: "경기 성남시 분당구 판교역로 235 (삼평동, 에이치스퀘어)"
///  →  "경기 성남시 분당구 판교역로 235"
///
/// 표시·저장에는 괄호를 포함한 원본을 쓰고, 좌표 조회에만 이 결과를 쓴다.
String stripReferenceText(String address) {
  final stripped = address.replaceFirst(RegExp(r'\s*\([^()]*\)\s*$'), '').trim();
  return stripped.isEmpty ? address.trim() : stripped;
}

class AddressGeocodingService {
  // geocoding 5.x부터 top-level 함수(geocoding.locationFromAddress(...))가 아니라
  // Geocoding 인스턴스 메서드로 API가 바뀜(4.x대 breaking change).
  static final Geocoding _geocoder = Geocoding();

  /// 행안부 지오코딩 통신 층. 테스트에서 실제 통신 없이 검증할 수 있도록
  /// 주입 가능하게 열어 둔다 — 기본값은 키가 안 들어 있으면 [JusoGeocodingService.isConfigured]가
  /// false라 조용히 비켜선다(빌드에 `JUSO_SEARCH_KEY`/`JUSO_COORD_KEY`를
  /// 안 넣으면 지금 동작과 완전히 같다).
  @visibleForTesting
  static JusoGeocodingService jusoService = JusoGeocodingService();

  /// 입력한 주소를 좌표로 바꾼다.
  ///
  /// ## 순서 — 행안부 먼저, 안 되면 OS 지오코더
  ///
  /// 행안부(business.juso.go.kr)가 좌표 공급자로 확정됐다(카카오·브이월드는
  /// 결과 저장이 약관 금지). 검색 키·좌표 키가 둘 다 있으면 먼저 시도하고,
  /// 키가 없거나(`isConfigured == false`) 결과를 못 얻으면 지금까지 쓰던
  /// OS 지오코더(iOS: CLGeocoder / Android: 네이티브 Geocoder)로 넘어간다.
  ///
  /// ⚠️ **키가 없을 때는 지금 동작과 완전히 같다.** 이것이 안전 기본값이다
  /// (`KAKAO_JS_KEY`와 같은 패턴) — 행안부 코드가 서버·앱에 딸려 들어가도
  /// 키를 안 넣는 한 아무 것도 안 바뀐다.
  ///
  /// 📌 **성능은 아직 이 사슬 전체로는 안 쟀다.** 검색 API 단독 판정
  /// 규칙(`juso_geocoding.dart`의 `pickBest`)은 90건 대조로 82.2%를 실측했지만,
  /// 그건 검색 응답을 비교한 것이지 좌표제공 API(`addrCoordApi.do`)까지 통과한
  /// 최종 좌표 획득률이 아니다. 좌표 키는 2026-08-24에야 승인됐다 — 전체
  /// 사슬 성능은 키를 넣고 실기기로 재측정해야 한다.
  ///
  /// ## [address]에는 상세주소를 붙이지 않는다
  ///
  /// ⚠️ 실기기 실측(추가 406, 두 표본 재현): 도로명 주소 뒤에 상세주소(동/호수
  /// 등)를 이어 붙여 질의하면 검색 결과가 0/25로 떨어진다. 그래서 이 함수는
  /// **기본 주소만** 받는 것을 전제로 한다 — 실제로 지금 호출부
  /// (`add_card_modal_view.dart`의 `_addressController`, `geo_backfill_service.dart`의
  /// `contact.address`)는 이미 `addressDetail`을 분리해서 관리하고 있어 이
  /// 계약을 그대로 만족한다. 여기서 새로 정제하지 않는다 — 이미 분리돼
  /// 들어오는 값을 그대로 쓰는 것까지만.
  ///
  /// [fallbackAddress]는 1차 조회가 실패했을 때 다시 시도할 **같은 위치의 다른
  /// 표기**다(도로명으로 안 되면 지번으로). 행안부·OS 지오코더 양쪽 다 이
  /// 순서를 따른다.
  ///
  /// 왜 필요한가: OS 지오코더가 도로명 주소로는 좌표를 못 찾는데 지번으로는
  /// 찾는 경우가 실사용에서 확인됐다(2026-08-14). 좌표가 없으면 그 인맥은
  /// 주변 지도에 아예 안 뜨는데, 우편번호 서비스는 두 표기를 함께 주므로
  /// 한 번 더 물어보면 살릴 수 있다.
  ///
  /// 저장되는 주소 문자열은 **1차 주소 그대로**다 — 화면에 보이는 주소가
  /// 갑자기 지번으로 바뀌면 사용자는 자기가 고른 것과 다르다고 느낀다.
  /// 여기서 지번은 좌표를 얻는 데만 쓴다.
  static Future<AddressValidationResult> validateAndConvert(
    String address, {
    String? fallbackAddress,
  }) async {
    final jusoAttempt = await _tryJuso(address, fallbackAddress: fallbackAddress);
    if (jusoAttempt.result != null) return jusoAttempt.result!;

    final first = await _lookup(address);
    if (first.isValid) return _withStage(first, GeoStage.osFallbackSuccess);

    final fallback = (fallbackAddress ?? '').trim();
    if (fallback.isEmpty || fallback == address.trim()) {
      return _withStage(first, _finalFailureStage(jusoAttempt.attemptedStage));
    }

    final second = await _lookup(fallback);
    if (!second.isValid) {
      return _withStage(first, _finalFailureStage(jusoAttempt.attemptedStage));
    }

    // 좌표는 지번으로 얻었지만 주소는 1차(도로명) 것을 유지한다.
    return AddressValidationResult(
      isValid: true,
      originalAddress: address.trim(),
      roadNameAddress: second.roadNameAddress,
      geoPosition: second.geoPosition,
      message: second.message,
      stage: GeoStage.osFallbackSuccess,
    );
  }

  /// 행안부·OS 둘 다 실패했을 때 붙일 최종 단계(추가 435 계측). 행안부를
  /// 시도조차 못 했으면(키 없음) [GeoStage.bothFailed] — "어느 단계에서
  /// 죽었나"를 더 좁힐 근거 자체가 없다.
  static GeoStage _finalFailureStage(JusoStage? attemptedStage) {
    if (attemptedStage == JusoStage.searchFailed) return GeoStage.jusoSearchFailed;
    if (attemptedStage == JusoStage.coordFailed) return GeoStage.jusoCoordFailed;
    return GeoStage.bothFailed;
  }

  static AddressValidationResult _withStage(
    AddressValidationResult r,
    GeoStage stage,
  ) => AddressValidationResult(
    isValid: r.isValid,
    originalAddress: r.originalAddress,
    roadNameAddress: r.roadNameAddress,
    geoPosition: r.geoPosition,
    message: r.message,
    failureReason: r.failureReason,
    stage: stage,
  );

  /// 행안부로 먼저 시도한다. 키가 없거나 실패하면 `result: null` — 호출부가
  /// OS 지오코더 경로로 넘어간다. [attemptedStage]는 실패했을 때(추가 435
  /// 계측) 어느 단계에서 죽었는지를 함께 알려준다 — 아예 시도하지 못했으면
  /// (키 없음·빈 주소) `null`.
  ///
  /// ⚠️ 도로명 주소 변환 제안(`roadNameAddress`)은 여기서 만들지 않는다.
  /// 행안부 검색 응답에 `roadAddr`가 있긴 하지만, 그걸 "제안"으로 띄우려면
  /// 원본과 비교하는 규칙이 따로 필요하고 이번 작업 범위 밖이다 — OS
  /// 지오코더 경로로 폴백했을 때만 지금처럼 제안이 뜬다(한계로 남긴다).
  static Future<({AddressValidationResult? result, JusoStage? attemptedStage})>
  _tryJuso(String address, {String? fallbackAddress}) async {
    if (!jusoService.isConfigured) {
      return (result: null, attemptedStage: null);
    }
    final trimmed = address.trim();
    if (trimmed.isEmpty) return (result: null, attemptedStage: null);

    final query = stripReferenceText(trimmed);
    final outcome = await jusoService.geocodeStaged(query);
    if (outcome.position != null) {
      return (
        result: AddressValidationResult(
          isValid: true,
          originalAddress: trimmed,
          geoPosition: outcome.position,
          message: '주소 위치를 확인했습니다.',
          stage: GeoStage.jusoSuccess,
        ),
        attemptedStage: JusoStage.success,
      );
    }

    final fallback = (fallbackAddress ?? '').trim();
    if (fallback.isEmpty || fallback == trimmed) {
      return (result: null, attemptedStage: outcome.stage);
    }
    final fallbackOutcome = await jusoService.geocodeStaged(
      stripReferenceText(fallback),
    );
    if (fallbackOutcome.position == null) {
      return (result: null, attemptedStage: fallbackOutcome.stage);
    }
    return (
      result: AddressValidationResult(
        isValid: true,
        originalAddress: trimmed,
        geoPosition: fallbackOutcome.position,
        message: '주소 위치를 확인했습니다.',
        stage: GeoStage.jusoSuccess,
      ),
      attemptedStage: JusoStage.success,
    );
  }

  static Future<AddressValidationResult> _lookup(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return const AddressValidationResult(
        isValid: false,
        originalAddress: '',
        message: '주소가 입력되지 않았습니다.',
      );
    }

    try {
      // Android 네이티브 Geocoder는 백엔드 서비스가 응답을 안 주면 예외를
      // 던지지도 않고 Future가 영원히 안 끝나는 경우가 있다("주소 확인 중..."
      // 상태로 멈추는 문제로 실기기에서 확인됨) — 타임아웃을 걸어서 일정
      // 시간 안에 안 끝나면 실패로 처리한다.
      // 주소 끝의 참고항목 괄호는 떼고 조회한다. 우편번호 서비스에서 고른
      // 주소에는 "… 판교역로 235 (삼평동, 에이치스퀘어)"처럼 법정동·건물명이
      // 붙어 있는데(backlog 추가 83), OS 지오코더는 이 괄호가 붙으면 주소를
      // 못 찾는 경우가 있다. 저장되는 문자열은 괄호를 포함한 원본 그대로다 —
      // 여기서 떼는 것은 좌표 조회용 질의뿐이다.
      final query = stripReferenceText(trimmed);
      final locations = await _geocoder
          .locationFromAddress(query)
          .timeout(const Duration(seconds: 10));
      if (locations.isEmpty) {
        return AddressValidationResult(
          isValid: false,
          originalAddress: trimmed,
          failureReason: GeoFailureReason.noResult,
          message: '위치를 찾을 수 없는 주소입니다. 건물명이나 도로명 주소를 확인해 주세요.',
        );
      }

      final location = locations.first;
      final geoPosition = GeoPosition(
        lat: location.latitude,
        lng: location.longitude,
      );
      final roadNameAddress = await _reverseGeocodeToRoadName(location);

      return AddressValidationResult(
        isValid: true,
        originalAddress: trimmed,
        roadNameAddress: roadNameAddress,
        geoPosition: geoPosition,
        message: '주소 위치를 확인했습니다.',
      );
    } catch (_) {
      return AddressValidationResult(
        isValid: false,
        originalAddress: trimmed,
        failureReason: GeoFailureReason.communicationError,
        message: '위치를 찾을 수 없는 주소입니다. 건물명이나 도로명 주소를 확인해 주세요.',
      );
    }
  }

  static Future<String?> _reverseGeocodeToRoadName(Location location) async {
    try {
      final placemarks = await _geocoder
          .placemarkFromCoordinates(location.latitude, location.longitude)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isEmpty) return null;

      final p = placemarks.first;

      // Android 네이티브 역지오코딩이 이 좌표에 대해 시/도(administrativeArea)
      // 만 돌려주고 도로명(thoroughfare)은 비워서 주는 경우가 실기기에서
      // 확인됐다(예: "경기도 성남시 분당구 대왕판교로644번길 49" 주소가
      // "경기도"로만 돌아옴 — 판교 한컴타워 주소, 2026-08-07). 도로명이
      // 없으면 "도로명 주소"라고 부를 수 없는데, 예전엔 이걸 그대로 받아들여
      // 멀쩡하던 원본 주소를 시/도 한 단어로 덮어써 버리는 심각한 데이터
      // 손실이 있었다. 도로명 자체가 없으면 변환 결과를 아예 버리고
      // null(변환 실패)로 처리해 원본 주소를 그대로 쓰게 한다.
      if (p.thoroughfare == null || p.thoroughfare!.trim().isEmpty) {
        return null;
      }

      final parts = [
        p.administrativeArea,
        p.subAdministrativeArea,
        p.thoroughfare,
        p.subThoroughfare,
      ].where((s) => s != null && s.trim().isNotEmpty).toList();

      if (parts.isEmpty) return null;
      return parts.join(' ');
    } catch (_) {
      // 역지오코딩 실패는 치명적이지 않음 — 정방향 지오코딩으로 얻은 좌표는
      // 이미 유효하므로 원본 주소를 그대로 쓰면 된다.
      return null;
    }
  }
}
