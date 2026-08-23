import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/common/card_image_viewer.dart';

/// 1×1 투명 PNG — 실제 이미지 디코딩 경로를 태우기 위한 최소 표본.
/// (개인정보 없는 합성 이미지. 명함 표본이 아니다.)
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

CardFaceImage _face(String label) =>
    CardFaceImage(image: MemoryImage(_tinyPng), label: label);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('CardPhotoPreview — 면 수에 따른 UI 분기(추가 426 인수 기준)', () {
    testWidgets('1장이면 앞/뒤 세그먼트가 없다', (tester) async {
      await tester.pumpWidget(
        _wrap(CardPhotoPreview(faces: [_face('명함 사진')], selectedIndex: 0)),
      );
      await tester.pumpAndSettle();

      // 세그먼트 라벨 자체가 화면에 없어야 한다 — 1장뿐이면 고를 게 없다.
      expect(find.text('명함 사진'), findsNothing);
      // 대신 돋보기(크게 보기) 버튼은 항상 있어야 한다.
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    });

    testWidgets('2장(앞/뒤)이면 세그먼트가 뜨고 탭하면 선택이 바뀐다', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          CardPhotoPreview(
            faces: [_face('앞면'), _face('뒷면')],
            selectedIndex: 0,
            onSelectFace: (i) => selected = i,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('앞면'), findsOneWidget);
      expect(find.text('뒷면'), findsOneWidget);

      await tester.tap(find.text('뒷면'));
      await tester.pumpAndSettle();

      expect(selected, 1);
    });

    testWidgets('돋보기를 누르면 전체화면 뷰어가 열리고 좌우로 넘기면 배지가 바뀐다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          CardPhotoPreview(faces: [_face('앞면'), _face('뒷면')], selectedIndex: 0),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();

      // 처음엔 앞면 1/2가 보인다.
      expect(find.text('앞면 1/2'), findsOneWidget);

      // 좌우 스와이프(페이지뷰 드래그)로 뒷면으로 넘어간다. 화면 폭 전체보다
      // 크게 던져야 드래그 한 번으로 다음 페이지까지 확실히 넘어간다.
      await tester.fling(find.byType(PageView), const Offset(-600, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('뒷면 2/2'), findsOneWidget);

      // 닫기를 누르면 뷰어가 사라지고 원래 화면(미리보기)으로 돌아온다.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('뒷면 2/2'), findsNothing);
      expect(find.byType(CardPhotoPreview), findsOneWidget);
    });
  });

  group('뷰어에서 돌아와도 화면 상태가 유지된다(추가 426 인수 기준)', () {
    testWidgets('뷰어를 열고 닫아도 텍스트 입력칸 값이 그대로다', (tester) async {
      final controller = TextEditingController(text: '기존 입력값');
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              TextField(controller: controller),
              CardPhotoPreview(faces: [_face('명함 사진')], selectedIndex: 0),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('기존 입력값'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 뷰어는 별도 라우트로 push된 것뿐 — pop해도 폼 위젯이 다시 만들어지지
      // 않으므로 컨트롤러 값이 그대로 남는다.
      expect(find.text('기존 입력값'), findsOneWidget);
      expect(controller.text, '기존 입력값');
    });
  });
}
