import '../../data/models/contact_model.dart';
import '../utils/address_region.dart';
import 'geo_backfill_service.dart';

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
/// ## 🚨 처음에 이 파일을 잘못 만들었다 — 경위를 남긴다
///
/// 처음 판은 `shared_preferences` 의 시도 기록을 **직접 열어 해석했다.** 키
/// 이름·주소 해시 계산·`maxAttempts` 3을 [GeoBackfillService] 와 **똑같이 한 벌
/// 더 적어 두고**, 그 둘이 어긋나지 않도록 대조 테스트까지 붙였다.
///
/// ⚠️ **그럴 필요가 없었다. 판정 함수가 이미 있었다.**
///
/// ```
/// GeoBackfillService.resolveGivenUpIds   기록을 한 번 읽어 목록 전체를 판정
/// ocr_stats_view.dart:103                이미 쓰고 있었다
/// contacts_repository.hasAddressGeocodingFailed   주석에 "(P1-25)" 라고 적혀 있다
/// ```
///
/// 착수 근거를 *"화면이 그 값을 볼 통로가 없다"* 로 적었는데 **통로는 있었다.**
/// `main` 실물을 먼저 열어 보라는 규약(CLAUDE.md 4-2절)을 **내 작업에는 적용하지
/// 않은 것**이 원인이다.
///
/// 📌 **더 나쁜 점은 동작이 맞았다는 것이다.** 복제한 해시 계산이 우연히 아니라
/// 정확히 같아서 테스트가 전부 통과했고, 그래서 **자동 검사로는 안 잡혔다.**
/// 틀렸으면 잡혔을 것을, 맞아서 놓쳤다.
///
/// ## 그래서 지금은 위임만 한다
///
/// 이 파일에 남은 것은 **[GeoBackfillService] 의 판정을 화면이 쓸 모양으로
/// 바꿔 주는 얇은 층**과, 그 결과를 문구로 가르는 [geoNoticeStateOf] 뿐이다.
/// 키·해시·횟수는 **한 곳에만 있다.**
class GeoFailureLookup {
  GeoFailureLookup({GeoBackfillService? service})
    : _service = service ?? GeoBackfillService();

  final GeoBackfillService _service;

  /// [contacts] 중 **주소로 좌표를 얻지 못해 포기된** 명함 id 집합.
  ///
  /// 판정은 전부 [GeoBackfillService.resolveGivenUpIds] 가 한다 — 시도 횟수도,
  /// **주소가 바뀌면 이전 실패는 무효**라는 규칙도 그쪽 것이다. 여기서 다시
  /// 세지 않는다.
  Future<Set<String>> loadGivenUpIds(Iterable<ContactModel> contacts) =>
      _service.resolveGivenUpIds(contacts.toList());
}

/// 명함 하나의 상태를 정한다. **화면이 무슨 말을 할지가 여기서 갈린다.**
///
/// [givenUp] 은 [GeoFailureLookup.loadGivenUpIds] 에 이 명함이 들어 있었는지다.
///
/// ⚠️ **아직 포기하지 않은 명함에는 안내를 띄우지 않는다.** 다음 실행에서 좌표를
/// 얻을 수 있는데 *"찾지 못했습니다"* 라고 하면 **틀린 말**이 된다.
GeoNoticeState geoNoticeStateOf(ContactModel c, bool givenUp) {
  if (c.geo != null) return GeoNoticeState.located;
  if (!(c.address?.trim().isNotEmpty ?? false)) return GeoNoticeState.noAddress;
  // 아직 시도할 여지가 있다 — 말하지 않는다.
  if (!givenUp) return GeoNoticeState.located;
  return regionOf(c.address).shortLabel == null
      ? GeoNoticeState.hidden
      : GeoNoticeState.regionOnly;
}
