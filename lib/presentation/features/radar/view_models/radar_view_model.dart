import 'package:flutter/foundation.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/notification_settings.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../core/utils/geo_utils.dart';

class RadarViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  NotificationSettings _settings = const NotificationSettings();
  GeoPosition _currentPosition = GeoUtils.fallbackLocation;
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
  ContactModel? get selectedContactForBriefing => _selectedContactForBriefing;
  ContactModel? get previewContact => _previewContact;

  List<ContactModel> get filteredContacts {
    final contacts = _contactsRepository.contacts;
    return contacts.where((c) {
      if (c.geo == null) return false;
      final distance = GeoUtils.getDistanceMeters(_currentPosition, c.geo);
      return distance <= _settings.radiusMeters;
    }).toList();
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
}
