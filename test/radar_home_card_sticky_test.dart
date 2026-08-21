import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/core/utils/location_quality.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/my_profile_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/view_models/radar_view_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/views/radar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 주변 탭 목록 상단 고정(브리프 ⑦)과 주변 홈 지도 카드(⑥-C)가 실제 화면에서
/// 회귀 없이 동작하는지 본다. 접힘 자체의 규칙은 `collapsing_list_header_test.dart`가
/// 이미 보고, 점 배치 계산은 `nearby_map_layout_test.dart`가 이미 보므로,
/// 여기서는 **주변 화면과 결합했을 때** — 스크롤로 실제 접히는지, 검색 중
/// 상태(F-11)·기준점 안내(F-13)·지역 구획(#401)과 겹치지 않는지만 본다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const origin = GeoPosition(lat: 37.5665, lng: 126.9780);

  ContactModel contactNear(int i) => ContactModel(
    id: 'c$i',
    name: '인맥$i',
    company: '회사$i',
    title: '',
    phone: '010-0000-${i.toString().padLeft(4, '0')}',
    email: 'c$i@test.com',
    tags: const [],
    talkingPoints: const [],
    // 위도를 조금씩 벌려 서로 다른 거리를 만든다(같은 주소 묶음 X).
    geo: GeoPosition(lat: origin.lat + 0.001 * i, lng: origin.lng),
  );

  LocationConsentRecord acceptedConsent() => LocationConsentRecord(
    decision: LocationConsentDecision.accepted,
    recordedAt: DateTime(2026, 8, 21),
    policyVersion: LocationConsentService.currentPolicyVersion,
  );

  Future<RadarViewModel> readyModel(
    WidgetTester tester, {
    int contactCount = 30,
  }) async {
    late RadarViewModel model;
    await tester.runAsync(() async {
      final repository = ContactsRepository();
      for (var i = 0; i < contactCount; i++) {
        repository.addContact(contactNear(i));
      }
      final gateway = _FakeLocationGateway()
        ..checkResult = DeviceLocationAccess.granted
        ..position = origin;
      model = RadarViewModel(
        contactsRepository: repository,
        locationService: gateway,
        locationConsentService: _FakeConsentStore(acceptedConsent()),
      );
      await model.initialization;
      // "전체"로 둬야 반경 계산에 상관없이 30명이 모두 목록에 들어가
      // 스크롤할 내용이 충분해진다.
      model.updateRadius(double.infinity);
    });
    return model;
  }

  Future<void> pumpRadar(WidgetTester tester, RadarViewModel model) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<RadarViewModel>.value(value: model),
            ChangeNotifierProvider<MyProfileRepository>(
              create: (_) => MyProfileRepository(),
            ),
          ],
          child: const RadarView(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 지갑 화면 테스트(`wallet_sticky_header_test.dart`)와 같은 이유로
  /// `jumpTo` + 고정 프레임만 넘긴다 — 실제 손가락 제스처의 물리는 이
  /// 테스트의 관심사가 아니고, `fling`은 관성 스크롤 때문에
  /// `pumpAndSettle`이 실질적으로 끝나지 않는다.
  Future<void> scrollDown(WidgetTester tester) async {
    final listElement = find.byType(Scrollable).evaluate().firstWhere(
      (e) => e.findAncestorWidgetOfExactType<EditableText>() == null,
    );
    final scrollable = (listElement as StatefulElement).state as ScrollableState;
    scrollable.position.jumpTo(400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('⭐ 맨 위에서는 큰 제목이 보이고, 내리면 축약형으로 접힌다', (tester) async {
    final model = await readyModel(tester);
    await pumpRadar(tester, model);

    expect(
      find.text('주변 인맥'),
      findsOneWidget,
      reason: '펼친 상태에서는 축약 제목 줄이 아직 없어 "주변 인맥"이 한 번만 보인다',
    );
    expect(find.text('주변'), findsNothing, reason: '접히기 전에는 축약 제목이 없다');

    await scrollDown(tester);

    expect(
      find.text('주변 인맥'),
      findsNothing,
      reason: '큰 제목은 접으면 흘려보낸다',
    );
    expect(find.text('주변'), findsOneWidget, reason: '축약 제목으로 바뀐다');
    expect(find.textContaining('가까운'), findsWidgets, reason: '축약 줄의 개수 배지');

    model.dispose();
  });

  testWidgets('⭐ 접혀도 검색창과 반경·지도 칩은 계속 쓸 수 있다(브리프 ⑦ "고정")', (
    tester,
  ) async {
    final model = await readyModel(tester);
    await pumpRadar(tester, model);

    await scrollDown(tester);

    expect(
      find.text('주변 인맥 중에서 검색'),
      findsOneWidget,
      reason: '검색창은 "고정" — 접혀도 남아 있어야 한다',
    );
    expect(find.text('지도'), findsOneWidget, reason: '지도 버튼도 축약 제목 줄로 옮겨 붙어 남는다');

    // 검색이 접힌 상태에서도 실제로 동작하는지까지 확인한다. "인맥25"를
    // 쓰는 이유: "인맥1"로 검색하면 인맥1·10~19가 전부 걸려 결과가 하나가
    // 아니게 된다 — 부분 일치 검색이라 겹치지 않는 숫자를 골라야 한다.
    await tester.enterText(find.byType(TextField), '인맥25');
    await tester.pump();
    expect(find.text('회사25'), findsOneWidget, reason: '검색어와 겹치지 않는 회사명으로 결과를 확인한다');
    expect(find.text('회사26'), findsNothing);

    model.dispose();
  });

  testWidgets('F-11 — 검색 중에는 지도 카드가 숨는다', (tester) async {
    final model = await readyModel(tester);
    await pumpRadar(tester, model);

    expect(
      find.textContaining('거리·방향 기준 표시'),
      findsOneWidget,
      reason: '평소에는 ⑥-C 카드의 과장 금지 문구가 보인다',
    );

    // "인맥25"는 0~29 중 겹치는 숫자가 없어 결과가 정확히 1명이 된다.
    model.setSearchTerm('인맥25');
    await tester.pump();

    expect(
      find.textContaining('거리·방향 기준 표시'),
      findsNothing,
      reason: '검색 중에는 지도 카드 자체가 F-11 규칙대로 숨는다',
    );
    expect(find.text('검색 결과 (1명)'), findsOneWidget);

    model.dispose();
  });

  testWidgets('F-13 — 지도에서 지정한 기준점 안내는 검색 중에도 남는다', (tester) async {
    final model = await readyModel(tester);
    await pumpRadar(tester, model);

    model.setAnchor(const GeoPosition(lat: 37.4979, lng: 127.0276));
    await tester.pump();

    expect(find.textContaining('지정한 위치 기준으로'), findsOneWidget);

    model.setSearchTerm('인맥1');
    await tester.pump();

    expect(
      find.textContaining('지정한 위치 기준으로'),
      findsOneWidget,
      reason: 'F-13 안내는 "지금 내 주변이 어떤가"가 아니라 "무엇을 기준으로 쟀는가"라 검색 중에도 남아야 한다',
    );

    model.dispose();
  });

  testWidgets('목록이 검색으로 다 걸러지면 접힌 채로 남지 않는다', (tester) async {
    final model = await readyModel(tester);
    await pumpRadar(tester, model);

    await scrollDown(tester);
    expect(find.text('주변 인맥'), findsNothing, reason: '접힘 확인');

    model.setSearchTerm('존재하지않는이름');
    await tester.pump();

    expect(find.textContaining('일치하는 주변 인맥이 없어요'), findsOneWidget);
    expect(
      find.text('주변 인맥'),
      findsOneWidget,
      reason: '검색 결과가 텅 비면 스크롤할 목록이 거의 없어 머리글이 강제로 펴져야 한다',
    );

    model.dispose();
  });

  testWidgets('#401 — 좌표 없는 명함의 지역 구획이 머리글 고정과 함께 있어도 보인다', (
    tester,
  ) async {
    late RadarViewModel model;
    await tester.runAsync(() async {
      final repository = ContactsRepository()
        ..addContact(
          ContactModel(
            id: 'no-geo',
            name: '주소만 있음',
            company: '',
            title: '',
            phone: '',
            email: '',
            address: '서울특별시 강남구 테헤란로 1',
            tags: const [],
            talkingPoints: const [],
          ),
        );
      final gateway = _FakeLocationGateway()
        ..checkResult = DeviceLocationAccess.granted
        ..position = origin;
      model = RadarViewModel(
        contactsRepository: repository,
        locationService: gateway,
        locationConsentService: _FakeConsentStore(acceptedConsent()),
      );
      await model.initialization;
    });

    await pumpRadar(tester, model);

    expect(find.textContaining('위치를 못 찾은 인맥'), findsOneWidget);
    // 연락이 없던 유일한 인맥이라 "오늘 연락하면 좋은 사람"(F-10 A) 후보로도
    // 함께 뜬다 — 지역 구획과 재연락 섹션 둘 다 같은 이름을 보여주는 것이
    // 정상이라 findsOneWidget이 아니라 findsWidgets로 본다.
    expect(find.text('주소만 있음'), findsWidgets);

    model.dispose();
  });

  testWidgets('⑥-C — 위치 동의가 없으면 지도 카드가 빈 상태 문구를 보여준다', (tester) async {
    late RadarViewModel model;
    await tester.runAsync(() async {
      final repository = ContactsRepository();
      model = RadarViewModel(
        contactsRepository: repository,
        locationService: _FakeLocationGateway(),
        locationConsentService: _FakeConsentStore(LocationConsentRecord.unknown),
      );
      await model.initialization;
    });

    await pumpRadar(tester, model);

    expect(
      find.textContaining('위치를 사용하면 주변 인맥을'),
      findsOneWidget,
      reason: '위치 동의가 없을 때는 가짜 점을 찍지 않고 빈 상태 문구를 보여준다',
    );

    model.dispose();
  });
}

class _FakeLocationGateway implements LocationGateway {
  @override
  LocationFixQuality lastFixQuality = LocationFixQuality.unknown;

  DeviceLocationAccess checkResult = DeviceLocationAccess.denied;
  DeviceLocationAccess requestResult = DeviceLocationAccess.denied;
  GeoPosition? position;

  @override
  Future<DeviceLocationAccess> checkAccess() async => checkResult;

  @override
  Future<DeviceLocationAccess> requestPermission() async => requestResult;

  @override
  Future<GeoPosition?> getCurrentPosition() async => position;

  @override
  Future<bool> openAppPermissionSettings() async => true;

  @override
  Future<bool> openDeviceLocationSettings() async => true;
}

class _FakeConsentStore implements LocationConsentStore {
  _FakeConsentStore(this.record);

  LocationConsentRecord record;

  @override
  Future<LocationConsentRecord> loadRecord() async => record;

  @override
  Future<LocationConsentRecord> accept() async {
    record = LocationConsentRecord(
      decision: LocationConsentDecision.accepted,
      recordedAt: DateTime(2026, 8, 21),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }

  @override
  Future<LocationConsentRecord> decline() async {
    record = LocationConsentRecord(
      decision: LocationConsentDecision.declined,
      recordedAt: DateTime(2026, 8, 21),
      policyVersion: LocationConsentService.currentPolicyVersion,
    );
    return record;
  }
}
