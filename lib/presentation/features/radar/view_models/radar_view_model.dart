import 'package:flutter/foundation.dart';
import '../../../../core/services/location_consent_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/proximity_settings_service.dart';
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

    _isRefreshingLocation = false;
    _safeNotify();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    _safeNotify();
  }

  List<ContactModel> get filteredContacts {
    final currentPosition = _currentPosition;
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

  ContactModel? get nearbyAlertContact {
    if (_currentPosition == null) return null;
    final inRange = filteredContacts;
    if (inRange.isEmpty) return null;

    final priorities = inRange.where((c) => c.isPriority).toList();
    final candidatePool = priorities.isNotEmpty ? priorities : inRange;
    candidatePool.sort((a, b) {
      final dA = GeoUtils.getDistanceMeters(_currentPosition, a.geo);
      final dB = GeoUtils.getDistanceMeters(_currentPosition, b.geo);
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
}
