import 'package:flutter/foundation.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/notification_settings.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../core/utils/geo_utils.dart';

class RadarViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  NotificationSettings _settings = const NotificationSettings();
  GeoPosition _currentPosition = GeoUtils.fallbackLocation;
  bool _isRefreshingLocation = false;
  ContactModel? _selectedContactForBriefing;
  ContactModel? _previewContact;

  RadarViewModel({required ContactsRepository contactsRepository})
      : _contactsRepository = contactsRepository {
    _contactsRepository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _contactsRepository.removeListener(notifyListeners);
    super.dispose();
  }

  NotificationSettings get settings => _settings;
  GeoPosition get currentPosition => _currentPosition;
  bool get isRefreshingLocation => _isRefreshingLocation;
  ContactModel? get selectedContactForBriefing => _selectedContactForBriefing;
  ContactModel? get previewContact => _previewContact;

  Future<void> refreshLocation() async {
    _isRefreshingLocation = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));

    // Refresh position around Yeoksam / Gangnam Tech Hub
    _currentPosition = const GeoPosition(lat: 37.5000, lng: 127.0360);
    _isRefreshingLocation = false;
    notifyListeners();
  }

  List<ContactModel> get filteredContacts {
    final contacts = _contactsRepository.contacts;
    final list = contacts.where((c) {
      if (c.geo == null) return false;
      final distance = GeoUtils.getDistanceMeters(_currentPosition, c.geo);
      return distance <= _settings.radiusMeters;
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
}
