import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/contact_detail_view.dart';

/// 명함 상세 시트 ⑤ 개선(2026-08-21 브리프 ⑤) 회귀 방지 테스트.
///
/// [ContactDetailView] 전체는 `context.read<AuthRepository>().firebaseUid`를
/// 쓰는데, 이 저장소 테스트 환경에는 Firebase 초기화(mock)가 없다 — 다른
/// 어떤 테스트도 Firebase를 건드리는 위젯을 직접 pump하지 않는다. 그래서
/// 여기서는 **화면과 분리해 둔 순수 로직**([contactRowActionKinds])과
/// **독립 위젯**([ContactActionIcon])만 검증한다. 시트 전체가 실제로 뜨는
/// 모습(빈 값 줄·닫기/편집 배치 등)은 실기기 부분 테스트로 확인한다.
void main() {
  group('contactRowActionKinds — 어떤 줄에 어떤 동작을 붙이는가', () {
    test('휴대폰 줄은 값이 있으면 전화+문자', () {
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.mobile, value: '010-1234-5678'),
        [ContactActionKind.call, ContactActionKind.sms],
      );
    });

    test('사무실 줄은 값이 있으면 전화만', () {
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.office, value: '02-123-4567'),
        [ContactActionKind.call],
      );
    });

    test('이메일 줄은 값이 있으면 메일만', () {
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.email, value: 'a@b.c'),
        [ContactActionKind.email],
      );
    });

    test('⭐ 값이 없으면(null) 아이콘이 없다 — 빈 데이터를 만들지 않는다', () {
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.mobile, value: null),
        isEmpty,
      );
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.office, value: null),
        isEmpty,
      );
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.email, value: null),
        isEmpty,
      );
    });

    test('⭐ 값이 빈 문자열/공백뿐이면 아이콘이 없다', () {
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.mobile, value: ''),
        isEmpty,
      );
      expect(
        contactRowActionKinds(rowKind: ContactRowKind.office, value: '   '),
        isEmpty,
      );
    });
  });

  group('ContactActionIcon — 시각 크기·터치 영역·접근성', () {
    Future<void> pump(WidgetTester tester, {required VoidCallback onTap}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ContactActionIcon(
                icon: Icons.call,
                label: '홍길동에게 전화',
                onTap: onTap,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('⭐ 터치 영역이 44dp 이상이다', (tester) async {
      await pump(tester, onTap: () {});
      final size = tester.getSize(find.byType(ContactActionIcon));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('⭐ tooltip이 접근성 라벨로 노출된다("OOO에게 전화")', (tester) async {
      await pump(tester, onTap: () {});
      expect(find.byTooltip('홍길동에게 전화'), findsOneWidget);
    });

    testWidgets('누르면 onTap이 불린다', (tester) async {
      var tapped = false;
      await pump(tester, onTap: () => tapped = true);
      await tester.tap(find.byType(ContactActionIcon));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
