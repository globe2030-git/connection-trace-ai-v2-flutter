import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2도 `Path`라는 이름을 내보낸다(경로 계산용). 그대로 두면 핀 꼬리를
// 그리는 `dart:ui`의 `Path`와 충돌하므로 여기서 가린다.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/address_geocoding_service.dart';
import '../../../common/call_picker_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/address_grouping.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../common/address_search_view.dart';
import '../utils/nearby_map_camera.dart';
import '../utils/nearby_map_clusters.dart';
import '../utils/nearby_map_label_collision.dart';
import '../utils/nearby_map_label_metrics.dart';
import '../view_models/radar_view_model.dart';
import 'nearby_map_cluster_sheet.dart';
import 'nearby_map_group_sheet.dart';
// 반경 선택 칩은 주변 화면과 공유한다 — 옵션·라벨·선택 시트가 갈라지면
// 두 화면이 서로 다른 반경 목록을 보여주게 된다.
import 'radar_view.dart';

/// 감지 반경 안의 인맥을 실제 지도 위에 보여주는 화면.
///
/// **인맥 좌표는 지도 사업자로 나가지 않는다.** 지도는 배경 타일만 내려받고,
/// 반경 원과 핀은 앱이 그 위에 직접 그린다. 외부로 나가는 것은 "지금 보고 있는
/// 지역의 타일 좌표"뿐이다 — 개인정보처리방침에도 이 구분대로 적었다.
class NearbyMapView extends StatefulWidget {
  const NearbyMapView({super.key});

  /// 지도가 이미 열려 있는지. 연속 탭으로 지도 화면이 겹겹이 쌓이는 것을
  /// 막는다(테스터 피드백, 2026-08-12) — 지도는 열 때마다 타일을 새로 내려받아
  /// 여러 장이 쌓이면 메모리·네트워크가 급격히 늘고 화면이 멈춘 것처럼 보인다.
  static bool _isOpen = false;

  static Future<void> show(BuildContext context) async {
    if (_isOpen) return;
    _isOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const NearbyMapView(),
        ),
      );
    } finally {
      // 닫히면(또는 예외가 나면) 다시 열 수 있게 반드시 풀어 준다.
      _isOpen = false;
    }
  }

  @override
  State<NearbyMapView> createState() => _NearbyMapViewState();
}

class _NearbyMapViewState extends State<NearbyMapView> {
  final _mapController = MapController();

  /// 직전에 그린 반경. 지도에서 반경을 바꾸면 원 크기만 바뀌고 화면 배율은
  /// 그대로라 원이 화면 밖으로 나가거나 점처럼 작아진다 — 바뀐 것을 눈으로
  /// 확인할 수 있도록 배율을 다시 맞추려고 들고 있는다.
  double? _lastRadius;

  /// 사용자가 손으로(제스처로) 지도를 옮긴 뒤의 중심점(추가 445, "이 위치에서
  /// 다시 찾기"). `null`이면 아직 손으로 옮긴 적이 없다는 뜻 — 그때는 버튼을
  /// 보여줄 이유가 없다.
  ///
  /// ⚠️ **프로그램이 지도를 옮긴 경우(반경 변경 시 자동 맞춤, 기준점 이동)는
  /// 여기 담지 않는다.** `MapOptions.onPositionChanged`의 `hasGesture`로
  /// 걸러낸다 — 안 걸러내면 기준점을 바꿔서 지도가 움직인 것도 "사용자가
  /// 끌어서 옮긴 것"으로 오인해, 방금 고른 기준점 위에 다시 찾기 버튼이 뜬다.
  LatLng? _gestureCenter;

  /// 검색 중 안내를 인라인으로 보여줄지. 이 화면은 바텀시트가 아니라
  /// 자체 `Scaffold`가 있는 전체 화면 라우트라 `ScaffoldMessenger`
  /// 스낵바를 써도 가려지지 않는다(바텀시트 안 스낵바 금지 규칙은 여기
  /// 해당 없음).
  bool _isSearchingAnchor = false;

  /// 브이월드(국토교통부 공간정보 오픈플랫폼) 인증키. 빌드할 때
  /// `--dart-define=VWORLD_KEY=...`로 넣는다. 키를 저장소에 커밋하지 않기
  /// 위해서다.
  ///
  /// 키가 없으면 OpenStreetMap 타일로 자동 전환한다 — 키 발급 전에도 화면이
  /// 비어 보이지 않게 하려는 것이고, OSM은 인증키·과금이 없다. 다만 국내
  /// 지번·건물 표기는 브이월드가 더 정확하므로 **운영 빌드에는 키를 넣는다.**
  static const _vworldKey = String.fromEnvironment('VWORLD_KEY');

  bool get _usingVWorld => _vworldKey.isNotEmpty;

  String get _tileUrl => _usingVWorld
      ? 'https://api.vworld.kr/req/wmts/1.0.0/$_vworldKey/Base/{z}/{y}/{x}.png'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// 지도 출처 표기. OSM은 라이선스상 표기가 **의무**이고, 브이월드도 출처
  /// 표시를 요구한다.
  String get _attribution =>
      _usingVWorld ? '© 국토교통부 브이월드' : '© OpenStreetMap contributors';

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// 반경이 화면에 꽉 차도록 초기 확대 수준을 고른다. 반경이 "제한 없음"이면
  /// 기준이 없으므로 동네가 보이는 정도로 시작한다.
  double _initialZoom(double radiusMeters) {
    if (radiusMeters.isInfinite) return 12;
    if (radiusMeters <= 500) return 15;
    if (radiusMeters <= 1000) return 14;
    if (radiusMeters <= 3000) return 13;
    return 12;
  }

  /// 기준 위치를 주소 검색으로 바꾼다(추가 445, ①). 이미 앱에 있는 주소 검색
  /// 화면(`address_search_view.dart`)을 그대로 재사용한다 — 새 검색 UI를
  /// 만들지 않는다는 지시대로다.
  ///
  /// 카카오가 그 자리에서 좌표를 못 주면(키 없음·도메인 불일치·검색 실패 등,
  /// `AddressSearchResult.geo`의 정상 실패 경로) `add_card_modal_view.dart`와
  /// 같은 순서로 OS/행안부 지오코더에 다시 물어본다 — 이 화면만 특별 취급하지
  /// 않고 앱 전체가 쓰는 지오코딩 경로를 그대로 탄다.
  Future<void> _openAddressSearch() async {
    final viewModel = context.read<RadarViewModel>();
    final result = await Navigator.of(context).push<AddressSearchResult>(
      MaterialPageRoute(builder: (_) => const AddressSearchView()),
    );
    if (result == null || !mounted) return;

    setState(() => _isSearchingAnchor = true);
    var geo = result.geo;
    if (geo == null) {
      final geocoded = await AddressGeocodingService.validateAndConvert(
        result.address,
        fallbackAddress: result.geocodeFallback,
      );
      geo = geocoded.isValid ? geocoded.geoPosition : null;
    }
    if (!mounted) return;
    setState(() => _isSearchingAnchor = false);

    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 주소의 좌표를 찾지 못했어요. 다른 주소로 다시 시도해 주세요.')),
      );
      return;
    }

    viewModel.setAnchor(geo, label: result.address.trim());
    // 새 기준점으로 카메라를 옮긴다. 아직 한 번도 손으로 지도를 안 옮긴
    // 상태와 같게 취급 — 방금 고른 기준점 위에 "다시 찾기" 버튼이 뜨면 안 된다.
    setState(() => _gestureCenter = null);
    try {
      _mapController.move(
        LatLng(geo.lat, geo.lng),
        _initialZoom(viewModel.settings.radiusMeters),
      );
    } catch (_) {
      // 지도가 아직 준비되지 않았으면 다음 빌드의 반경 재맞춤에서 잡힌다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RadarViewModel>();
    final me = viewModel.currentPosition;
    // 지도에서 직접 찍은 기준점(F-13). 없으면 내 위치가 기준이다.
    final anchor = viewModel.anchorPosition;
    final radius = viewModel.settings.radiusMeters;

    // 좌표가 있는 인맥만 지도에 올릴 수 있다. 주소만 있고 좌표 변환이 아직
    // 안 된 인맥은 목록에는 나와도 지도에는 찍을 수 없다 — 아래 개수 표시가
    // 목록 개수와 다를 수 있어 그 사실을 문구로 밝힌다.
    final plottable = viewModel.filteredContacts
        .where((c) => c.geo != null)
        .toList();
    final hiddenCount = viewModel.filteredContacts.length - plottable.length;

    if (me == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: _appBar(context),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              '현재 위치를 아직 확인하지 못했습니다.\n"주변" 화면에서 위치를 새로고침한 뒤 다시 열어 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
          ),
        ),
      );
    }

    // 내 위치와 거리 기준점은 다를 수 있다(F-13). 파란 점은 언제나 내 위치에
    // 그대로 두고, 반경 원과 거리 계산만 기준점을 따른다 — 내 점까지 함께
    // 옮기면 사용자가 자기가 어디 있는지를 잃는다.
    final myPoint = LatLng(me.lat, me.lng);
    final origin = anchor ?? me;
    final center = LatLng(origin.lat, origin.lng);

    // 반경이 바뀌었으면 원이 화면에 들어오도록 배율을 다시 맞춘다. 빌드 중에는
    // 지도를 움직일 수 없어 다음 프레임으로 미룬다.
    // 반경이 "전체"면 담을 원이 없다. 그때는 인맥이 실제로 있는 곳까지 담도록
    // 좌표 목록으로 맞춘다(2026-08-22 실측 — 예전에는 내 위치만 보고 배율을
    // 정해서, 인맥이 30km 밖에 있으면 핀이 하나도 없는 지도가 열렸다).
    final fitPlan = resolveMapFit(
      radiusMeters: radius,
      center: center,
      myPoint: myPoint,
      contactsNearestFirst: [
        for (final c in plottable)
          (
            point: LatLng(c.geo!.lat, c.geo!.lng),
            distanceMeters: GeoUtils.getDistanceMeters(origin, c.geo),
          ),
      ],
    );
    final fitPoints = fitPlan.coordinates;
    final cameraFit = fitPoints == null
        ? null
        : CameraFit.coordinates(
            coordinates: fitPoints,
            // ⚠️ 아래 여백이 큰 이유 — `_FoundBar`가 **지도 위에 겹쳐** 있다.
            // 맞춤은 그 사실을 모르므로, 여백이 작으면 가장 남쪽 핀을 흰 바
            // 뒤에 밀어 넣는다. 2026-08-22 실측에서 실제로 그랬다: 광주
            // 인맥(230.3km)의 핀이 화면 밖이 아니라 **바에 가려** 안 보였고,
            // "핀이 없는데 화면만 남쪽으로 벌어진" 것처럼 읽혔다.
            //
            // 실측: 바가 지도 아래 약 101dp를 덮는데 여백은 48이었다.
            padding: const EdgeInsets.only(
              left: 48,
              right: 48,
              top: 48,
              bottom: 150,
            ),
            maxZoom: kMapFitMaxZoom,
          );

    if (_lastRadius != null && _lastRadius != radius) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          if (cameraFit != null) {
            _mapController.fitCamera(cameraFit);
          } else {
            _mapController.move(center, _initialZoom(radius));
          }
        } catch (_) {
          // 지도가 아직 준비되지 않았으면 그냥 넘어간다 — 다음 조작 때 맞춰진다.
        }
      });
    }
    _lastRadius = radius;

    // "이 위치에서 다시 찾기"(추가 445, ③) — 사용자가 손으로 지도를 옮긴
    // 거리가 문턱을 넘었을 때만 버튼을 보여준다. 아직 안 옮겼으면(`null`)
    // 0으로 쳐서 버튼을 감춘다.
    final gestureCenterGeo = _gestureCenter == null
        ? null
        : GeoPosition(
            lat: _gestureCenter!.latitude,
            lng: _gestureCenter!.longitude,
          );
    final movedFromOriginMeters = gestureCenterGeo == null
        ? 0.0
        : GeoUtils.getDistanceMeters(origin, gestureCenterGeo);
    final showRefindButton = shouldShowRefindHereButton(movedFromOriginMeters);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: _appBar(context),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _initialZoom(radius),
              // 맞춤이 있으면 flutter_map이 첫 프레임에 이걸로 덮어쓴다.
              // `initialCenter`/`initialZoom`은 맞춤이 없을 때의 값으로 남는다.
              initialCameraFit: cameraFit,
              // 지도를 돌릴 수 있으면 "북쪽이 위"라는 기준이 흔들려 주변 인맥의
              // 방향을 읽기 어려워진다. 회전만 막고 확대·이동은 열어 둔다.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              // 지도를 누른 지점을 거리 기준으로 삼는다(F-13, 사용자 결정
              // 2026-08-16: 드래그가 아니라 탭). 드래그는 지도 이동(팬)과
              // 손동작이 겹쳐, 지도를 옮기려다 기준점이 딸려 온다.
              //
              // `onTap`은 탭에만 반응하고 팬·확대에는 반응하지 않는다. 새 제스처
              // 인식기를 얹지 않는 것이 중요하다 — 이 화면은 연속 터치로 멈추는
              // 결함(E-11)이 났던 자리다.
              onTap: (_, point) => viewModel.setAnchor(
                GeoPosition(lat: point.latitude, lng: point.longitude),
              ),
              // "이 위치에서 다시 찾기"(추가 445, ③)에 쓸 위치 추적. `hasGesture`로
              // 손으로 옮긴 것만 골라낸다 — 반경 변경 시 자동 맞춤이나 기준점
              // 이동으로 지도가 프로그램에 의해 움직인 것까지 잡으면, 기준점을
              // 방금 옮겨 놓고도 "다시 찾기" 버튼이 뜨는 오작동이 난다.
              onPositionChanged: (camera, hasGesture) {
                if (!hasGesture) return;
                setState(() => _gestureCenter = camera.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _tileUrl,
                // 타일 서버가 요청 주체를 식별할 수 있도록 패키지명을 밝힌다.
                // OSM 타일 이용 정책이 요구하는 사항이다.
                userAgentPackageName: 'com.creamhouse.connectionsense',
                maxZoom: 18,
              ),
              if (!radius.isInfinite)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: center,
                      radius: radius,
                      // 미터 단위로 그린다 — 화면 픽셀이 아니라 실제 거리라야
                      // 확대·축소해도 원이 지도와 함께 커지고 작아진다.
                      useRadiusInMeter: true,
                      color: AppColors.accent.withValues(alpha: 0.10),
                      borderColor: AppColors.accent.withValues(alpha: 0.55),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: myPoint,
                    width: 22,
                    height: 22,
                    child: const _MyLocationDot(),
                  ),
                  // 기준점을 옮겼을 때만 그린다. 내 위치와 모양을 다르게 해야
                  // 어느 쪽이 나이고 어느 쪽이 기준인지 구분된다.
                  if (anchor != null)
                    Marker(
                      point: center,
                      width: 30,
                      height: 30,
                      child: const _AnchorMark(),
                    ),
                ],
              ),
              // 인맥 마커는 별도 위젯으로 뺐다(추가 452) — 화면 좌표 기준으로
              // 라벨 충돌을 판정하려면 `MapCamera.of(context)`가 필요한데,
              // 그건 `FlutterMap.children` 목록 안(=`MapInheritedModel`
              // 아래)에서만 쓸 수 있다. 이 State의 `build()`는 `FlutterMap`
              // 바깥이라 여기서는 못 쓴다.
              _ContactMarkersLayer(
                markers: computeMapMarkerGroups(plottable),
                onTapContact: (contact) => _showContactSheet(
                  context,
                  contact,
                  origin,
                  isCustomAnchor: anchor != null,
                ),
                onTapGroup: (group) => showNearbyMapGroupSheet(
                  context,
                  group: group,
                  origin: origin,
                ),
                onTapCluster: (contacts) => showNearbyMapClusterSheet(
                  context,
                  contacts: contacts,
                  origin: origin,
                ),
              ),
            ],
          ),
          // 기준 위치 바(추가 445, ①) — 지금 무엇을 기준으로 지도를 보고
          // 있는지 상단에 항상 밝히고, 눌러서 주소 검색으로 바꿀 수 있게
          // 한다. "내 위치로 돌아가기"는 이 바가 아니라 오른쪽 아래
          // 버튼(`_MapButton`)이 맡는다 — 탭으로 찍었든 주소로 골랐든
          // `anchor != null`이면 같은 버튼이 같은 동작을 하므로 되돌릴
          // 수단을 두 번 만들 필요가 없다.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _AnchorBar(
              label: _basisLabel(viewModel),
              isCustom: anchor != null,
              isBusy: _isSearchingAnchor,
              onTap: _isSearchingAnchor ? null : _openAddressSearch,
            ),
          ),
          // "이 위치에서 다시 찾기"(추가 445, ③) — 지도를 일정 거리 이상 끌어
          // 옮겼을 때만 뜬다. 기준 위치 바 바로 아래에 둔다.
          if (showRefindButton)
            Positioned(
              top: 68,
              left: 0,
              right: 0,
              child: Center(
                child: _RefindHereButton(
                  onTap: () {
                    final g = _gestureCenter!;
                    viewModel.setAnchor(
                      GeoPosition(lat: g.latitude, lng: g.longitude),
                    );
                    setState(() => _gestureCenter = null);
                  },
                ),
              ),
            ),
          // 버튼과 아래 바를 **한 세로 묶음**으로 둔다. 예전에는 버튼이
          // `Positioned(bottom: 96)`으로 화면 밑에서 띄운 고정값이었는데,
          // 바에 안내 줄이 한 줄 늘자 바가 높아져 **버튼이 바 뒤로 숨었다**
          // (2026-08-16 실기기에서 확인). 하필 그 바에 "오른쪽 아래 버튼으로
          // 돌아갑니다"라고 적혀 있어, 가리키는 버튼이 안 보이는 상태였다.
          // 묶어 두면 바가 몇 줄이 되든 버튼은 항상 바로 위에 뜬다.
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 12),
                  child: _MapButton(
                    // 같은 버튼이지만 기준점을 옮겨 둔 상태에서는 하는 일이
                    // 하나 더 있다 — 기준점을 풀고 내 위치로 되돌린다.
                    // 되돌릴 방법이 없으면 "내 위치로 어떻게 돌아가지"가
                    // 곧바로 문의가 된다.
                    tooltip: anchor != null ? '기준점 해제 · 내 위치로' : '내 위치로',
                    icon: Icons.my_location,
                    onTap: () {
                      viewModel.clearAnchor();
                      setState(() => _gestureCenter = null);
                      _mapController.move(myPoint, _initialZoom(radius));
                    },
                  ),
                ),
                _FoundBar(
                  count: plottable.length,
                  hiddenCount: hiddenCount,
                  outsideCount: fitPlan.outsideCount,
                  attribution: _attribution,
                  // 탭으로 기준점을 지정하는 것은 **눌러 보기 전에는 알 수 없는
                  // 동작**이라 안내를 글자로 붙인다. 이 저장소가 이미 같은
                  // 판단을 한 자리가 있다 — 주변 화면의 "짧게: 위치 갱신 ·
                  // 길게: 감지 켜기/끄기" 줄이 같은 이유로 붙어 있다.
                  anchorDistanceFromMe: anchor == null
                      ? null
                      : GeoUtils.getDistanceMeters(me, anchor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final radius = context.select<RadarViewModel, double>(
      (vm) => vm.settings.radiusMeters,
    );
    return AppBar(
      backgroundColor: AppColors.cardSurface,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        '주변 인맥 지도',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      // 반경을 제목에 글자로만 적어 두면 "여기서 바꿀 수 있다"는 걸 알 수 없다.
      // 원을 보면서 바로 조절하고 싶다는 요청(2026-08-12)에 따라 주변 화면과
      // **같은 선택 칩**을 여기에도 둔다. 고른 값은 같은 뷰모델을 거쳐 기기에
      // 저장되므로 주변 화면으로 돌아가도 그대로 유지된다.
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: RadiusSelector(
              radiusMeters: radius,
              onChanged: context.read<RadarViewModel>().updateRadius,
            ),
          ),
        ),
      ],
    );
  }

  /// 핀을 눌렀을 때 뜨는 미니 카드.
  ///
  /// **여기에 전화·AI 버튼이 붙는 것이 F-14의 실제 변경분이다.** 그전에는 이
  /// 카드가 글자만 보여 주어, 같은 인맥이라도 목록에서는 바로 전화를 걸 수
  /// 있고 지도에서는 걸 수 없었다. 목록에서 버튼을 빼는 방향이 아니라 지도에
  /// 더하는 방향으로 맞춘다(사용자 결정 2026-08-16, A안).
  ///
  /// 빠른 동작은 **눈에 보이는 버튼**으로만 둔다 — 길게 누르기에 얹지 않는다.
  /// 이 앱에서 길게 누르기는 주변 화면의 위치 버튼 한 곳뿐이고, 거기조차 옆에
  /// 글자 설명을 붙여야 했다.
  void _showContactSheet(
    BuildContext context,
    ContactModel contact,
    GeoPosition origin, {
    required bool isCustomAnchor,
  }) {
    final distance = GeoUtils.getDistanceMeters(origin, contact.geo);
    // 번호가 하나도 없으면 통화 버튼을 잠근다 — 눌러도 아무 일이 없는 것보다
    // 낫다. 목록 카드와 같은 판단이다.
    final hasAnyPhone =
        contact.phone.trim().isNotEmpty ||
        (contact.officePhone?.trim().isNotEmpty ?? false);
    // 지도 라우트의 내비게이터·뷰모델을 미리 잡아 둔다. 시트를 닫은 뒤에는
    // 시트의 context가 죽어 있어 쓸 수 없다.
    final mapNavigator = Navigator.of(context);
    final viewModel = context.read<RadarViewModel>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        contact.title,
                        contact.company,
                      ].where((s) => s.trim().isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      // 기준점을 옮겨 둔 상태에서 "여기서"라고 하면 어디를
                      // 말하는지 알 수 없다. 무엇을 기준으로 잰 값인지 밝힌다.
                      distance.isFinite
                          ? '${isCustomAnchor ? '지정한 위치' : '내 위치'}에서 ${_distanceLabel(distance)}'
                          : '거리 정보 없음',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // 목록 카드와 같은 구성·같은 순서(전화 → AI). 같은 인맥을 두
              // 화면에서 다른 모양으로 보여 줄 이유가 없다.
              IconButton(
                tooltip: '${contact.name}에게 전화',
                onPressed: hasAnyPhone
                    ? () {
                        // 번호가 둘이면 선택 시트가 또 열린다. 미니 카드를 먼저
                        // 닫아 시트가 시트 위에 겹치지 않게 한다.
                        Navigator.of(sheetContext).pop();
                        // 번호 두 개 처리와 "실제로 통화가 시작됐는가" 반환값이
                        // 이미 검증된 경로다(2026-08-10·08-11). 새로 짜면 그
                        // 검증을 버리는 셈이라 목록과 같은 것을 쓴다.
                        showCallPicker(context, contact);
                      }
                    : null,
                icon: AppIcon(
                  AppIconId.call,
                  size: 22,
                  color: hasAnyPhone
                      ? AppColors.accentText
                      : AppColors.textMuted,
                ),
              ),
              IconButton(
                tooltip: '${contact.name} AI 대화 가이드',
                onPressed: () {
                  // 브리핑은 '주변' 화면 위에 겹쳐 그려진다. 지도는 그 위에 얹힌
                  // 별도 라우트라, 지도를 열어 둔 채 브리핑을 켜면 **지도 뒤에서
                  // 열려 아무것도 안 보인다.** 그래서 미니 카드와 지도를 닫고
                  // 연다. 어차피 브리핑은 전체 화면이라 지도는 가려진다.
                  Navigator.of(sheetContext).pop();
                  mapNavigator.pop();
                  viewModel.openBriefing(contact);
                },
                icon: const Icon(
                  Icons.auto_awesome,
                  size: 22,
                  color: AppColors.accentText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _distanceLabel(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  /// 기준 위치 바에 보여줄 문구(추가 445, ①).
  ///
  /// - 기준점이 없으면 "내 위치".
  /// - 주소 검색으로 골랐으면 그 주소 문장(뷰모델의 [RadarViewModel.anchorLabel]).
  /// - 지도를 탭하거나 "이 위치에서 다시 찾기"로 옮겼으면(라벨 없음) 일반화된
  ///   문구로 대신한다 — 좌표만 있고 사람이 읽을 이름은 없는 게 정상이다.
  static String _basisLabel(RadarViewModel viewModel) {
    if (viewModel.anchorPosition == null) return '내 위치';
    final label = viewModel.anchorLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return '지도에서 지정한 위치';
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.4),
            blurRadius: 8,
          ),
        ],
      ),
    );
  }
}

/// 사용자가 찍은 거리 기준점 표시(F-13).
///
/// 내 위치(채워진 원)와 **모양을 다르게** 한다 — 같은 모양이면 둘 중 어느 것이
/// 나인지 알 수 없다. 십자 과녁은 "여기를 기준으로 잰다"는 뜻으로 읽힌다.
class _AnchorMark extends StatelessWidget {
  const _AnchorMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '거리 기준점',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4)],
        ),
        child: const Icon(
          Icons.center_focus_strong,
          size: 18,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _ContactPin extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onTap;

  const _ContactPin({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = contact.name.trim().isEmpty
        ? '?'
        : contact.name.trim().characters.first;
    return Semantics(
      button: true,
      label: '${contact.name} 위치',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 4),
                ],
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            // 핀 끝을 뾰족하게 — 원만 있으면 어느 지점을 가리키는지 애매하다.
            CustomPaint(size: const Size(10, 8), painter: _PinTailPainter()),
          ],
        ),
      ),
    );
  }
}

/// 인맥 마커(묶음 + 낱개) 전체를 그리는 계층(추가 452로 신설).
///
/// `MapCamera.of(context)`로 **현재 화면 좌표**를 얻어 묶음 마커의 라벨끼리
/// 겹치는지 판정한다(`nearby_map_label_collision.dart`) — 이 계산은
/// `FlutterMap.children` 목록 안에서 빌드되는 위젯이어야만 `MapCamera`에
/// 접근할 수 있어 별도 위젯으로 뺐다. 지도를 옮기거나 확대할 때마다 이
/// `build()`가 다시 불리지만(카메라가 바뀌므로), **라벨 글자 폭은 다시 재지
/// 않는다** — 그 값은 `plottable`이 바뀔 때(=인맥 데이터가 바뀔 때)만
/// 재는 [measureGroupLabelWidth]에서 미리 받아 온다.
class _ContactMarkersLayer extends StatelessWidget {
  final List<MapMarkerGroup> markers;
  final ValueChanged<ContactModel> onTapContact;
  final ValueChanged<AddressGroup> onTapGroup;
  final ValueChanged<List<ContactModel>> onTapCluster;

  const _ContactMarkersLayer({
    required this.markers,
    required this.onTapContact,
    required this.onTapGroup,
    required this.onTapCluster,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);

    // 라벨이 있는 마커(=묶음, 2명 이상)만 충돌 판정 대상이다. 낱개 마커
    // (`_ContactPin`)는 애초에 라벨이 없어 겹칠 것도 없다 — 이 결함(추가
    // 452)은 추가 445가 묶음 마커에 붙인 회사명 라벨 때문에 생겼다.
    final groupById = <String, MapMarkerGroup>{};
    final candidates = <LabelCandidate>[];
    var order = 0;
    for (final marker in markers) {
      if (!marker.isGrouped) continue;
      final id = marker.representative.id;
      groupById[id] = marker;
      final offset = camera.latLngToScreenOffset(
        LatLng(marker.point.lat, marker.point.lng),
      );
      final text = groupCompanyLabel(marker.group) ?? '같은 주소 ${marker.count}명';
      candidates.add(
        LabelCandidate(
          id: id,
          x: offset.dx,
          y: offset.dy,
          labelWidth: measureGroupLabelWidth(text),
          // 우선순위 규칙(nearby_map_label_collision.dart 문서 참고):
          // 인원 많은 쪽 → order(=거리) 앞선 쪽. `markers`는 이미
          // `computeMapMarkerGroups(plottable)`가 거리순으로 넘겨주므로
          // 리스트 인덱스를 그대로 order로 쓴다.
          priority: marker.count,
          order: order,
        ),
      );
      order++;
    }
    final clusters = computeLabelClusters(candidates);
    final clusterById = <String, LabelCluster>{};
    for (final cluster in clusters) {
      for (final id in cluster.memberIds) {
        clusterById[id] = cluster;
      }
    }

    return MarkerLayer(
      markers: [
        for (final marker in markers)
          Marker(
            point: LatLng(marker.point.lat, marker.point.lng),
            // 묶음 마커는 대표 회사명(또는 "같은 주소 N명") 글자띠가
            // 원 위에 붙어 낱개 핀보다 폭이 넓다. 회사명 라벨은
            // 최대 [kGroupLabelMaxWidth]까지 쓰므로 그보다 넉넉히 잡는다
            // — 폭이 라벨보다 좁으면 옆 마커와 겹쳐 보인다.
            width: marker.isGrouped ? 160 : 40,
            height: marker.isGrouped ? 66 : 46,
            alignment: Alignment.topCenter,
            child: marker.isGrouped
                ? _buildGroupPin(
                    marker,
                    clusterById[marker.representative.id],
                    groupById,
                  )
                : _ContactPin(
                    contact: marker.representative,
                    onTap: () => onTapContact(marker.representative),
                  ),
          ),
      ],
    );
  }

  /// 묶음 마커 하나를 만든다 — [cluster]는 이 마커가 화면에서 다른 묶음
  /// 마커와 겹쳐 있으면 그 무리, 안 겹쳤으면 `null`이다.
  Widget _buildGroupPin(
    MapMarkerGroup marker,
    LabelCluster? cluster,
    Map<String, MapMarkerGroup> groupById,
  ) {
    return _GroupPin(
      group: marker.group,
      // 겹쳐서 하나의 클러스터로 묶였으면 대표(우선순위 최고)만 라벨을
      // 보여준다. 안 겹쳤으면(cluster==null) 예전처럼 항상 보인다.
      showLabel:
          cluster == null || cluster.visibleId == marker.representative.id,
      onTap: () {
        // 겹친 마커는 **아무거나 눌러도 같은 결과**를 보여준다(사용자 지시,
        // 추가 452) — 화면에서 겹쳐 있으면 손가락으로 어느 것을 정확히
        // 짚었는지 사용자도 구분할 수 없기 때문이다. 안 겹쳤으면 예전
        // 그대로 그 묶음의 단일 시트를 연다.
        if (cluster != null && cluster.isCollision) {
          onTapCluster([
            for (final id in cluster.memberIds)
              ...groupById[id]!.group.contacts,
          ]);
        } else {
          onTapGroup(marker.group);
        }
      },
    );
  }
}

/// 같은 도로명 주소에 여러 명이 있을 때 낱개 핀 대신 그리는 숫자 묶음
/// 마커(P2-①). 원 안에는 인원수, 위에는 **대표 회사명**(또는 회사명이 없으면
/// "같은 주소 N명") 라벨을 붙인다(추가 445, ②) — 그냥 숫자만 있으면 "왜
/// 숫자가 커졌지"와 "어느 건물이지"가 눌러 보기 전에는 안 읽힌다. 대표 회사를
/// 정하는 규칙은 [groupCompanyLabel] 참고.
///
/// 접근성 라벨은 도로명까지 포함한다("크림하우스 외 9, OO로 NN, 같은 주소
/// N명") — 스크린 리더 사용자는 원 안의 숫자나 라벨의 말줄임을 볼 수 없으므로,
/// 어느 주소·회사의 묶음인지까지 말해 줘야 낱개 핀들과 구분된다. **이 라벨은
/// [showLabel]이 `false`여도(화면 겹침으로 숨겨도) 항상 읽힌다** — 화면에서만
/// 숨기는 것이지 정보 자체를 잃는 게 아니다(추가 452).
class _GroupPin extends StatelessWidget {
  final AddressGroup group;
  final VoidCallback onTap;

  /// 화면 겹침 판정 결과 이 마커의 라벨을 보여줄지(`nearby_map_view.dart`
  /// `_ContactMarkersLayer`가 정한다). `false`면 자리만 비우고 원·꼬리는
  /// 그대로 그린다 — 마커 자체가 사라지면 안 된다(정보를 잃으면 안
  /// 된다는 지시, 추가 452). 대신 겹친 자리를 누르면
  /// [showNearbyMapClusterSheet]가 떠서 가려진 회사를 고를 수 있다.
  final bool showLabel;

  const _GroupPin({
    required this.group,
    required this.onTap,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final count = group.contacts.length;
    // 대표 회사명 라벨(추가 445, ②) — 누르기 전에 어느 건물인지 알 수 있게
    // 한다. 회사명이 하나도 없는 묶음이면(가짜 이름을 지어내지 않는다는
    // 원칙에 따라) [groupCompanyLabel]이 null을 주고, 그때는 예전 그대로
    // "같은 주소 N명"으로 보여준다.
    final companyLabel = groupCompanyLabel(group);
    final pillText = companyLabel ?? '같은 주소 $count명';
    return Semantics(
      button: true,
      label: companyLabel != null
          ? '$companyLabel, ${group.address}, 같은 주소 $count명'
          : '${group.address}, 같은 주소 $count명',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 대표 회사명(또는 "같은 주소 N명") 라벨 — 낱개 핀과 한눈에
            // 구분되도록 원 위에 알약 모양으로 얹는다.
            //
            // ⚠️ 회사명이 길면 지도를 가린다 — 최대 폭을 두고 한 줄로
            // 자른다(말줄임).
            //
            // [showLabel]이 false면(화면에서 다른 라벨과 겹침) 같은 높이의
            // 빈 자리로 대신한다 — 라벨 유무에 따라 원·꼬리 위치가 오르내리면
            // 지도를 쓰는 도중 마커가 흔들려 보인다.
            if (showLabel)
              ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: kGroupLabelMaxWidth,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.accent, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    pillText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kGroupLabelFontSize,
                      fontWeight: kGroupLabelFontWeight,
                      color: AppColors.accentText,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: kLabelHeight),
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 4),
                  ],
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // 핀 끝을 뾰족하게 — 낱개 핀과 같은 모양이라야 "이것도 이
            // 지점을 가리키는 핀이다"가 한눈에 읽힌다.
            ExcludeSemantics(
              child: CustomPaint(
                size: const Size(10, 8),
                painter: _PinTailPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.accent;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MapButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardSurface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: AppColors.accentText),
      ),
    );
  }
}

/// 지도 상단의 기준 위치 바(추가 445, ①). 지금 무엇을 기준으로 거리를 재고
/// 있는지 보여주고, 누르면 주소 검색으로 바꿀 수 있다.
class _AnchorBar extends StatelessWidget {
  final String label;

  /// 기준점이 내 위치가 아닌지 — 강조 색을 쓸지 정하는 데만 쓴다(지도 위의
  /// 다른 기준점 표시들과 같은 규칙).
  final bool isCustom;

  /// 주소를 고른 뒤 좌표를 구하는 동안(카카오가 못 주면 지오코더 재시도까지
  /// 걸리는 시간) 다시 누르지 못하게 막는다.
  final bool isBusy;

  final VoidCallback? onTap;

  const _AnchorBar({
    required this.label,
    required this.isCustom,
    required this.isBusy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '기준 위치: $label. 눌러서 주소로 바꾸기',
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isCustom ? Icons.center_focus_strong : Icons.my_location,
                  size: 16,
                  color: AppColors.accentText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '기준 위치',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentText,
                    ),
                  )
                else
                  const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.accentText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "이 위치에서 다시 찾기" 버튼(추가 445, ③). 지도를 일정 거리 이상 끌어
/// 옮겼을 때만 뜬다 — 노출 조건은 [shouldShowRefindHereButton]에서 정한다.
class _RefindHereButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RefindHereButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                '이 위치에서 다시 찾기',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지도 아래 "N명을 찾았습니다" 바.
class _FoundBar extends StatelessWidget {
  final int count;
  final int hiddenCount;

  /// 처음 화면 밖에 남은 인맥 수. 핀은 지도에 그대로 있고 축소하면 보인다.
  final int outsideCount;
  final String attribution;

  /// 기준점을 옮겨 뒀으면 내 위치에서 그 지점까지의 거리. 옮기지 않았으면
  /// `null`이고, 그때는 "지도를 누르면 된다"는 안내가 대신 나간다.
  final double? anchorDistanceFromMe;

  const _FoundBar({
    required this.count,
    required this.hiddenCount,
    required this.outsideCount,
    required this.attribution,
    this.anchorDistanceFromMe,
  });

  /// "(내 위치에서 1.2km)". 거리를 못 재면 괄호째 뺀다 — "내 위치에서 에서"
  /// 같은 문장이 되는 것보다 없는 편이 낫다.
  static String _fromMeSuffix(double meters) {
    if (!meters.isFinite) return '';
    if (meters < 1000) return ' (내 위치에서 ${meters.round()}m)';
    return ' (내 위치에서 ${(meters / 1000).toStringAsFixed(1)}km)';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.cardSurface,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count명을 지도에 표시했습니다',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            // 기준이 어디인지 항상 한 줄로 밝힌다. 기준점을 옮겨 놓고 그 사실을
            // 안 보여 주면 거리가 달라진 이유를 알 수 없다.
            Row(
              children: [
                Icon(
                  anchorDistanceFromMe == null
                      ? Icons.touch_app_outlined
                      : Icons.center_focus_strong,
                  size: 13,
                  color: anchorDistanceFromMe == null
                      ? AppColors.textMuted
                      : AppColors.accentText,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    anchorDistanceFromMe == null
                        ? '지도를 누르면 그 지점 기준으로 거리를 다시 계산합니다'
                        : '지금 기준: 지도에서 지정한 위치'
                              '${_fromMeSuffix(anchorDistanceFromMe!)}'
                              ' · 오른쪽 아래 버튼으로 내 위치로 돌아갑니다',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: anchorDistanceFromMe == null
                          ? FontWeight.w400
                          : FontWeight.w700,
                      color: anchorDistanceFromMe == null
                          ? AppColors.textMuted
                          : AppColors.accentText,
                    ),
                  ),
                ),
              ],
            ),
            // 좌표가 없는 인맥은 지도에 못 찍는다. 이 사실을 숨기면 "목록엔
            // 5명인데 지도엔 3명"이 버그로 보인다.
            // 무리에서 크게 벗어난 인맥은 첫 화면에 안 담는다 — 그 하나
            // 때문에 나머지가 전부 구석으로 몰리기 때문이다. 다만 **없는 것이
            // 아니라 밖에 있는 것**이므로 그렇게 말한다.
            if (outsideCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                '멀리 있는 $outsideCount명은 축소하면 보입니다',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(height: 2),
              Text(
                '주소 좌표가 아직 없는 $hiddenCount명은 표시되지 않았습니다',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              attribution,
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
