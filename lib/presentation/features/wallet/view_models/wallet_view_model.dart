import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/utils/korean_initial.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/contacts_repository.dart';

/// 명함지갑 정렬 기준.
enum ContactSort {
  /// 최근 등록순(기본) — id에 심긴 등록 시각 내림차순.
  recent,

  /// 이름 가나다순(한글 초성 → 가나다, 영문 등은 뒤).
  name,

  /// 회사명 가나다순(같은 회사는 이름순).
  company,

  /// 마지막 소통일 최신순 — 소통 기록(commLogs)의 가장 최근 시각 내림차순.
  /// 기록이 없는 인맥은 뒤로 보낸다.
  lastComm,
}

class WalletViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  String _searchTerm = '';
  List<String> _selectedTags = [];
  ContactSort _sort = ContactSort.recent;
  bool _isDisposed = false;

  static const String _sortPrefKey = 'wallet_sort_v1';

  WalletViewModel({required ContactsRepository contactsRepository})
    : _contactsRepository = contactsRepository {
    _contactsRepository.addListener(_onContactsChanged);
    _loadSort();
  }

  /// 저장해 둔 정렬 기준을 불러온다(앱 재실행에도 기억). 비동기라 로드가
  /// 끝나면 화면을 다시 그린다.
  Future<void> _loadSort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_sortPrefKey);
      if (saved == null) return;
      final match = ContactSort.values.where((e) => e.name == saved);
      if (match.isNotEmpty && match.first != _sort) {
        _sort = match.first;
        _safeNotify();
      }
    } catch (_) {
      // 저장소 접근 실패는 기본 정렬(최근등록순)로 두면 되므로 무시한다.
    }
  }

  Future<void> _saveSort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sortPrefKey, _sort.name);
    } catch (_) {}
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
  ContactSort get sort => _sort;
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
    final query = _searchTerm.trim().toLowerCase();
    final list = _contactsRepository.contacts.where((c) {
      final matchesSearch =
          query.isEmpty ||
          // 대소문자를 무시한다. 예전에는 그대로 비교해서 'SAMSUNG'으로 저장된
          // 회사명이 'samsung'으로는 검색되지 않았다(영문 회사명에서 흔한 일).
          c.name.toLowerCase().contains(query) ||
          c.company.toLowerCase().contains(query) ||
          c.title.toLowerCase().contains(query);

      final matchesTags =
          _selectedTags.isEmpty ||
          _selectedTags.any((tag) => c.tags.contains(tag));

      return matchesSearch && matchesTags;
    }).toList();

    switch (_sort) {
      case ContactSort.recent:
        // 새 명함 id는 등록 시각(millisecondsSinceEpoch)이라 그대로 내림차순
        // 정렬하면 최근 등록순이 된다. 숫자가 아닌 옛 id는 updatedAt으로 보완.
        list.sort((a, b) => _registeredAt(b).compareTo(_registeredAt(a)));
      case ContactSort.name:
        list.sort(_compareByName);
      case ContactSort.company:
        list.sort((a, b) {
          final byCompany = _compareByGroup(a.company, b.company);
          return byCompany != 0 ? byCompany : _compareByName(a, b);
        });
      case ContactSort.lastComm:
        // 마지막 소통이 최근일수록 위로. 기록 없는 인맥(0)은 자연히 맨 뒤.
        list.sort((a, b) => _lastCommAt(b).compareTo(_lastCommAt(a)));
    }
    return list;
  }

  /// 현재 정렬 기준에서 이 명함이 속한 초성 그룹(ㄱ/ㄴ/…/#). 인덱스 점프에
  /// 쓴다. 그룹 점프가 의미 없는 시간 기준 정렬(최근등록·소통일)에서는 빈
  /// 문자열.
  String sortGroupOf(ContactModel c) {
    switch (_sort) {
      case ContactSort.recent:
      case ContactSort.lastComm:
        return '';
      case ContactSort.name:
        return KoreanInitial.of(c.name);
      case ContactSort.company:
        return KoreanInitial.of(c.company);
    }
  }

  void setSort(ContactSort sort) {
    if (_sort == sort) return;
    _sort = sort;
    _safeNotify();
    unawaited(_saveSort());
  }

  /// 카드에 표시할 날짜와 그 의미 — **정렬 기준에 맞춘다**(사용자 요청).
  /// - 소통일순 → 마지막 소통일(라벨 "마지막 소통")
  /// - 그 외(최근등록순·이름순·회사명순) → 등록일(라벨 "등록")
  /// 값이 없으면 date=null → 카드에서 날짜를 숨긴다. 등록일은 id에 심긴 등록
  /// 시각(millisecondsSinceEpoch)에서 얻는다 — 모델에 별도 등록일 필드가 없다.
  ({DateTime? date, String label}) cardDateFor(ContactModel c) {
    if (_sort == ContactSort.lastComm) {
      final ms = _lastCommAt(c);
      return (
        date: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        label: '마지막 소통',
      );
    }
    final ms = _registeredAt(c);
    return (
      date: ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
      label: '등록',
    );
  }

  static int _registeredAt(ContactModel c) =>
      int.tryParse(c.id) ?? c.updatedAt?.millisecondsSinceEpoch ?? 0;

  /// 이 명함의 마지막 소통 시각(ms). 소통 기록이 없으면 0이라 소통일순에서
  /// 자연히 맨 뒤로 간다.
  static int _lastCommAt(ContactModel c) {
    var latest = 0;
    for (final log in c.commLogs) {
      final ms = log.timestamp.millisecondsSinceEpoch;
      if (ms > latest) latest = ms;
    }
    return latest;
  }

  int _compareByName(ContactModel a, ContactModel b) =>
      _compareByGroup(a.name, b.name);

  /// 한글 초성 그룹을 먼저(가나다순), 영문 등 '#' 그룹을 뒤로 보낸 뒤, 같은
  /// 그룹 안에서는 문자열 순서로 비교한다.
  int _compareByGroup(String a, String b) {
    final ra = KoreanInitial.rank(a);
    final rb = KoreanInitial.rank(b);
    if (ra != rb) return ra.compareTo(rb);
    return a.toLowerCase().compareTo(b.toLowerCase());
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

  /// 같은 전화번호로 이미 등록된 명함(있으면). 저장 전 중복 경고에 쓴다(P1-40).
  ContactModel? findDuplicateByPhone(String phone, {String? excludeId}) =>
      _contactsRepository.findByPhone(phone, excludeId: excludeId);

  void addContact(ContactModel contact) {
    _contactsRepository.addContact(contact);
  }

  void updateContact(ContactModel contact) {
    _contactsRepository.updateContact(contact);
  }

  void deleteContact(String id) {
    _contactsRepository.deleteContact(id);
  }

  /// 여러 명함을 한 번에 삭제한다(F-06 선택 삭제). 저장소의 단건 삭제를
  /// 순회 호출한다 — 각 호출이 tombstone·백업 삭제·기기 저장을 처리하므로
  /// 여기서 따로 할 일은 없다. 순회 중 목록이 바뀌므로 id를 먼저 확정한다.
  void deleteContacts(Iterable<String> ids) {
    for (final id in ids.toList()) {
      _contactsRepository.deleteContact(id);
    }
  }
}
