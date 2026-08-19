// 스캔 결과에서 줄+좌표를 읽는 것(추가 334).
//
// ⚠️ 이 테스트가 지키는 핵심은 **"옛 자료가 그대로 돈다"**이다. 좌표 칸이 없는
// 파일이 실제로 쓰이고 있어서, 여기가 깨지면 지금까지 잰 숫자가 통째로
// 흔들린다.
import 'package:flutter_test/flutter_test.dart';

import 'support/scan_row_lines.dart';

void main() {
  group('좌표가 없는 옛 자료', () {
    test('원문만 있으면 줄은 그대로, 좌표는 0(=모름)', () {
      final r = scanRowLines({'원문': '홍길동 ⏐ (주)어디어디 ⏐ 부장'});
      expect(r.map((b) => b.text), ['홍길동', '(주)어디어디', '부장']);
      expect(r.every((b) => b.left == 0 && b.top == 0), isTrue);
      expect(r.every((b) => b.width == 0 && b.height == 0), isTrue);
      expect(scanRowHasBoxes({'원문': '홍길동'}), isFalse);
    });

    test('원문이 비면 빈 목록', () {
      expect(scanRowLines({'원문': ''}), isEmpty);
      expect(scanRowLines({}), isEmpty);
    });

    test('빈 조각은 버린다', () {
      expect(scanRowLines({'원문': '가 ⏐  ⏐ 나'}).map((b) => b.text), ['가', '나']);
    });
  });

  group('좌표가 실린 자료', () {
    test('원문과 짝을 맞춰 읽는다', () {
      final r = scanRowLines({
        '원문': '홍길동 ⏐ 부장',
        '좌표': '10,20,300,40 ⏐ 12,70,150,25',
      });
      expect(r, hasLength(2));
      expect(r[0].left, 10);
      expect(r[0].top, 20);
      expect(r[0].width, 300);
      expect(r[0].height, 40);
      expect(r[1].top, 70);
      expect(scanRowHasBoxes({
        '원문': '홍길동 ⏐ 부장',
        '좌표': '10,20,300,40 ⏐ 12,70,150,25',
      }), isTrue);
    });
  });

  group('⚠️ 짝이 어긋나면 좌표를 통째로 버린다', () {
    // 앞에서부터 맞춰 쓰면 **엉뚱한 줄에 엉뚱한 좌표**가 붙어 조용히 틀린다.
    // 좌표 규칙은 그걸 근거로 칸을 정하므로, 조용히 틀리는 것이 제일 나쁘다.
    test('개수가 모자라면', () {
      final r = scanRowLines({'원문': '가 ⏐ 나 ⏐ 다', '좌표': '1,2,3,4 ⏐ 5,6,7,8'});
      expect(r.map((b) => b.text), ['가', '나', '다']);
      expect(r.every((b) => b.left == 0), isTrue, reason: '좌표를 쓰면 안 된다');
    });

    test('개수가 넘쳐도', () {
      final r = scanRowLines({
        '원문': '가 ⏐ 나',
        '좌표': '1,2,3,4 ⏐ 5,6,7,8 ⏐ 9,10,11,12',
      });
      expect(r.every((b) => b.left == 0), isTrue);
    });

    test('한 줄이라도 숫자가 깨졌으면 전부 버린다', () {
      final r = scanRowLines({'원문': '가 ⏐ 나', '좌표': '1,2,3,4 ⏐ 어쩌고'});
      expect(r.every((b) => b.left == 0), isTrue);
    });

    test('칸 개수가 4가 아니어도 버린다', () {
      final r = scanRowLines({'원문': '가', '좌표': '1,2,3'});
      expect(r.single.left, 0);
    });
  });
}
