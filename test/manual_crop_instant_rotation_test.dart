// 자르기 화면 회전 즉시 반영(P2-③ 2차, 실기기 피드백: "굽기 ~2초가 남음" +
// "반시계 회전이 안 된다") 회귀 방지.
//
// 순수 로직(CropRotationBakeState, rotateCornersCcw90)은 각자 테스트로
// 고정돼 있다 — 이 파일은 그 둘이 실제 위젯(ManualCropView) 안에서 **한
// 프레임 만에 화면을 돌리는지**, 그리고 **저장 시점에는 굽기가 끝난
// 상태여야 한다는 인수 기준**을 실제로 지키는지를 확인한다.
//
// ⚠️ **`tester.runAsync`가 필요하다**(`image_file_cache_test.dart`와 같은
// 이유) — 진짜 이미지 디코딩·`compute()`(isolate 스폰)는 위젯 테스트의
// "가짜 시간" 안에서는 끝나지 않는다. 실제 시간이 흐르게 하려고 감싼다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:connection_trace_ai_flutter/presentation/features/wallet/views/manual_crop_view.dart';

void main() {
  late Directory dir;
  late String photoPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manual_crop_instant_test');
    final photo = img.Image(width: 400, height: 300);
    img.fill(photo, color: img.ColorRgb8(200, 200, 200));
    photoPath = '${dir.path}/card.jpg';
    await File(photoPath).writeAsBytes(img.encodeJpg(photo, quality: 90));
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  // ⚠️ `pumpAndSettle()`을 안 쓴다 — 로딩 중에는 `CircularProgressIndicator`
  // (끝없이 도는 애니메이션)가 떠 있어서 **영원히 안 멎는다.** 정해진
  // 프레임 수만큼만, 실제 시간을 조금씩 흘려보내며 편다.
  //
  // ⚠️ 버튼 행([회전] 등)은 이미지 로딩과 무관하게 **처음부터 그려진다**
  // (`build`에서 그 행이 로딩 분기 바깥에 있다) — 그래서 아이콘 존재만으로는
  // "로딩이 끝났다"를 못 가린다. 실제 사진이 뜬 뒤에만 나타나는
  // [RotatedBox]로 판정한다.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('반시계 버튼이 있고, 한 프레임 만에 화면이 돈다(배경 굽기를 기다리지 않는다)', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: ManualCropView(imagePath: photoPath)));
    // FileImage 스트림이 실제 크기를 읽을 때까지 기다린다(초기 로딩만).
    await pumpUntil(tester, () => find.byType(RotatedBox).evaluate().isNotEmpty);

    expect(find.byIcon(Icons.rotate_left), findsOneWidget, reason: '반시계 버튼이 있어야 한다');
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);

    final beforeBox = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(beforeBox.quarterTurns, 0);

    await tester.tap(find.byIcon(Icons.rotate_left));
    // ⚠️ **딱 한 프레임만 편다** — 실제 굽기(무거운 디코드+isolate 스폰)는
    // 이 한 프레임 안에 못 끝난다. 그런데도 화면은 이미 돌아가 있어야
    // "즉시"라는 주장이 성립한다(실기기 피드백의 핵심).
    await tester.pump();

    final afterBox = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(afterBox.quarterTurns, 3, reason: '반시계 한 번 = pendingTurns 3(=270도, cw90의 역)');

    // 뒷정리 — 배경 굽기가 끝날 때까지 기다려 남은 타이머·Future가 없게 한다.
    await pumpUntil(
      tester,
      () => tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns == 0,
    );
  });

  testWidgets('회전 직후 곧바로 확정해도 저장물이 화면과 어긋나지 않는다(인수 기준 1)', (
    tester,
  ) async {
    Object? poppedResult;
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              poppedResult = await Navigator.of(context).push<Object?>(
                MaterialPageRoute(builder: (_) => ManualCropView(imagePath: photoPath)),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // 페이지 전환 시작
    await pumpUntil(tester, () => find.byType(RotatedBox).evaluate().isNotEmpty);

    // 시계 방향으로 한 번 돌리고 — 배경 굽기가 끝나기 **전에** 곧바로
    // [이대로 자르기]를 누른다(연타·조급한 확정 흉내).
    await tester.tap(find.byIcon(Icons.rotate_right));
    await tester.pump();
    await tester.tap(find.text('이대로 자르기'));
    // 확정은 밀린 굽기가 끝날 때까지 기다린다 — 화면이 닫힐 때까지 편다.
    await pumpUntil(tester, () => closed);

    expect(poppedResult, isA<ManualCropResult>());
    final result = poppedResult! as ManualCropResult;
    // 원본은 400x300(가로) — 90도 돌려 구웠으면 세로(300x400)여야 한다.
    expect(result.imageSize.width, closeTo(300, 5));
    expect(result.imageSize.height, closeTo(400, 5));
    expect(result.imagePath, isNot(photoPath), reason: '실제로 새로 구운 파일을 가리켜야 한다');
    expect(File(result.imagePath).existsSync(), isTrue);

    final baked = img.decodeImage(File(result.imagePath).readAsBytesSync())!;
    expect(baked.width, closeTo(300, 5));
    expect(baked.height, closeTo(400, 5));
  });
}
