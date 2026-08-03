import 'package:flutter/foundation.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/contacts_repository.dart';

class WalletViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  String _searchTerm = '';
  List<String> _selectedTags = [];
  bool _isDisposed = false;

  WalletViewModel({required ContactsRepository contactsRepository})
    : _contactsRepository = contactsRepository {
    _contactsRepository.addListener(_onContactsChanged);
  }

  void _onContactsChanged() => _safeNotify();

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _contactsRepository.removeListener(_onContactsChanged);
    super.dispose();
  }

  String get searchTerm => _searchTerm;
  List<String> get selectedTags => List.unmodifiable(_selectedTags);
  // 검색/태그 필터와 무관한 전체 목록 — 중복 인맥(휴대폰 번호 일치) 검사처럼
  // 필터링된 filteredContacts로는 놓칠 수 있는 조회에 쓴다.
  List<ContactModel> get contacts => _contactsRepository.contacts;

  List<String> get allTags {
    final tagsSet = <String>{};
    for (var c in _contactsRepository.contacts) {
      tagsSet.addAll(c.tags);
    }
    return tagsSet.toList();
  }

  List<ContactModel> get filteredContacts {
    return _contactsRepository.contacts.where((c) {
      final matchesSearch =
          _searchTerm.isEmpty ||
          c.name.contains(_searchTerm) ||
          c.company.contains(_searchTerm) ||
          c.title.contains(_searchTerm);

      final matchesTags =
          _selectedTags.isEmpty ||
          _selectedTags.any((tag) => c.tags.contains(tag));

      return matchesSearch && matchesTags;
    }).toList();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    _safeNotify();
  }

  void toggleTag(String tag) {
    if (_selectedTags.contains(tag)) {
      _selectedTags.remove(tag);
    } else {
      _selectedTags.add(tag);
    }
    _safeNotify();
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
