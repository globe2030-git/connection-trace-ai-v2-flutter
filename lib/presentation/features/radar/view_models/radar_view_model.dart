import 'package:flutter/foundation.dart';
import '../../../../core/services/location_consent_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/proximity_settings_service.dart';
import '../../../../core/services/reconnect_priority_service.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/proximity_settings.dart';
import '../../../../data/repositories/contacts_repository.dart';

enum LocationAccessState {
  loading,
  consentRequired,
  consentDeclined,
  locating,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  ready,
  unavailable,
}

class RadarViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  final LocationGateway _locationService;
  final LocationConsentStore _locationConsentService;
  final ProximitySettingsStore _proximitySettingsService;

  ProximitySettings _settings = const ProximitySettings();
  GeoPosition? _currentPosition;

  /// 사용자가 지도에서 직접 찍은 거리 기준점(F-13). `null`이면 내 현재 위치가
  /// 기준이다.
  ///
  /// **기기에 저장하지 않는다(사용자 결정, 2026-08-16).** 바로 아래 감지 반경은
  /// 저장하므로(추가 139) 여기만 빠진 것처럼 보이지만, 빠뜨린 것이 아니다.
  /// 기준점은 "내일 갈 동네를 잠깐 살펴본다"는 **일시적 조작**이라, 앱을 껐다
  /// 켰는데 엉뚱한 동네가 기준으로 남아 있으면 "왜 내 위치가 아니지"가 된다.
  /// 저장을 넣으면 검증 등급도 부분 테스트에서 전체 테스트로 올라간다.
  GeoPosition? _anchorPosition;
  LocationConsentRecord _locationConsent = LocationConsentRecord.unknown;
  LocationAccessState _locationAccessState = LocationAccessState.loading;
  bool _isRefreshingLocation = false;
  bool _isDisposed = false;
  ContactModel? _selectedContactForBriefing;
  ContactModel? _previewContact;
  String _searchTerm = '';

  late final Future<void> initialization;

  RadarViewModel({
    required ContactsRepository contactsRepository,
    LocationGateway? locationService,
    LocationConsentStore? locationConsentService,
    ProximitySettingsStore? proximitySettingsService,
  }) : _contactsRepository = contactsRepository,
       _locationService = locationService ?? LocationService(),
       _locationConsentService =
           locationConsentService ?? LocationConsentService(),
       _proximitySettingsService =
           proximitySettingsService ?? ProximitySettingsService() {
    _contactsRepository.addListener(_onContactsChanged);
    // 저장해 둔 감지 반경을 먼저 되살린다. 이게 없으면 앱을 다시 켤 때마다
    // 기본값(1km)으로 돌아가 사용자가 고른 기준이 사라진다(추가 139).
    _restoreRadius();
    // 앱 실행 직후에는 OS 권한을 요청하지 않는다. 저장된 앱 자체 동의를 먼저
    // 확인하고, 동의가 있는 경우에만 현재 OS 권한 상태로 위치를 읽는다.
    initialization = _initializeLocation();
  }

  Future<void> _restoreRadius() async {
    final saved = await _proximitySettingsService.load();
    if (_isDisposed) return;
    _settings = saved;
    _safeNotify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _contactsRepository.removeListener(_onContactsChanged);
    super.dispose();
  }

  void _onContactsChanged() => _safeNotify();

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  ProximitySettings get settings => _settings;
  GeoPosition? get currentPosition => _currentPosition;

  /// 지도에서 지정한 기준점. 지정하지 않았으면 `null`.
  GeoPosition? get anchorPosition => _anchorPosition;

  /// 지금 거리 기준이 내 위치가 아닌지. 화면에 "지금 기준이 어디인가"를
  /// 밝히는 데 쓴다 — 이걸 숨기면 거리가 달라진 이유를 알 수 없다.
  bool get isUsingCustomAnchor => _anchorPosition != null;

  /// **거리 계산의 유일한 기준점.** 지도의 반경 원·핀 거리, 목록의 거리·정렬이
  /// 모두 이 한 값을 본다. 화면마다 따로 기준을 두면 같은 사람이 지도와
  /// 목록에서 다른 거리로 보인다.
  GeoPosition? get referencePosition => _anchorPosition ?? _currentPosition;
  bool get isRefreshingLocation => _isRefreshingLocation;
  bool get usingRealGps => _currentPosition != null;
  bool get isLocationInitialized =>
      _locationAccessState != LocationAccessState.loading;
  bool get hasLocationConsent =>
      _locationConsent.decision == LocationConsentDecision.accepted;
  bool get shouldShowLocationConsent =>
      _locationAccessState == LocationAccessState.consentRequired;
  LocationConsentRecord get locationConsent => _locationConsent;
  LocationAccessState get locationAccessState => _locationAccessState;
  // 좌표는 서버에 백업하지 않으므로(backlog 추가 75, C안) 새 기기에서 복원한
  // 직후에는 명함에 좌표가 없어 거리 계산이 안 된다. 주소로 좌표를 다시
  // 계산하는 동안 화면이 "주변에 아무도 없음"으로 보이면 오해를 사므로,
  // 준비 중이라는 사실을 그대로 노출한다.
  bool get isPreparingContactLocations => _contactsRepository.isBackfillingGeo;
  int get contactLocationsPrepared => _contactsRepository.geoBackfillDone;
  int get contactLocationsToPrepare => _contactsRepository.geoBackfillTotal;

  ContactModel? get selectedContactForBriefing => _selectedContactForBriefing;
  ContactModel? get previewContact => _previewContact;
  String get searchTerm => _searchTerm;

  Future<void> _initializeLocation() async {
    try {
      _locationConsent = await _locationConsentService.loadRecord();
      switch (_locationConsent.decision) {
        case LocationConsentDecision.unknown:
          _locationAccessState = LocationAccessState.consentRequired;
          _safeNotify();
        case LocationConsentDecision.declined:
          _locationAccessState = LocationAccessState.consentDeclined;
          _safeNotify();
        case LocationConsentDecision.accepted:
          await refreshLocation();
      }
    } catch (_) {
      _currentPosition = null;
      _locationAccessState = LocationAccessState.unavailable;
      _safeNotify();
    }
  }

  Future<void> acceptLocationConsent() async {
    _locationConsent = await _locationConsentService.accept();
    await _resolveLocationAccess(requestPermission: true);
  }

  Future<void> declineLocationConsent() async {
    _locationConsent = await _locationConsentService.decline();
    _currentPosition = null;
    _anchorPosition = null;
    _locationAccessState = LocationAccessState.consentDeclined;
    _safeNotify();
  }

  Future<void> withdrawLocationConsent() => declineLocationConsent();

  Future<void> requestLocationPermission() async {
    if (!hasLocationConsent) return;
    await _resolveLocationAccess(requestPermission: true);
  }

  Future<void> refreshLocation() async {
    if (!hasLocationConsent) {
      _currentPosition = null;
      _anchorPosition = null;
      _locationAccessState =
          _locationConsent.decision == LocationConsentDecision.declined
          ? LocationAccessState.consentDeclined
          : LocationAccessState.consentRequired;
      _safeNotify();
      return;
    }
    await _resolveLocationAccess(requestPermission: false);
  }

  Future<void> refreshLocationAccess() => refreshLocation();

  Future<bool> openRelevantLocationSettings() {
    if (_locationAccessState == LocationAccessState.serviceDisabled) {
      return _locationService.openDeviceLocationSettings();
    }
    return _locationService.openAppPermissionSettings();
  }

  Future<void> _resolveLocationAccess({required bool requestPermission}) async {
    // 앱 복귀와 사용자의 수동 갱신이 동시에 들어와도 GPS 요청은 하나만 유지한다.
    if (_isRefreshingLocation) return;
    _isRefreshingLocation = true;
    _locationAccessState = LocationAccessState.locating;
    _safeNotify();

    final access = requestPermission
        ? await _locationService.requestPermission()
        : await _locationService.checkAccess();

    switch (access) {
      case DeviceLocationAccess.granted:
        final position = await _locationService.getCurrentPosition();
        _currentPosition = position;
        _locationAccessState = position == null
            ? LocationAccessState.unavailable
            : LocationAccessState.ready;
      case DeviceLocationAccess.serviceDisabled:
        _currentPosition = null;
        _locationAccessState = LocationAccessState.serviceDisabled;
      case DeviceLocationAccess.denied:
        _currentPosition = null;
        _locationAccessState = LocationAccessState.permissionDenied;
      case DeviceLocationAccess.deniedForever:
        _currentPosition = null;
        _locationAccessState = LocationAccessState.permissionDeniedForever;
      case DeviceLocationAccess.error:
        _currentPosition = null;
        _locationAccessState = LocationAccessState.unavailable;
    }

    // 위치를 잃으면 지도에서 찍어 둔 기준점도 함께 푼다. 내 위치가 없으면
    // 지도 화면 자체가 열리지 않아 기준점을 되돌릴 방법이 없는데, 목록 거리만
    // 지정한 지점 기준으로 남으면 사용자가 손쓸 수 없는 상태가 된다.
    if (_currentPosition == null) _anchorPosition = null;

    _isRefreshingLocation = false;
    _safeNotify();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    _safeNotify();
  }

  /// 화면(지도·목록)이 보는 목록. 내 위치가 아니라 **기준점**을 본다(F-13) —
  /// 지도에서 다른 지점을 찍어 두면 그 점 기준으로 반경 안에 드는 사람이 바뀐다.
  List<ContactModel> get filteredContacts => _contactsNear(referencePosition);

  /// 주어진 지점을 기준으로 반경·검색어를 적용해 거른다.
  ///
  /// 기준점을 인자로 받는 이유는 **부르는 쪽마다 기준이 다르기 때문이다.**
  /// 화면은 기준점(둘러보기)을, 근접 알림은 내 실제 위치(지금 여기)를 쓴다.
  List<ContactModel> _contactsNear(GeoPosition? origin) {
    final currentPosition = origin;
    if (currentPosition == null) return const [];

    final contacts = _contactsRepository.contacts;
    final query = _searchTerm.trim().toLowerCase();
    final list = contacts.where((c) {
      if (c.geo == null) return false;
      final distance = GeoUtils.getDistanceMeters(currentPosition, c.geo);
      if (distance > _settings.radiusMeters) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          c.company.toLowerCase().contains(query) ||
          c.title.toLowerCase().contains(query);
    }).toList();

    list.sort((a, b) {
      final distA = GeoUtils.getDistanceMeters(currentPosition, a.geo);
      final distB = GeoUtils.getDistanceMeters(currentPosition, b.geo);
      final compDist = distA.compareTo(distB);
      if (compDist != 0) return compDist;
      return a.name.compareTo(b.name);
    });

    return list;
  }

  /// "지금 근처에 이 사람이 있습니다"로 알릴 후보.
  ///
  /// ⚠️ **여기만 기준점(F-13)을 쓰지 않는다. 빠뜨린 것이 아니다.**
  /// 이 값은 *"지금 내가 있는 곳에 누가 있나"*에 답한다. 기준점을 적용하면
  /// 서울에 있는 사용자가 지도에서 부산을 찍은 순간 400km 떨어진 사람을
  /// "근처에 있다"고 알리게 된다 — 거짓 알림이고, 사용자는 기준점을 옮긴
  /// 것과 그 알림을 연결 짓지 못한다.
  ///
  /// 그래서 후보를 거를 때도 `filteredContacts`(기준점 기준)를 쓰지 않고
  /// **내 실제 위치로 다시 거른다.**
  ContactModel? get nearbyAlertContact {
    final origin = _currentPosition;
    if (origin == null) return null;
    final inRange = _contactsNear(origin);
    if (inRange.isEmpty) return null;

    final priorities = inRange.where((c) => c.isPriority).toList();
    final candidatePool = priorities.isNotEmpty ? priorities : inRange;
    candidatePool.sort((a, b) {
      final dA = GeoUtils.getDistanceMeters(origin, a.geo);
      final dB = GeoUtils.getDistanceMeters(origin, b.geo);
      return dA.compareTo(dB);
    });
    return candidatePool.first;
  }

  /// 감지 반경을 바꾸고 **기기에 저장한다.** 저장하지 않으면 다음 실행에서
  /// 기본값으로 돌아가 사용자가 고른 기준이 사라진다(추가 139).
  void updateRadius(double newRadiusMeters) {
    _settings = _settings.copyWith(radiusMeters: newRadiusMeters);
    _safeNotify();
    // 저장 실패가 화면을 막을 이유는 없다 — 이번 세션 동안은 이미 적용됐다.
    _proximitySettingsService.saveRadius(newRadiusMeters);
  }

  /// 지도에서 찍은 지점을 거리 기준으로 삼는다(F-13).
  ///
  /// 좌표는 화면에 그리고 거리 계산에만 쓴다 — **로그로 남기지 않는다.**
  /// 위치는 개인정보라 디버그 출력에도 위경도를 찍지 않는다.
  void setAnchor(GeoPosition position) {
    _anchorPosition = position;
    _safeNotify();
  }

  /// 기준점을 풀고 내 현재 위치로 되돌린다.
  void clearAnchor() {
    if (_anchorPosition == null) return;
    _anchorPosition = null;
    _safeNotify();
  }

  void setPreviewContact(ContactModel? contact) {
    _previewContact = contact;
    _safeNotify();
  }

  void openBriefing(ContactModel contact) {
    _selectedContactForBriefing = contact;
    _safeNotify();
  }

  void closeBriefing() {
    _selectedContactForBriefing = null;
    _safeNotify();
  }

  void updateContact(ContactModel contact) {
    _contactsRepository.updateContact(contact);
  }

  // --- F-10 A. 오늘 연락하면 좋은 사람 ---------------------------------
  //
  // 위치와 무관하다. 이 화면의 나머지는 "지금 내 주변"을 말하지만, 재연락은
  // "누굴 까먹었나"라서 GPS가 없어도(=filteredContacts가 비어도) 답할 수 있다.
  // 그래서 `_currentPosition`을 보지 않고 저장소 전체를 대상으로 한다.

  /// 오늘 연락하면 좋은 사람 목록. 순위·이유는 전부 기기 안에서 정해진다
  /// (AI 호출 없음, 서버 전송 없음).
  List<ReconnectCandidate> get reconnectCandidates =>
      ReconnectPriorityService.pick(
        contacts: _contactsRepository.contacts,
        now: DateTime.now(),
      );

  /// "이번엔 넘김" — 7일 뒤에 다시 후보가 된다. 아무것도 지우지 않는다.
  void snoozeReconnect(ContactModel contact) {
    _contactsRepository.updateContact(
      ReconnectPriorityService.applySnooze(
        contact: contact,
        now: DateTime.now(),
      ),
    );
  }
}
