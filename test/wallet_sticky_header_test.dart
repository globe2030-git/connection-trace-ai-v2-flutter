import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/groups_view_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/wallet_view_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/wallet_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 명함 지갑 목록 상단 고정(UI 개선 ⑦, 2026-08-21)이 실제 화면에서
/// 회귀 없이 동작하는지 본다. 접힘 자체의 규칙은
/// `collapsing_list_header_test.dart`가 이미 보므로, 여기서는 **지갑
/// 화면과 결합했을 때** — 스크롤로 실제 접히는지, 선택 모드(F-06)와
/// 겹치지 않는지, 검색이 계속 되는지만 본다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ContactModel contact(int i) => ContactModel(
    id: 'c$i',
    name: '인맥$i',
    company: '회사$i',
    title: '',
    phone: '010-0000-${i.toString().padLeft(4, '0')}',
    email: 'c$i@test.com',
    tags: const [],
    talkingPoints: const [],
  );

  /// 로그인 전(uid 없음) 평문 저장 형식 — wallet_search_test.dart와 동일한
  /// 방식으로 목록을 심는다.
  ///
  /// ⚠️ `ContactsRepository()`가 내부에서 진짜 `Future.delayed`를 기다리는데,
  /// `testWidgets` 안에서는 `tester.runAsync`로 감싸지 않으면 그 대기가
  /// 절대 안 끝난다(자동화 테스트 바인딩은 가짜 시간만 흘려보내고, `pump`를
  /// 아직 한 번도 안 부른 시점이라 그 가짜 시계조차 안 움직인다) — 실제로
  /// 겪은 무한 대기(2026-08-21), `wallet_search_test.dart`는 `testWidgets`가
  /// 아니라 `test`라 같은 코드가 문제없이 동작했던 것이었다.
  // WalletView가 이제 GroupsViewModel도 본다(추가 427 — 상단 그룹 칩).
  // WalletViewModel과 같은 ContactsRepository 인스턴스를 공유해야
  // 명함 목록이 어긋나지 않는다.
  Future<({WalletViewModel wallet, GroupsViewModel groups})> viewModelWith(
    WidgetTester tester,
    List<ContactModel> contacts,
  ) async {
    final entries = contacts.map((c) {
      final j = c.toJson();
      final parts = j.entries.map((e) {
        final v = e.value;
        if (v == null) return '"${e.key}":null';
        if (v is num) return '"${e.key}":$v';
        if (v is bool) return '"${e.key}":$v';
        if (v is List) return '"${e.key}":[]';
        return '"${e.key}":"${v.toString().replaceAll('"', r'\"')}"';
      });
      return '{${parts.join(',')}}';
    });
    SharedPreferences.setMockInitialValues({
      'saved_contacts_v2': '[${entries.join(',')}]',
    });
    late WalletViewModel wallet;
    late GroupsViewModel groups;
    await tester.runAsync(() async {
      final repo = ContactsRepository();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wallet = WalletViewModel(contactsRepository: repo);
      groups = GroupsViewModel(
        groupsRepository: GroupsRepository(),
        contactsRepository: repo,
      );
    });
    return (wallet: wallet, groups: groups);
  }

  Future<void> pumpWallet(
    WidgetTester tester,
    WalletViewModel vm,
    GroupsViewModel groupsVm,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<WalletViewModel>.value(value: vm),
            ChangeNotifierProvider<GroupsViewModel>.value(value: groupsVm),
          ],
          child: const WalletView(),
        ),
      ),
    );
    // pumpAndSettle 대신 고정 프레임만 넘긴다 — 위 scrollDown과 같은 이유.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 명함이 많을 때 스크롤을 시뮬레이션한다.
  ///
  /// `tester.drag`/`fling`으로 큰 거리를 밀면 관성(ballistic) 스크롤
  /// 물리가 걸려 `pumpAndSettle`이 실제 몇 초~분 단위로 안 끝난다(직접
  /// 겪음 — 2026-08-21). 목록의 스크롤 위치를 직접 `jumpTo`해 즉시
  /// 옮기고, 머리글 접힘 애니메이션(180ms)만큼만 프레임을 넘긴다 —
  /// 실제 손가락 제스처의 물리 디테일은 이 테스트의 관심사가 아니다.
  Future<void> scrollDown(WidgetTester tester) async {
    // `scrollable_positioned_list`는 `ListView`가 아니라 자체
    // `Scrollable`을 그린다(패키지 소스 확인) — `ListView`로 찾을 수 없다.
    // 검색창(`TextField`)도 내부에 자기 `Scrollable`(가로 텍스트 스크롤)을
    // 갖고 있고, 추가 427부터는 그룹 칩 줄도 가로 `ListView`(Scrollable)다
    // — `EditableText` 조상 유무만으로는 더는 목록을 구분할 수 없다(그룹
    // 칩도 조상에 EditableText가 없다). **세로축**인 것으로 한 번 더
    // 좁힌다 — 목록만 세로로 스크롤한다.
    final listElement = find.byType(Scrollable).evaluate().firstWhere((e) {
      if (e.findAncestorWidgetOfExactType<EditableText>() != null) {
        return false;
      }
      final widget = e.widget as Scrollable;
      return widget.axisDirection == AxisDirection.down ||
          widget.axisDirection == AxisDirection.up;
    });
    final scrollable = (listElement as StatefulElement).state as ScrollableState;
    scrollable.position.jumpTo(300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('⭐ 맨 위에서는 큰 제목이 보이고, 내리면 축약형으로 접힌다', (tester) async {
    final vms = await viewModelWith(tester, List.generate(40, contact));
    await pumpWallet(tester, vms.wallet, vms.groups);

    // 맨 위 — 큰 제목 그대로.
    expect(
      find.text('명함 지갑'),
      findsOneWidget,
      reason: '펼친 상태에서는 축약 제목 줄이 아직 없어 "명함 지갑"이 한 번만 보인다',
    );
    expect(find.text('40명의 인맥'), findsOneWidget);

    await scrollDown(tester);

    // 접힌 뒤 — 축약 제목(+ 배지)이 뜨고, 부제 텍스트는 사라진다.
    expect(find.text('명함 지갑'), findsOneWidget, reason: '축약 제목으로 바뀌어도 문구는 같다');
    expect(
      find.text('40명의 인맥'),
      findsNothing,
      reason: '큰 제목 블록(부제 포함)은 흘려보낸다',
    );
    expect(
      find.text('40'),
      findsOneWidget,
      reason: '접힌 축약 제목 옆 개수 배지',
    );
  });

  testWidgets('⭐ 접혀도 검색창과 정렬 칩은 계속 쓸 수 있다', (tester) async {
    final vms = await viewModelWith(tester, List.generate(40, contact));
    await pumpWallet(tester, vms.wallet, vms.groups);

    await scrollDown(tester);

    expect(
      find.text('이름, 회사, 직함 검색'),
      findsOneWidget,
      reason: '검색창은 브리프 표에서 "고정" — 접혀도 남아 있어야 한다',
    );
    expect(find.text('최근등록순'), findsOneWidget, reason: '정렬 칩도 고정');

    // 검색이 실제로 계속 동작하는지까지 — 접힌 채로 검색해도 목록이 좁혀진다.
    await tester.enterText(find.byType(TextField), '인맥1');
    await tester.pump();
    expect(find.text('인맥1'), findsOneWidget);
    expect(find.text('인맥2'), findsNothing);
  });

  testWidgets('⭐ 선택 모드(F-06)에서 접으면 선택 개수·전체선택 버튼이 축약 줄에 남는다', (
    tester,
  ) async {
    final vms = await viewModelWith(tester, List.generate(40, contact));
    await pumpWallet(tester, vms.wallet, vms.groups);

    await tester.tap(find.byTooltip('선택 삭제'));
    await tester.pump();

    await scrollDown(tester);

    expect(
      find.text('0개 선택'),
      findsOneWidget,
      reason: '선택 모드에서는 개수 배지 대신 선택 개수 문구가 축약 줄에 남아야 한다',
    );
    expect(
      find.text('전체 선택'),
      findsOneWidget,
      reason: '선택 모드 상단 바(전체선택/취소)가 고정 블록에 가려지지 않는다',
    );
    expect(find.text('취소'), findsOneWidget);
  });

  testWidgets('목록이 검색으로 다 걸러지면 접힌 채로 남지 않는다', (tester) async {
    final vms = await viewModelWith(tester, List.generate(40, contact));
    await pumpWallet(tester, vms.wallet, vms.groups);

    await scrollDown(tester);
    expect(find.text('40명의 인맥'), findsNothing, reason: '접힘 확인');

    await tester.enterText(find.byType(TextField), '존재하지않는이름');
    await tester.pump();

    expect(
      find.text('검색 결과가 없습니다'),
      findsOneWidget,
    );
    expect(
      find.text('40명의 인맥'),
      findsOneWidget,
      reason: '빈 상태에는 스크롤할 목록이 없으니 머리글이 강제로 펴져야 한다',
    );
  });
}
