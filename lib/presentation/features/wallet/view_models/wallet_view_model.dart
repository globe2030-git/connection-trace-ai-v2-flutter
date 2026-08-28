import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/location_consent_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/korean_initial.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/contacts_repository.dart';

/// 명함지갑 정렬 기준.
///
/// ⚠️ 2026-08-23 사용자 확정(기존 기능과 상충하면 갈아엎지 않고 공존시킨다,
/// 2026-08-20 원칙): 추가 427 착수 때 "소통일순"을 캔버스 확정안(최근등록·
/// 이름·회사명·거리순 넷)에 맞춰 지웠는데, 그건 기존 기능 축소라 원칙에
/// 안 맞는다는 지적을 받고 되살렸다. 지금은 **다섯 종**이다 — 캔버스 넷 +
/// 기존 소통일순.
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

  /// 가까운 거리순(추가 427) — 내 현재 위치에서 가까운 순. [WalletViewModel.
  /// distanceSortAvailable]가 false면(위치 동의가 없거나 아직 측위 전) 최근
  /// 등록순으로 대신 정렬한다([distanceSortFallbackActive]로 화면에 알린다).
  distance,
}

class WalletViewModel extends ChangeNotifier {
  final ContactsRepository _contactsRepository;
  final LocationGateway _locationService;
  final LocationConsentStore _locationConsentService;
  String _searchTerm = '';
  List<String> _selectedTags = [];
  // 그룹 필터(추가 427) — null이면 "전체". [ContactModel.groupIds]에 이
  // id가 있는 명함만 남긴다.
  String? _selectedGroupId;
  ContactSort _sort = ContactSort.recent;
  bool _isDisposed = false;

  // "가까운 거리순" 정렬의 기준 위치. 주변 탭([RadarViewModel])과 달리 여기서는
  // **새로 위치 동의·권한을 요청하지 않는다** — 이미 동의·권한이 있을 때만
  // 조용히 읽어 쓴다. 명함지갑에서 처음 위치 동의 팝업을 띄우면 그 화면의
  // 맥락(주변 인맥 감지)과 다른 곳에서 낯선 팝업이 뜨는 셈이라, 동의가 아직
  // 없으면 [distanceSortFallbackActive]로 대체 정렬(최근등록순) 중임을
  // 알리기만 한다.
  GeoPosition? _distanceOrigin;
  bool _distanceOriginLoading = false;

  static const String _sortPrefKey = 'wallet_sort_v1';
  // ⚠️ 그룹 "이름"이 아니라 id만 저장한다(법무 검토 결론) — 그룹명은
  // 제3자를 특정할 수 있는 값이라 암호화 안 되는 일반 shared_preferences
  // 키에 원문을 넣지 않는다(CLAUDE.md 4절).
  static const String _groupFilterPrefKey = 'wallet_group_filter_v1';

  WalletViewModel({
    required ContactsRepository contactsRepository,
    LocationGateway? locationService,
    LocationConsentStore? locationConsentService,
  }) : _contactsRepository = contactsRepository,
       _locationService = locationService ?? LocationService(),
       _locationConsentService =
           locationConsentService ?? LocationConsentService() {
    _contactsRepository.addListener(_onContactsChanged);
    _loadSort();
    _loadGroupFilter();
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
        if (_sort == ContactSort.distance) unawaited(_maybeLoadDistanceOrigin());
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

  Future<void> _loadGroupFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_groupFilterPrefKey);
      if (saved == null || saved.isEmpty) return;
      _selectedGroupId = saved;
      _safeNotify();
    } catch (_) {
      // 저장소 접근 실패는 "전체"로 두면 되므로 무시한다.
    }
  }

  Future<void> _saveGroupFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = _selectedGroupId;
      if (id == null) {
        await prefs.remove(_groupFilterPrefKey);
      } else {
        await prefs.setString(_groupFilterPrefKey, id);
      }
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
  String? get selectedGroupId => _selectedGroupId;

  /// "가까운 거리순"을 실제로 쓸 수 있는지(위치 동의·권한·측위가 이미 돼
  /// 있는지). false면 화면에서 최근등록순으로 대신 보여주고 있다는 뜻이다.
  bool get distanceSortAvailable => _distanceOrigin != null;

  /// 지금 "가까운 거리순"을 골랐지만 위치 기준이 없어 최근등록순으로 대신
  /// 보여주는 중인지 — 화면의 안내 한 줄에 쓴다.
  bool get distanceSortFallbackActive =>
      _sort == ContactSort.distance && _distanceOrigin == null;

  // 검색/태그/그룹 필터와 무관한 전체 목록 — 중복 인맥(휴대폰 번호 일치)
  // 검사처럼 필터링된 filteredContacts로는 놓칠 수 있는 조회에 쓴다.
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
    final groupId = _selectedGroupId;
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

      final matchesGroup = groupId == null || c.groupIds.contains(groupId);

      return matchesSearch && matchesTags && matchesGroup;
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
      case ContactSort.distance:
        final origin = _distanceOrigin;
        if (origin == null) {
          // 위치 기준이 없으면 최근등록순으로 대신 보여준다
          // (distanceSortFallbackActive가 true인 동안).
          list.sort((a, b) => _registeredAt(b).compareTo(_registeredAt(a)));
        } else {
          list.sort((a, b) {
            final dA = GeoUtils.getDistanceMeters(origin, a.geo);
            final dB = GeoUtils.getDistanceMeters(origin, b.geo);
            final cmp = dA.compareTo(dB);
            return cmp != 0 ? cmp : _compareByName(a, b);
          });
        }
    }
    return list;
  }

  /// 현재 정렬 기준에서 이 명함이 속한 초성 그룹(ㄱ/ㄴ/…/#). 인덱스 점프에
  /// 쓴다. 그룹 점프가 의미 없는 정렬(최근등록·소통일·거리)에서는 빈 문자열.
  String sortGroupOf(ContactModel c) {
    switch (_sort) {
      case ContactSort.recent:
      case ContactSort.lastComm:
      case ContactSort.distance:
        return '';
      case ContactSort.name:
        return KoreanInitial.of(c.name);
      case ContactSort.company:
        return KoreanInitial.of(c.company);
    }
  }

  void setSort(ContactSort sort) {
    if (_sort == sort) {
      if (sort == ContactSort.distance) unawaited(_maybeLoadDistanceOrigin());
      return;
    }
    _sort = sort;
    _safeNotify();
    unawaited(_saveSort());
    if (sort == ContactSort.distance) unawaited(_maybeLoadDistanceOrigin());
  }

  /// 위치 동의·권한이 **이미 있을 때만** 조용히 현재 위치를 읽는다. 새로
  /// 동의를 구하거나 OS 권한 팝업을 띄우지 않는다(주변 탭의 몫) — 명함지갑은
  /// 그 흐름을 대신하지 않는다.
  Future<void> _maybeLoadDistanceOrigin() async {
    if (_distanceOrigin != null || _distanceOriginLoading) return;
    _distanceOriginLoading = true;
    try {
      final consent = await _locationConsentService.loadRecord();
      if (consent.decision != LocationConsentDecision.accepted) return;
      final access = await _locationService.checkAccess();
      if (access != DeviceLocationAccess.granted) return;
      final position = await _locationService.getCurrentPosition();
      if (position == null) return;
      _distanceOrigin = position;
      _safeNotify();
    } catch (_) {
      // 실패해도 거리 정렬은 최근등록순 대체로 계속 동작한다.
    } finally {
      _distanceOriginLoading = false;
    }
  }

  /// 카드에 표시할 날짜와 그 의미 — **정렬 기준에 맞춘다**(사용자 요청).
  /// - 소통일순 → 마지막 소통일(라벨 "마지막 소통")
  /// - 그 외(최근등록순·이름순·회사명순·거리순) → 등록일(라벨 "등록") —
  ///   거리순도 어차피 표시할 다른 날짜가 없어 등록일을 그대로 보여준다.
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

  /// 그룹 칩 필터를 바꾼다(추가 427). `null`이면 "전체".
  void setSelectedGroup(String? groupId) {
    if (_selectedGroupId == groupId) return;
    _selectedGroupId = groupId;
    _safeNotify();
    unawaited(_saveGroupFilter());
  }

  /// 같은 사람으로 볼 만한 명함(있으면). 저장 전 중복 경고에 쓴다(P1-40).
  ///
  /// 휴대폰끼리 · 이메일 완전 일치 · (번호가 양쪽 다 없을 때만) 이름+회사를
  /// 본다. **사무실·직통·팩스는 보지 않는다** — 대표번호는 같은 회사 사람
  /// 여럿이 공유한다(사용자 확정 2026-08-26).
  /// 같은 주소를 가진 명함의 좌표(등록 화면이 저장 직전에 본다).
  /// 판정은 저장소 한 곳에만 둔다 — 여기서 다시 세지 않는다.
  GeoPosition? geoForSameAddress(String address) =>
      _contactsRepository.geoForSameAddress(address);

  DuplicateMatch? findDuplicate({
    required String phone,
    String? email,
    String? name,
    String? company,
    String? excludeId,
  }) => _contactsRepository.findDuplicate(
    phone: phone,
    email: email,
    name: name,
    company: company,
    excludeId: excludeId,
  );

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
