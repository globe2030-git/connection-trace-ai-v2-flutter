// F-03 회전 계산 검사.
//
// 무엇을 지키려는 검사인가: **네 번 눌러 제자리로 온 사진을 다시 굽지 않는
// 것**과, 각도가 항상 0·90·180·270 안에 머무는 것. 재인코딩은 누를 때마다
// 화질을 깎으므로, "제자리면 굽지 않는다"가 이 기능의 조용한 핵심이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/scan_rotation.dart';

void main() {
  group('nextClockwiseTurn', () {
    test('90도씩 시계 방향으로 돈다', () {
      expect(nextClockwiseTurn(0), 90);
      expect(nextClockwiseTurn(90), 180);
      expect(nextClockwiseTurn(180), 270);
    });

    test('네 번 누르면 제자리로 돌아온다', () {
      var d = 0;
      for (var i = 0; i < 4; i++) {
        d = nextClockwiseTurn(d);
      }
      expect(d, 0);
    });

    test('계속 눌러도 360을 넘지 않는다', () {
      var d = 0;
      for (var i = 0; i < 13; i++) {
        d = nextClockwiseTurn(d);
        expect(d, lessThan(360));
        expect(d % 90, 0);
      }
    });
  });

  group('needsRebake — 제자리면 다시 굽지 않는다', () {
    test('0이면 굽지 않는다', () {
      expect(needsRebake(0), isFalse);
    });

    test('네 번 눌러 제자리로 온 경우도 굽지 않는다', () {
      expect(needsRebake(360), isFalse);
      expect(needsRebake(720), isFalse);
    });

    test('돌린 상태면 굽는다', () {
      expect(needsRebake(90), isTrue);
      expect(needsRebake(180), isTrue);
      expect(needsRebake(270), isTrue);
    });
  });

  group('normalizeTurn', () {
    test('360을 넘겨도 0~270으로 접는다', () {
      expect(normalizeTurn(360), 0);
      expect(normalizeTurn(450), 90);
    });

    test('음수도 받는다 — 나중에 반시계를 붙여도 그대로 쓴다', () {
      expect(normalizeTurn(-90), 270);
      expect(normalizeTurn(-360), 0);
    });
  });

  group('quarterTurnsFor — RotatedBox에 넘길 값', () {
    test('0~3 사이로만 나온다', () {
      expect(quarterTurnsFor(0), 0);
      expect(quarterTurnsFor(90), 1);
      expect(quarterTurnsFor(180), 2);
      expect(quarterTurnsFor(270), 3);
      expect(quarterTurnsFor(360), 0);
    });

    test('음수도 0~3 안에 들어온다', () {
      expect(quarterTurnsFor(-90), 3);
    });
  });

  group('미리보기와 저장이 같은 각도를 쓴다', () {
    test('quarterTurnsFor와 normalizeTurn이 어긋나지 않는다', () {
      // 미리보기는 quarterTurns로 돌리고 저장은 각도로 굽는다. 둘이 어긋나면
      // **사용자가 본 것과 인식에 들어가는 것이 달라진다.**
      for (final d in [0, 90, 180, 270, 360, 450, -90]) {
        expect(quarterTurnsFor(d) * 90, normalizeTurn(d));
      }
    });
  });
}
