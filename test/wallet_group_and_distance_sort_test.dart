// 명함지갑 그룹 필터 + 정렬(추가 427) — 검색·그룹 필터·정렬 조합, 그리고
// 그룹 칩 선택을 기기에 기억할 때 **그룹 id만** 저장하는지(법무 검토 결론,
// 이름 문자열 금지)를 고정한다.
import 'dart:convert';

import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/core/utils/location_quality.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/wallet_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 위치 동의가 이미 수락돼 있고 항상 같은 좌표를 돌려주는 가짜.
class _AcceptedConsent implements LocationConsentStore {
  @override
  Future<LocationConsentRecord> loadRecord() async => const LocationConsentRecord(
    decision: LocationConsentDecision.accepted,
    recordedAt: null,
    policyVersion: LocationConsentService.currentPolicyVersion,
  );

  @override
  Future<LocationConsentRecord> accept() => loadRecord();

  @override
  Future<LocationConsentRecord> decline() async => const LocationConsentRecord(
    decision: LocationConsentDecision.declined,
    recordedAt: null,
    policyVersion: LocationConsentService.currentPolicyVersion,
  );
}

/// 동의가 아직 없는(기본) 가짜 — 실제 기기 기본 상태를 흉내낸다.
class _UnknownConsent implements LocationConsentStore {
  @override
  Future<LocationConsentRecord> loadRecord() async =>
      LocationConsentRecord.unknown;

  @override
  Future<LocationConsentRecord> accept() => loadRecord();

  @override
  Future<LocationConsentRecord> decline() => loadRecord();
}

class _FakeLocationGateway implements LocationGateway {
  final GeoPosition? position;

  _FakeLocationGateway({this.position});

  @override
  Future<DeviceLocationAccess> checkAccess() async =>
      DeviceLocationAccess.granted;

  @override
  Future<DeviceLocationAccess> requestPermission() async =>
      DeviceLocationAccess.granted;

  @override
  Future<GeoPosition?> getCurrentPosition() async => position;

  @override
  Future<bool> openAppPermissionSettings() async => true;

  @override
  Future<bool> openDeviceLocationSettings() async => true;

  @override
  LocationFixQuality get lastFixQuality => LocationFixQuality.unknown;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ContactModel contact(
    String id, {
    String name = '',
    List<String> groupIds = const [],
    GeoPosition? geo,
    List<CommunicationLogModel> commLogs = const [],
  }) => ContactModel(
    id: id,
    name: name.isEmpty ? '인맥$id' : name,
    company: '',
    title: '',
    phone: '010-0000-$id',
    email: '$id@test.com',
    tags: const [],
    talkingPoints: const [],
    groupIds: groupIds,
    geo: geo,
    commLogs: commLogs,
  );

  Future<WalletViewModel> vmWith(
    List<ContactModel> contacts, {
    LocationGateway? locationService,
    LocationConsentStore? locationConsentService,
  }) async {
    // ⚠️ wallet_search_test.dart의 기존 seed() 패턴은 List 필드를 전부 `[]`로
    // 뭉갠다(그 테스트는 목록 내용에 관심이 없어서 무해했다). 여기서는
    // groupIds가 실제로 왕복해야 그룹 필터를 검증할 수 있으므로 jsonEncode로
    // 정확히 직렬화한다.
    SharedPreferences.setMockInitialValues({
      'saved_contacts_v2': jsonEncode(contacts.map((c) => c.toJson()).toList()),
    });
    final repo = ContactsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return WalletViewModel(
      contactsRepository: repo,
      locationService: locationService,
      locationConsentService: locationConsentService,
    );
  }

  group('그룹 필터', () {
    test('그룹을 고르면 그 그룹 참조가 있는 명함만 남는다', () async {
      final vm = await vmWith([
        contact('1', groupIds: ['gA']),
        contact('2', groupIds: ['gB']),
        contact('3', groupIds: ['gA', 'gB']),
        contact('4'),
      ]);

      vm.setSelectedGroup('gA');

      expect(vm.filteredContacts.map((c) => c.id).toSet(), {'1', '3'});
    });

    test('"전체"(null)는 그룹 유무와 무관하게 전부 보여준다', () async {
      final vm = await vmWith([
        contact('1', groupIds: ['gA']),
        contact('2'),
      ]);

      vm.setSelectedGroup('gA');
      vm.setSelectedGroup(null);

      expect(vm.filteredContacts.map((c) => c.id).toSet(), {'1', '2'});
    });

    test('⭐ 검색 + 그룹 필터가 함께 조합돼야 한다(AND)', () async {
      final vm = await vmWith([
        contact('1', name: '홍길동', groupIds: ['gA']),
        contact('2', name: '홍길동', groupIds: ['gB']),
        contact('3', name: '김철수', groupIds: ['gA']),
      ]);

      vm.setSelectedGroup('gA');
      vm.setSearchTerm('홍길동');

      expect(vm.filteredContacts.map((c) => c.id).toList(), ['1']);
    });

    test('⚠️ 그룹 필터 선택은 shared_preferences에 id만 남고 이름은 없다', () async {
      final vm = await vmWith([contact('1', groupIds: ['g_secret_id'])]);

      vm.setSelectedGroup('g_secret_id');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('wallet_group_filter_v1');
      expect(saved, 'g_secret_id');
    });

    test('"전체"로 되돌리면 저장된 키가 지워진다', () async {
      final vm = await vmWith([contact('1', groupIds: ['gA'])]);
      vm.setSelectedGroup('gA');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      vm.setSelectedGroup(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wallet_group_filter_v1'), isNull);
    });

    test('앱을 다시 켜면 저장해 둔 그룹 필터가 복원된다', () async {
      SharedPreferences.setMockInitialValues({
        'saved_contacts_v2': jsonEncode(
          [contact('1', groupIds: ['gA']).toJson()],
        ),
        'wallet_group_filter_v1': 'gA',
      });
      final repo = ContactsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final vm = WalletViewModel(contactsRepository: repo);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.selectedGroupId, 'gA');
    });
  });

  group('가까운 거리순', () {
    test('⭐ 위치 동의·측위가 있으면 가까운 순으로 정렬된다', () async {
      final origin = const GeoPosition(lat: 37.5, lng: 127.0);
      final near = const GeoPosition(lat: 37.501, lng: 127.0); // 매우 가까움
      final far = const GeoPosition(lat: 37.9, lng: 127.5); // 멀리

      final vm = await vmWith(
        [
          contact('1', name: '먼사람', geo: far),
          contact('2', name: '가까운사람', geo: near),
        ],
        locationService: _FakeLocationGateway(position: origin),
        locationConsentService: _AcceptedConsent(),
      );

      vm.setSort(ContactSort.distance);
      // 비동기로 위치를 읽어오므로 한 번 기다린다.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.distanceSortAvailable, isTrue);
      expect(vm.filteredContacts.map((c) => c.id).toList(), ['2', '1']);
    });

    test('⭐ 위치 동의가 없으면 최근등록순으로 대신 정렬하고, 그 사실을 알린다', () async {
      final vm = await vmWith(
        [contact('1'), contact('2')],
        locationConsentService: _UnknownConsent(),
      );

      vm.setSort(ContactSort.distance);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.distanceSortAvailable, isFalse);
      expect(vm.distanceSortFallbackActive, isTrue);
      // id가 등록시각 역할을 하므로(추가 클수록 최근) 2, 1 순서가 최근등록순.
      expect(vm.filteredContacts.map((c) => c.id).toList(), ['2', '1']);
    });

    test('거리순 정렬은 그룹 필터와도 함께 동작한다', () async {
      final origin = const GeoPosition(lat: 37.5, lng: 127.0);
      final near = const GeoPosition(lat: 37.501, lng: 127.0);
      final far = const GeoPosition(lat: 37.9, lng: 127.5);

      final vm = await vmWith(
        [
          contact('1', geo: far, groupIds: ['gA']),
          contact('2', geo: near, groupIds: ['gA']),
          contact('3', geo: near, groupIds: ['gB']),
        ],
        locationService: _FakeLocationGateway(position: origin),
        locationConsentService: _AcceptedConsent(),
      );
      vm.setSort(ContactSort.distance);
      vm.setSelectedGroup('gA');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.filteredContacts.map((c) => c.id).toList(), ['2', '1']);
    });
  });

  // ⚠️ 2026-08-23 사용자 확정 — "기존 기능과 상충하면 갈아엎지 않고
  // 공존시킨다"(2026-08-20 원칙)에 따라 소통일순을 되살렸다. 정렬은 이제
  // 다섯 종(최근등록·이름·회사명·소통일·거리순)이고, 이 그룹은 소통일순이
  // 살아있는지 + 그룹 필터와도 조합되는지를 고정한다.
  group('소통일순 (복원, 2026-08-23)', () {
    CommunicationLogModel logAt(DateTime at) => CommunicationLogModel(
      type: 'call',
      summary: '',
      timestamp: at,
    );

    test('⭐ 다섯 종 정렬이 모두 존재한다', () {
      expect(ContactSort.values, hasLength(5));
      expect(
        ContactSort.values,
        containsAll(const [
          ContactSort.recent,
          ContactSort.name,
          ContactSort.company,
          ContactSort.lastComm,
          ContactSort.distance,
        ]),
      );
    });

    test('마지막 소통이 최근인 명함이 위로 온다', () async {
      final vm = await vmWith([
        contact('1', commLogs: [logAt(DateTime(2026, 1, 1))]),
        contact('2', commLogs: [logAt(DateTime(2026, 8, 1))]),
        contact('3'), // 소통 기록 없음 — 맨 뒤로.
      ]);

      vm.setSort(ContactSort.lastComm);

      expect(vm.filteredContacts.map((c) => c.id).toList(), ['2', '1', '3']);
    });

    test('소통일순도 그룹 필터와 함께 동작한다', () async {
      final vm = await vmWith([
        contact('1', groupIds: ['gA'], commLogs: [logAt(DateTime(2026, 1, 1))]),
        contact('2', groupIds: ['gA'], commLogs: [logAt(DateTime(2026, 8, 1))]),
        contact('3', groupIds: ['gB'], commLogs: [logAt(DateTime(2026, 9, 1))]),
      ]);

      vm.setSort(ContactSort.lastComm);
      vm.setSelectedGroup('gA');

      expect(vm.filteredContacts.map((c) => c.id).toList(), ['2', '1']);
    });
  });
}
