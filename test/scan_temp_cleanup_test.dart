// 촬영 임시 파일 정리 검사(2026-08-16).
//
// 무엇을 지키려는 검사인가:
// ① **우리가 만든 것만** 지운다 — 다른 앱·플러그인 파일을 지우면 그쪽이 깨진다.
// ② **방금 만든 것은 안 지운다** — 지금 인식·저장에 쓰이는 중일 수 있다.
// ③ **던지지 않는다** — 정리 실패로 촬영·저장이 막히면 안 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/scan_temp_cleanup.dart';

void main() {
  group('isScanTempName — 우리가 만든 것만', () {
    test('우리 파일은 맞다', () {
      expect(isScanTempName('card_scan_1786805378064.jpg'), isTrue);
      expect(isScanTempName('card_rot_1786805541190.jpg'), isTrue);
      // 무음 촬영(프레임 캡처) 원본 — 정상 흐름에서는 크롭 뒤 바로 지워지지만,
      // 화면을 중간에 닫으면 남을 수 있어 같은 규칙으로 걸려야 한다.
      expect(isScanTempName('card_silent_1786805600000.jpg'), isTrue);
    });

    test('남의 파일은 건드리지 않는다', () {
      expect(isScanTempName('CAP167556052032855569.jpg'), isFalse);
      expect(isScanTempName('flutter_engine.so'), isFalse);
      expect(isScanTempName('contact_card_abc.enc'), isFalse);
      expect(isScanTempName(''), isFalse);
    });
  });

  group('shouldSweep — 방금 만든 것은 안 지운다', () {
    final now = DateTime(2026, 8, 16, 12, 0);

    test('1시간이 지나면 지운다', () {
      expect(
        shouldSweep('card_scan_1.jpg', now.subtract(const Duration(hours: 2)), now),
        isTrue,
      );
    });

    test('방금 만든 것은 안 지운다 — 지금 쓰이는 중일 수 있다', () {
      expect(
        shouldSweep('card_scan_1.jpg', now.subtract(const Duration(minutes: 5)), now),
        isFalse,
      );
      expect(shouldSweep('card_rot_1.jpg', now, now), isFalse);
    });

    test('경계에서 안전한 쪽으로 — 정확히 1시간이면 안 지운다', () {
      expect(
        shouldSweep('card_scan_1.jpg', now.subtract(kScanTempMaxAge), now),
        isFalse,
      );
    });

    test('오래됐어도 우리 파일이 아니면 안 지운다', () {
      expect(
        shouldSweep('CAP123.jpg', now.subtract(const Duration(days: 7)), now),
        isFalse,
      );
    });

    // 탈퇴 정리(추가 243) — 방침이 "탈퇴 시 전부 파기"라고 적고 있어, 1시간이
    // 안 된 파일이 남는 것 자체가 방침과 실물의 차이가 된다.
    test('maxAge가 0이면 방금 만든 것도 지운다 — 탈퇴 정리', () {
      expect(
        shouldSweep('card_scan_1.jpg', now, now, maxAge: Duration.zero),
        isTrue,
      );
      expect(
        shouldSweep(
          'card_rot_1.jpg',
          now.subtract(const Duration(seconds: 1)),
          now,
          maxAge: Duration.zero,
        ),
        isTrue,
      );
    });

    test('maxAge가 0이어도 남의 파일은 안 지운다', () {
      expect(
        shouldSweep('CAP123.jpg', now, now, maxAge: Duration.zero),
        isFalse,
      );
    });
  });

  group('deleteQuietly — 던지지 않는다', () {
    test('없는 파일에도 조용하다', () async {
      await expectLater(deleteQuietly('/없는/경로/파일.jpg'), completes);
    });

    test('null·빈 문자열에도 조용하다', () async {
      await expectLater(deleteQuietly(null), completes);
      await expectLater(deleteQuietly(''), completes);
    });

    test('실제로 지운다', () async {
      final dir = await Directory.systemTemp.createTemp('scan_cleanup_test');
      final f = File('${dir.path}/card_scan_9.jpg')..writeAsStringSync('x');
      expect(f.existsSync(), isTrue);
      await deleteQuietly(f.path);
      expect(f.existsSync(), isFalse);
      await dir.delete(recursive: true);
    });
  });

  group('sweepScanTemp — 실제 폴더에서', () {
    test('오래된 우리 파일만 지우고 나머지는 남긴다', () async {
      final dir = await Directory.systemTemp.createTemp('scan_sweep_test');
      final old = DateTime.now().subtract(const Duration(hours: 3));

      final mine = File('${dir.path}/card_scan_old.jpg')..writeAsStringSync('a');
      final rot = File('${dir.path}/card_rot_old.jpg')..writeAsStringSync('b');
      final fresh = File('${dir.path}/card_scan_new.jpg')..writeAsStringSync('c');
      final theirs = File('${dir.path}/CAP_old.jpg')..writeAsStringSync('d');
      mine.setLastModifiedSync(old);
      rot.setLastModifiedSync(old);
      theirs.setLastModifiedSync(old);

      final removed = await sweepScanTemp(dir);

      expect(removed, 2);
      expect(mine.existsSync(), isFalse);
      expect(rot.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: '방금 만든 것은 남아야 한다');
      expect(theirs.existsSync(), isTrue, reason: '남의 파일은 남아야 한다');

      await dir.delete(recursive: true);
    });

    test('없는 폴더에도 던지지 않는다', () async {
      final removed = await sweepScanTemp(Directory('/없는/폴더'));
      expect(removed, 0);
    });

    test('탈퇴 정리(maxAge 0)는 방금 만든 것까지 쓸어낸다', () async {
      final dir = await Directory.systemTemp.createTemp('scan_sweep_all_test');
      final fresh = File('${dir.path}/card_scan_new.jpg')
        ..writeAsStringSync('a');
      final rot = File('${dir.path}/card_rot_new.jpg')..writeAsStringSync('b');
      final theirs = File('${dir.path}/CAP_new.jpg')..writeAsStringSync('c');

      final removed = await sweepScanTemp(dir, maxAge: Duration.zero);

      expect(removed, 2);
      expect(fresh.existsSync(), isFalse);
      expect(rot.existsSync(), isFalse);
      expect(theirs.existsSync(), isTrue, reason: '남의 파일은 여전히 남긴다');

      await dir.delete(recursive: true);
    });
  });
}
