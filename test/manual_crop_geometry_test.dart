// 손으로 자르기(F-03, 추가 290)의 **좌표 변환**을 검증한다.
//
// 왜 따로 재나: 확인 화면은 사진을 `BoxFit.contain`으로 그리고, 카메라
// 프리뷰는 cover로 그린다. **맞추는 규칙이 다른데 좌표는 똑같이 생겼다** —
// 섞이면 손가락 위치와 자르는 위치가 어긋나고, 그건 실기기에서만 드러난다.
//
// ⚠️ 이 저장소는 좌표계를 섞어 실기기에서 두 번 헤맸다(추가 273). 그래서
// 화면 없이 검증할 수 있는 부분은 **전부 순수 함수로 빼서 여기서 고정한다.**
import 'dart:ui';

import 'package:connection_trace_ai_flutter/core/utils/card_quad_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('containImageRect — 레터박스 자리', () {
    test('가로로 긴 사진은 위아래에 띠가 남는다', () {
      // 사진 2:1을 정사각 상자에 넣으면 높이가 절반만 찬다.
      final r = containImageRect(const Size(200, 100), const Size(100, 100));
      expect(r.width, 100);
      expect(r.height, 50);
      expect(r.top, 25); // 위아래로 나눠 가진다
      expect(r.left, 0);
    });

    test('세로로 긴 사진은 좌우에 띠가 남는다', () {
      final r = containImageRect(const Size(100, 200), const Size(100, 100));
      expect(r.width, 50);
      expect(r.height, 100);
      expect(r.left, 25);
      expect(r.top, 0);
    });

    test('비율이 같으면 상자를 꽉 채운다', () {
      final r = containImageRect(const Size(300, 200), const Size(150, 100));
      expect(r, const Rect.fromLTWH(0, 0, 150, 100));
    });

    test('⚠️ 크기가 0이어도 터지지 않는다', () {
      // 첫 프레임에는 이미지 크기를 아직 모를 수 있다.
      expect(
        containImageRect(Size.zero, const Size(100, 100)),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });
  });

  group('상자 좌표 ↔ 이미지 정규 좌표', () {
    const image = Size(200, 100);
    const box = Size(100, 100); // 위아래 25씩 띠

    test('사진의 왼쪽 위 모서리는 (0,0)이다', () {
      expect(
        containPointToImageNormalized(const Offset(0, 25), image, box),
        const Offset(0, 0),
      );
    });

    test('사진의 오른쪽 아래 모서리는 (1,1)이다', () {
      expect(
        containPointToImageNormalized(const Offset(100, 75), image, box),
        const Offset(1, 1),
      );
    });

    test('한가운데는 (0.5, 0.5)다', () {
      expect(
        containPointToImageNormalized(const Offset(50, 50), image, box),
        const Offset(0.5, 0.5),
      );
    });

    test('⚠️ 사진 밖(띠 위)을 짚어도 0~1 안으로 잡아 둔다', () {
      // 손가락이 사진을 벗어나도 귀퉁이는 사진 안에 머물러야 한다 —
      // 밖으로 나간 귀퉁이로 자르면 **검은 띠가 섞여 들어온다.**
      expect(
        containPointToImageNormalized(const Offset(-30, 0), image, box).dx,
        0,
      );
      expect(
        containPointToImageNormalized(const Offset(999, 999), image, box),
        const Offset(1, 1),
      );
    });

    test('📌 되돌리면 제자리로 온다 — 손잡이를 그리는 데 쓴다', () {
      const point = Offset(30, 40);
      final norm = containPointToImageNormalized(point, image, box);
      final back = imageNormalizedToContainPoint(norm, image, box);
      expect(back.dx, closeTo(point.dx, 0.001));
      expect(back.dy, closeTo(point.dy, 0.001));
    });
  });

  group('⚠️ cover 규칙과 섞이지 않는다', () {
    test('같은 사진·같은 상자라도 contain과 cover는 다른 자리를 가리킨다', () {
      // 이게 같아지면 두 규칙 중 하나를 잘못 쓰고 있다는 뜻이다.
      const image = Size(200, 100);
      const box = Size(100, 100);
      final contain = containImageRect(image, box);
      final cover = visibleImageRect(image, box);
      // contain은 **상자** 좌표, cover는 **이미지 픽셀** 좌표라 뜻부터 다르다.
      expect(contain.height, 50); // 상자 안에서 사진이 차지하는 높이
      expect(cover.width, 100); // 이미지에서 화면에 보이는 폭(픽셀)
    });
  });
}
