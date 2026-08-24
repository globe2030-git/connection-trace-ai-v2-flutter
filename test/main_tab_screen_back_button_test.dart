import 'package:connection_trace_ai_flutter/core/services/location_consent_service.dart';
import 'package:connection_trace_ai_flutter/core/services/location_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/core/utils/location_quality.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/view_models/radar_view_model.dart';
import 'package:connection_trace_ai_flutter/presentation/navigation/main_tab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 추가 437 — 뒤로가기를 눌러도 앱이 종료되지 않고 화면만 닫혀 프로세스가
/// 최근 앱 목록에 그대로 남던 결함을 고치며 잠근 규칙.
///
/// 실제 화면(주변/명함/설정) 대신 [MainTabScreen.debugScreens]로 가벼운
/// 대역을 넣는다 — 설정 화면은 `FirebaseAuth.instance`를 직접 건드려
/// `flutter test`에서 Firebase 초기화 없이 렌더링할 수 없다
/// (`auth_repository_social_session_test.dart` 참고). 이 테스트가 잠그려는
/// 것은 "그 자리에 어떤 화면이 있든" 성립해야 하는 탭 전환·종료 로직 자체다.
///
/// 뒤로가기는 시스템 back 제스처와 같은 경로(`NavigatorState.maybePop`)로
/// 흉내 낸다 — Flutter의 `PopScope` 자체 테스트(`pop_scope_test.dart`)도
/// 같은 방식을 쓴다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<RadarViewModel> readyModel(WidgetTester tester) async {
    late RadarViewModel model;
    await tester.runAsync(() async {
      model = RadarViewModel(
        contactsRepository: ContactsRepository(),
        locationService: _FakeLocationGateway(),
        locationConsentService: _FakeConsentStore(
          LocationConsentRecord.unknown,
        ),
      );
      await model.initialization;
    });
    return model;
  }

  ContactModel testContact() => const ContactModel(
    id: 'c1',
    name: '테스트',
    company: '',
    title: '',
    phone: '',
    email: '',
    tags: [],
    talkingPoints: [],
  );

  Future<void> pumpMainTab(
    WidgetTester tester,
    RadarViewModel model, {
    required Future<void> Function() onExit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<RadarViewModel>.value(
          value: model,
          child: MainTabScreen(
            debugScreens: const [
              Center(child: Text('탭0-주변')),
              Center(child: Text('탭1-명함')),
              Center(child: Text('탭2-설정')),
            ],
            debugExitApp: onExit,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 안드로이드 뒤로가기 한 번을 흉내 낸다.
  Future<void> pressBack(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
  }

  testWidgets('ⓐ 두 번째 탭에서 뒤로가기 → 첫 탭으로 돌아가고 종료하지 않는다', (
    tester,
  ) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    await tester.tap(find.text('명함'));
    await tester.pump();
    expect(find.text('탭1-명함'), findsOneWidget);

    await pressBack(tester);

    expect(
      find.text('탭0-주변'),
      findsOneWidget,
      reason: '뒤로가기는 종료가 아니라 먼저 첫 탭으로 돌아가야 한다(안드로이드 관례)',
    );
    expect(exitCount, 0, reason: '탭 전환 단계에서는 아직 종료하면 안 된다');

    model.dispose();
  });

  testWidgets('ⓐ 세 번째 탭에서 뒤로가기 → 첫 탭으로 돌아가고 종료하지 않는다', (
    tester,
  ) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    await tester.tap(find.text('설정'));
    await tester.pump();
    expect(find.text('탭2-설정'), findsOneWidget);

    await pressBack(tester);

    expect(find.text('탭0-주변'), findsOneWidget);
    expect(exitCount, 0);

    model.dispose();
  });

  testWidgets('ⓑ 첫 탭에서 한 번 누르면 안내만 뜨고 종료하지 않는다', (tester) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    await pressBack(tester);

    expect(find.text('한 번 더 누르면 종료됩니다.'), findsOneWidget);
    expect(exitCount, 0, reason: '한 번만 눌렀을 때는 종료하면 안 된다');

    model.dispose();
  });

  testWidgets('ⓒ 2초 안에 두 번 누르면 종료 경로가 호출된다', (tester) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    await pressBack(tester);
    expect(find.text('한 번 더 누르면 종료됩니다.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await pressBack(tester);

    expect(exitCount, 1, reason: '2초 안에 다시 누르면 종료 경로가 정확히 한 번 불려야 한다');

    model.dispose();
  });

  testWidgets('ⓓ 2초가 지난 뒤 다시 누르면 다시 안내부터 뜨고 즉시 종료하지 않는다', (
    tester,
  ) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    await pressBack(tester);
    expect(find.text('한 번 더 누르면 종료됩니다.'), findsOneWidget);

    // 두 번 누르기 창(2초)이 지나가도록 흘려 보낸다. 한 번에 크게
    // 점프시키지 않고 잘게 끊는 이유: 이 화면의 "두 번 눌러야 종료" 타이머
    // (`_exitArmTimer`)와 별개로 `SnackBar` 자체도 내부 타이머로 퇴장
    // 애니메이션을 갖고 있는데, 그건 진입 애니메이션이 완료된 뒤에야
    // 잡힌다(`ScaffoldMessengerState.build` 참고) — 점프 한 번으로는 "진입
    // 완료 → 타이머 등록"과 "그 타이머가 실제로 울림"이 같은 프레임에 함께
    // 끝나지 않는다. 이 테스트가 잠그려는 것은 스낵바의 퇴장 타이밍이
    // 아니라 **이 화면 자신의 재무장 여부**라, 스낵바가 화면에 남아 있는지는
    // 따지지 않는다 — 같은 문구를 다시 `showSnackBar`로 띄워도 큐에 이어
    // 붙을 뿐 문구 자체는 계속 하나만 보이므로 아래 확인은 영향받지 않는다.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    await pressBack(tester);

    expect(
      exitCount,
      0,
      reason: '2초가 지나면 다시 눌러도 즉시 종료가 아니라 안내부터 다시 떠야 한다',
    );
    expect(find.text('한 번 더 누르면 종료됩니다.'), findsOneWidget);

    model.dispose();
  });

  testWidgets('AI 대화 브리핑 오버레이가 열려 있으면 루트 뒤로가기가 탭 전환·종료로 새지 않는다', (
    tester,
  ) async {
    final model = await readyModel(tester);
    var exitCount = 0;
    await pumpMainTab(tester, model, onExit: () async => exitCount++);

    // 실물 BriefingOverlayView 없이도(대역 화면이라 안 그려진다) 이 화면이
    // RadarViewModel의 상태만 보고 판단하는지를 확인한다 — 실제 오버레이
    // 쪽 PopScope와의 이중 처리는 radar_view.dart에 별도로 붙어 있고, 여기서
    // 잠그는 것은 "MainTabScreen이 오버레이가 열린 걸 알면 자기 로직을
    // 건너뛴다"는 이 화면만의 책임이다.
    model.openBriefing(testContact());
    await tester.pump();

    await pressBack(tester);

    expect(exitCount, 0, reason: '오버레이가 열려 있으면 종료로 새면 안 된다');
    expect(
      find.text('한 번 더 누르면 종료됩니다.'),
      findsNothing,
      reason: '오버레이가 열려 있으면 종료 안내도 뜨면 안 된다 — 오버레이 쪽이 뒤로가기를 가져간다',
    );
    expect(
      find.text('탭0-주변'),
      findsOneWidget,
      reason: '탭도 그대로여야 한다(원래도 첫 탭이었지만, 전환 로직 자체가 안 타야 한다는 뜻)',
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
