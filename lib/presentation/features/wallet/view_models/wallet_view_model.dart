import 'package:flutter/foundation.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/contacts_repository.dart';

class WalletViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  String _searchTerm = '';
  List<String> _selectedTags = [];

  WalletViewModel({required ContactsRepository contactsRepository})
      : _contactsRepository = contactsRepository {
    _contactsRepository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _contactsRepository.removeListener(notifyListeners);
    super.dispose();
  }

  String get searchTerm => _searchTerm;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);

  List<String> get allTags {
    final tagsSet = <String>{};
    for (var c in _contactsRepository.contacts) {
      tagsSet.addAll(c.tags);
    }
    return tagsSet.toList();
  }

  List<ContactModel> get filteredContacts {
    return _contactsRepository.contacts.where((c) {
      final matchesSearch = _searchTerm.isEmpty ||
          c.name.contains(_searchTerm) ||
          c.company.contains(_searchTerm) ||
          c.title.contains(_searchTerm);

      final matchesTags = _selectedTags.isEmpty ||
          _selectedTags.any((tag) => c.tags.contains(tag));

      return matchesSearch && matchesTags;
    }).toList();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    notifyListeners();
  }

  void toggleTag(String tag) {
    if (_selectedTags.contains(tag)) {
      _selectedTags.remove(tag);
    } else {
      _selectedTags.add(tag);
    }
    notifyListeners();
  }

  void togglePriority(String id) {
    _contactsRepository.togglePriority(id);
  }

  void addContact(ContactModel contact) {
    _contactsRepository.addContact(contact);
  }

  void updateContact(ContactModel contact) {
    _contactsRepository.updateContact(contact);
  }

  void deleteContact(String id) {
    _contactsRepository.deleteContact(id);
  }
}
