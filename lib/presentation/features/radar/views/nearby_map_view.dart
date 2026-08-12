import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2도 `Path`라는 이름을 내보낸다(경로 계산용). 그대로 두면 핀 꼬리를
// 그리는 `dart:ui`의 `Path`와 충돌하므로 여기서 가린다.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../view_models/radar_view_model.dart';

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

    final center = LatLng(me.lat, me.lng);

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
              // 지도를 돌릴 수 있으면 "북쪽이 위"라는 기준이 흔들려 주변 인맥의
              // 방향을 읽기 어려워진다. 회전만 막고 확대·이동은 열어 둔다.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
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
                    point: center,
                    width: 22,
                    height: 22,
                    child: const _MyLocationDot(),
                  ),
                  for (final contact in plottable)
                    Marker(
                      point: LatLng(contact.geo!.lat, contact.geo!.lng),
                      width: 40,
                      height: 46,
                      alignment: Alignment.topCenter,
                      child: _ContactPin(
                        contact: contact,
                        onTap: () => _showContactSheet(context, contact, me),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 12,
            bottom: 96,
            child: _MapButton(
              tooltip: '내 위치로',
              icon: Icons.my_location,
              onTap: () => _mapController.move(center, _initialZoom(radius)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _FoundBar(
              count: plottable.length,
              hiddenCount: hiddenCount,
              attribution: _attribution,
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
      title: Text(
        radius.isInfinite
            ? '주변 인맥 지도'
            : '주변 인맥 지도 · 반경 ${_radiusLabel(radius)}',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  static String _radiusLabel(double meters) {
    if (meters.isInfinite) return '제한 없음';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(0)}km';
  }

  void _showContactSheet(
    BuildContext context,
    ContactModel contact,
    GeoPosition me,
  ) {
    final distance = GeoUtils.getDistanceMeters(me, contact.geo);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardSurface,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
                distance.isFinite
                    ? '여기서 ${_distanceLabel(distance)}'
                    : '거리 정보 없음',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
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

  const _FoundBar({
    required this.count,
    required this.hiddenCount,
    required this.attribution,
  });

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
