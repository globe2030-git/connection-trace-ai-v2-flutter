import 'package:flutter/foundation.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/notification_settings.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/services/location_service.dart';

class RadarViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  NotificationSettings _settings = const NotificationSettings();
  GeoPosition _currentPosition = GeoUtils.fallbackLocation;
  bool _isRefreshingLocation = false;
  bool _usingRealGps = false;
  ContactModel? _selectedContactForBriefing;
  ContactModel? _previewContact;
  String _searchTerm = '';

  RadarViewModel({required ContactsRepository contactsRepository})
      : _contactsRepository = contactsRepository {
    _contactsRepository.addListener(notifyListeners);
    // 화면이 뜨자마자 실제 GPS 위치를 한 번 시도한다. 권한이 없거나 위치
    // 서비스가 꺼져 있으면 LocationService가 null을 반환하므로 이 경우
    // 기존 fallback(강남역 기준) 좌표를 그대로 유지한 채 조용히 넘어간다.
    refreshLocation();
  }

  @override
  void dispose() {
    _contactsRepository.removeListener(notifyListeners);
    super.dispose();
  }

  NotificationSettings get settings => _settings;
  GeoPosition get currentPosition => _currentPosition;
  bool get isRefreshingLocation => _isRefreshingLocation;
  // 실제 GPS 좌표를 못 가져와 fallback(강남역 기준) 좌표를 쓰고 있는지 여부 —
  // 설정 화면 등에서 "위치 권한 필요" 안내를 보여줄 때 참고용.
  bool get usingRealGps => _usingRealGps;
  ContactModel? get selectedContactForBriefing => _selectedContactForBriefing;
  ContactModel? get previewContact => _previewContact;
  String get searchTerm => _searchTerm;

  void setSearchTerm(String term) {
    _searchTerm = term;
    notifyListeners();
  }

  Future<void> refreshLocation() async {
    _isRefreshingLocation = true;
    notifyListeners();

    final realPosition = await LocationService.getCurrentPosition();
    if (realPosition != null) {
      _currentPosition = realPosition;
      _usingRealGps = true;
    } else {
      _usingRealGps = false;
    }

    _isRefreshingLocation = false;
    notifyListeners();
  }

  List<ContactModel> get filteredContacts {
    final contacts = _contactsRepository.contacts;
    final query = _searchTerm.trim().toLowerCase();
    final list = contacts.where((c) {
      if (c.geo == null) return false;
      final distance = GeoUtils.getDistanceMeters(_currentPosition, c.geo);
      if (distance > _settings.radiusMeters) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          c.company.toLowerCase().contains(query) ||
          c.title.toLowerCase().contains(query);
    }).toList();

    // Primary: distance ascending (closest first), Secondary: Korean alphabetical (가나다순)
    list.sort((a, b) {
      final distA = GeoUtils.getDistanceMeters(_currentPosition, a.geo);
      final distB = GeoUtils.getDistanceMeters(_currentPosition, b.geo);

      final compDist = distA.compareTo(distB);
      if (compDist != 0) {
        return compDist;
      }
      return a.name.compareTo(b.name);
    });

    return list;
  }

  ContactModel? get nearbyAlertContact {
    if (!_settings.enabled) return null;
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

  void updateRadius(double newRadiusMeters) {
    _settings = _settings.copyWith(radiusMeters: newRadiusMeters);
    notifyListeners();
  }

  void updateBatteryMode(dynamic mode) {
    _settings = _settings.copyWith(batteryMode: mode);
    notifyListeners();
  }

  void setPreviewContact(ContactModel? contact) {
    _previewContact = contact;
    notifyListeners();
  }

  void openBriefing(ContactModel contact) {
    _selectedContactForBriefing = contact;
    notifyListeners();
  }

  void closeBriefing() {
    _selectedContactForBriefing = null;
    notifyListeners();
  }

  void togglePriority(String id) {
    _contactsRepository.togglePriority(id);
  }

  void toggleDetection() {
    _settings = _settings.copyWith(enabled: !_settings.enabled);
    notifyListeners();
  }

  void updateContact(ContactModel contact) {
    _contactsRepository.updateContact(contact);
  }
}
