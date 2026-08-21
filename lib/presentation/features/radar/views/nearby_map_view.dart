import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2도 `Path`라는 이름을 내보낸다(경로 계산용). 그대로 두면 핀 꼬리를
// 그리는 `dart:ui`의 `Path`와 충돌하므로 여기서 가린다.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../utils/nearby_map_camera.dart';
import '../view_models/radar_view_model.dart';
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
    final fitPoints = mapFitCoordinates(
      radiusMeters: radius,
      center: center,
      myPoint: myPoint,
      contactPoints: [
        for (final c in plottable) LatLng(c.geo!.lat, c.geo!.lng),
      ],
    );
    final cameraFit = fitPoints == null
        ? null
        : CameraFit.coordinates(
            coordinates: fitPoints,
            padding: const EdgeInsets.all(48),
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
                  for (final contact in plottable)
                    Marker(
                      point: LatLng(contact.geo!.lat, contact.geo!.lng),
                      width: 40,
                      height: 46,
                      alignment: Alignment.topCenter,
                      child: _ContactPin(
                        contact: contact,
                        onTap: () => _showContactSheet(
                          context,
                          contact,
                          origin,
                          isCustomAnchor: anchor != null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
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
                      _mapController.move(myPoint, _initialZoom(radius));
                    },
                  ),
                ),
                _FoundBar(
                  count: plottable.length,
                  hiddenCount: hiddenCount,
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
                        PhoneCallService.showCallPicker(context, contact);
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

/// 지도 아래 "N명을 찾았습니다" 바.
class _FoundBar extends StatelessWidget {
  final int count;
  final int hiddenCount;
  final String attribution;

  /// 기준점을 옮겨 뒀으면 내 위치에서 그 지점까지의 거리. 옮기지 않았으면
  /// `null`이고, 그때는 "지도를 누르면 된다"는 안내가 대신 나간다.
  final double? anchorDistanceFromMe;

  const _FoundBar({
    required this.count,
    required this.hiddenCount,
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
