// 자르기 화면 회귀 방지 — 이미지 크기 로드 전 확정 크래시 자리(추가 407 ②).
//
// 하단 버튼 행(회전 2개·다시 찾기·이대로 자르기)은 이미지 로딩 스피너 분기
// 밖에 있어서(`build`의 Column 구조 참고) `_imageSize`가 아직 null인 순간에도
// 그려진다. 이전에는 이 상태에서 [이대로 자르기]를 누르면 `_confirm()`이
// `ManualCropResult(imageSize: _imageSize!)`에서 크래시할 수 있었다(원본
// 코드부터 있던 문제 — #447 회전 개선 작업 중 발견, 이번에 수정).
//
// ⚠️ **화면-저장물 일치 원칙**(추가 273 이후 이 저장소의 반복 원칙): 크래시를
// 막는다고 "일단 null 대신 아무 크기나 넣어 저장은 되게" 하면 안 된다 —
// 조용히 잘못된 좌표로 저장되는 것이 크래시보다 나쁘다. 그래서 로드 전에는
// 버튼 자체가 비활성화돼 눌러도 아무 일도 안 일어나야 한다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/manual_crop_view.dart';

void main() {
  late Directory dir;
  late String photoPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manual_crop_load_race_test');
    final photo = img.Image(width: 400, height: 300);
    img.fill(photo, color: img.ColorRgb8(200, 200, 200));
    photoPath = '${dir.path}/card.jpg';
    await File(photoPath).writeAsBytes(img.encodeJpg(photo, quality: 90));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('이미지 크기 로드 전에는 [이대로 자르기]가 비활성화돼 눌러도 크래시하지 않는다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualCropView(imagePath: photoPath)),
    );
    // ⚠️ 로딩이 끝나길 기다리지 않는다 — 바로 다음 프레임(이미지 크기를
    // 아직 모르는 시점)에서 버튼 행이 이미 그려져 있는지, 눌러도 안전한지가
    // 이 테스트의 핵심이다.
    await tester.pump();

    final confirmButtonFinder = find.widgetWithText(ElevatedButton, '이대로 자르기');
    expect(confirmButtonFinder, findsOneWidget, reason: '버튼 행은 로딩 중에도 그려진다');

    final confirmButton = tester.widget<ElevatedButton>(confirmButtonFinder);
    expect(confirmButton.onPressed, isNull, reason: '이미지 크기를 모르면 비활성화돼야 한다');

    // 비활성화된 버튼을 눌러도 예외 없이 넘어가야 한다(1차 방어선).
    await tester.tap(confirmButtonFinder, warnIfMissed: false);
    await tester.pump();

    // 화면이 그대로 남아 있다 — Navigator.pop이 호출되지 않았다는 뜻.
    expect(find.byType(ManualCropView), findsOneWidget);

    final rotateLeft = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.byIcon(Icons.rotate_left),
        matching: find.byType(OutlinedButton),
      ),
    );
    final rotateRight = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.byIcon(Icons.rotate_right),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(rotateLeft.onPressed, isNull, reason: '로딩 전에는 회전도 비활성화된다');
    expect(rotateRight.onPressed, isNull);

    // 뒷정리 — 이미지가 실제로 로드될 때까지 기다려 남은 Future가 없게 한다.
    await pumpUntil(tester, () => find.byType(RotatedBox).evaluate().isNotEmpty);

    // 로드가 끝나면 다시 활성화된다.
    final confirmAfterLoad = tester.widget<ElevatedButton>(confirmButtonFinder);
    expect(confirmAfterLoad.onPressed, isNotNull);
  });

  testWidgets('[다시 찾기] 버튼 아이콘이 회전 버튼들과 다르다(추가 407 ①)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualCropView(imagePath: photoPath)),
    );
    await tester.pump();

    // 예전 아이콘(Icons.replay)이 남아 있지 않아야 한다 — 회전류 아이콘과
    // 혼동됐던 그 아이콘이다.
    expect(find.byIcon(Icons.replay), findsNothing);
    expect(find.byIcon(Icons.undo), findsOneWidget);

    // 역할이 읽히는 문구(Tooltip)가 아이콘을 감싸고 있어야 한다.
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.byIcon(Icons.undo), matching: find.byType(Tooltip)),
    );
    expect(tooltip.message, contains('되돌리기'));

    final semanticsAncestors = find
        .ancestor(of: find.byIcon(Icons.undo), matching: find.byType(Semantics))
        .evaluate()
        .map((e) => e.widget as Semantics);
    expect(
      semanticsAncestors.any((s) => (s.properties.label ?? '').contains('되돌리기')),
      isTrue,
      reason: '역할이 읽히는 Semantics 라벨이 있어야 한다',
    );
  });
}
