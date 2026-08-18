// F-01 충돌 선택 시트의 약속 검증.
//
// 이 시트의 가장 중요한 성질은 **아무것도 고르지 않으면 지금 값이 그대로
// 남는다**는 것이다. 스캔 한 번으로 사용자가 이미 입력한 값이 저절로 바뀌면
// 안 된다. 기본값이 뒤집히면 "뒷면을 찍었더니 앞면 정보가 사라졌다"가 된다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/scan_field_conflict_sheet.dart';

const _conflicts = [
  ScanFieldConflict(
    key: 'mobile',
    label: '휴대폰 번호',
    currentValue: '010-1234-5678',
    scannedValue: '02-555-0000',
  ),
  ScanFieldConflict(
    key: 'email',
    label: '이메일',
    currentValue: 'hong@gmail.com',
    scannedValue: 'hong@raum.co.kr',
  ),
];

/// 시트를 열고 결과를 받아 주는 껍데기 화면.
Future<Map<String, String>?> _open(WidgetTester tester) async {
  Map<String, String>? result;
  var returned = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              result = await showScanFieldConflictSheet(
                context,
                conflicts: _conflicts,
              );
              returned = true;
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  expect(returned, isFalse, reason: '시트가 열려 있는 동안에는 결과가 없어야 한다');
  return result;
}

void main() {
  testWidgets('부딪힌 칸과 두 값이 모두 보인다', (tester) async {
    await _open(tester);

    expect(find.text('뒷면에서 다른 값을 읽었습니다 (2개)'), findsOneWidget);
    expect(find.text('휴대폰 번호'), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
    expect(find.text('02-555-0000'), findsOneWidget);
    expect(find.text('이메일'), findsOneWidget);
    expect(find.text('hong@raum.co.kr'), findsOneWidget);
  });

  testWidgets('아무것도 고르지 않고 적용하면 바뀌는 값이 없다', (tester) async {
    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showScanFieldConflictSheet(
                  context,
                  conflicts: _conflicts,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    // 빈 map — "고르지 않았다"는 뜻이지 실패가 아니다.
    expect(result, isEmpty);
  });

  testWidgets('뒷면 값을 고른 칸만 돌려준다', (tester) async {
    Map<String, String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showScanFieldConflictSheet(
                  context,
                  conflicts: _conflicts,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 휴대폰만 뒷면 값으로 바꾼다. 이메일은 손대지 않는다.
    await tester.tap(find.text('02-555-0000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(result, {'mobile': '02-555-0000'});
  });

  testWidgets('취소하면 null — 한 칸을 골라 뒀더라도 아무것도 바꾸지 않는다', (tester) async {
    Map<String, String>? result;
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showScanFieldConflictSheet(
                  context,
                  conflicts: _conflicts,
                );
                returned = true;
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('02-555-0000'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNull);
  });
}
