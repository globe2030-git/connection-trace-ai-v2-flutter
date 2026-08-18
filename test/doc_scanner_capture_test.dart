// 기성 문서 스캐너 촬영 경로 검사(2026-08-16, 추가 266 1단계).
//
// 무엇을 지키려는 검사인가:
// ① **정리 규칙에 새 구멍을 내지 않는다** — 새 경로가 만드는 임시 파일이
//    기존 쓸어담기(`sweepScanTemp`)와 탈퇴 정리에 **반드시 걸려야** 한다.
//    접두사를 한 글자만 바꿔도 평문 명함 사진이 캐시에 남는데, 그건 저장본을
//    암호화하는 이유 자체를 무력화한다. 오늘 그 구멍을 여섯 개 막았다(추가
//    247·249·253) — 새로 뚫지 않는 것을 검사로 못 박는다.
// ② **다시 구울지를 확장자가 아니라 실제 바이트로 정한다** — 플랫폼마다
//    형식이 다르고(Android PNG · iOS 지정), 확장자가 내용과 어긋나면 판단이
//    틀린다.
// ③ **기본값은 아직 기존 경로다** — 1단계는 경로를 하나 더 만들 뿐이다.
//    2단계에서 재보기 전에 기본값이 바뀌어 나가면 검증 없이 교체된 것이 된다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/doc_scanner_capture_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/scan_temp_cleanup.dart';

void main() {
  group('① 임시 파일 이름 — 기존 정리 규칙에 걸려야 한다', () {
    final name = docScannerTempFileName(
      DateTime.fromMillisecondsSinceEpoch(1755300000000),
    );

    test('접두사가 kScanTempPrefixes 안에 있다', () {
      // 이 검사가 실패하면 "정리가 안 되는 평문 사진"이 생긴 것이다.
      expect(kScanTempPrefixes, contains(kDocScannerTempPrefix));
    });

    test('만들어진 이름을 isScanTempName이 우리 것으로 본다', () {
      expect(name, 'card_scan_1755300000000.jpg');
      expect(isScanTempName(name), isTrue);
    });

    test('1시간이 지나면 쓸어담기가 지운다', () {
      final made = DateTime(2026, 8, 16, 10, 0);
      expect(shouldSweep(name, made, made.add(const Duration(hours: 2))), isTrue);
    });

    test('방금 만든 것은 안 지운다 — 지금 인식·저장에 쓰이는 중일 수 있다', () {
      final made = DateTime(2026, 8, 16, 10, 0);
      expect(
        shouldSweep(name, made, made.add(const Duration(minutes: 5))),
        isFalse,
      );
    });

    test('탈퇴 정리(maxAge 0)에서는 방금 만든 것도 지운다', () {
      final made = DateTime(2026, 8, 16, 10, 0);
      expect(
        shouldSweep(name, made, made, maxAge: Duration.zero),
        isTrue,
      );
    });
  });

  group('② JPEG 판정 — 확장자가 아니라 바이트로 본다', () {
    test('JPEG 앞머리(FF D8 FF)면 참', () {
      expect(looksLikeJpeg(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), isTrue);
    });

    test('PNG 앞머리면 거짓 — 다시 구워야 한다', () {
      expect(
        looksLikeJpeg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        isFalse,
      );
    });

    test('너무 짧으면 거짓 — 앞머리를 볼 수 없다', () {
      expect(looksLikeJpeg(Uint8List.fromList([0xFF, 0xD8])), isFalse);
      expect(looksLikeJpeg(Uint8List(0)), isFalse);
    });
  });

  group('③ 1단계는 경로를 더할 뿐 — 기본값은 아직 기존 화면', () {
    test('기본값 상수가 false다', () {
      // ⚠️ 이 검사를 고쳐서 통과시키지 마라. 2단계 측정 결과 없이 기본값을
      // 바꾸는 것은 "재보지 않고 단정한 것"이다(추가 250).
      expect(kUseDocScannerCaptureByDefault, isFalse);
    });

    test('시작 값이 상수와 같다', () {
      expect(docScannerCaptureEnabled.value, kUseDocScannerCaptureByDefault);
    });
  });

  group('⚠️ ML Kit 원본 정리 — 실기기에서 새는 것을 잡고 만든 검사', () {
    // 2026-08-16: `cleanCache()`만 부르고 끝냈더니 **평문 명함 JPEG 두 개가
    // 캐시에 그대로 남아 있었다**(바이트 수가 찍은 사진과 일치). 플러그인은
    // 자기 접두사(`DOCUMENT_SCAN_`)만 지우는데, **ML Kit 원본은 GMS가 이름을
    // 정해서** 그 규칙 밖에 있다. 코드 리뷰로는 안 나왔고 **캐시를 열어 봐야**
    // 나왔다.
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('docscan_test_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('ML Kit 폴더 안의 평문 사진을 지운다', () async {
      final dir = Directory('${root.path}/$kMlKitScannerCacheDir');
      await dir.create();
      final leaked = File('${dir.path}/420983556411951.jpg');
      await leaked.writeAsBytes([0xFF, 0xD8, 0xFF, 0x00]);
      expect(await leaked.exists(), isTrue);

      await sweepMlKitScannerCache(root);

      expect(await leaked.exists(), isFalse);
    });

    test('폴더가 없어도 던지지 않는다 — 아직 한 번도 안 찍은 기기', () async {
      // 정리 실패로 촬영이 막히면 사용자가 잃는 것이 더 크다.
      await expectLater(sweepMlKitScannerCache(root), completes);
    });

    test('폴더 밖은 건드리지 않는다 — 우리 것만 지운다', () async {
      final dir = Directory('${root.path}/$kMlKitScannerCacheDir');
      await dir.create();
      final outsider = File('${root.path}/somebody_elses.jpg');
      await outsider.writeAsBytes([1, 2, 3]);

      await sweepMlKitScannerCache(root);

      expect(await outsider.exists(), isTrue);
    });

    // ⚠️ 이 검사가 2026-08-16에 생긴 이유:
    //
    // 처음 구현은 `Directory.systemTemp`를 **기본값**으로 썼다. 그런데
    // `systemTemp`는 `code_cache`이고 **ML Kit은 `cache`에 쓴다.** 없는 폴더를
    // 보고 있었으므로 함수는 **예외도 안 내고 조용히 아무것도 안 지웠다.**
    //
    // 그때 이 파일의 검사들은 **전부 통과했다** — 폴더를 직접 넘겨 줬기
    // 때문이다. **기본값을 아무도 안 밟았다.**
    //
    // 그래서 기본값을 없애 부르는 쪽이 반드시 넘기게 했고, 아래로 **"엉뚱한
    // 폴더를 주면 조용히 실패한다"**는 성질을 못 박는다. 다음 사람이 이걸
    // 보면 "왜 안 지워지지"에서 폴더부터 의심한다.
    test('⚠️ 엉뚱한 폴더를 주면 조용히 아무것도 안 한다 — 이것이 실제 결함이었다',
        () async {
      final wrong = await Directory.systemTemp.createTemp('wrong_root_');
      final right = await Directory.systemTemp.createTemp('right_root_');
      final mlkit = Directory('${right.path}/$kMlKitScannerCacheDir');
      await mlkit.create(recursive: true);
      final leftover = File('${mlkit.path}/1234.jpg');
      await leftover.writeAsBytes([0xFF, 0xD8, 0xFF, 0x00]);

      // 엉뚱한 폴더 — 던지지도, 지우지도 않는다.
      await expectLater(sweepMlKitScannerCache(wrong), completes);
      expect(await leftover.exists(), isTrue,
          reason: '엉뚱한 폴더를 줬으니 남아 있어야 한다 — 조용한 실패다');

      // 맞는 폴더 — 지운다.
      await sweepMlKitScannerCache(right);
      expect(await leftover.exists(), isFalse);

      await wrong.delete(recursive: true);
      await right.delete(recursive: true);
    });
  });

  group('픽셀 수 — 2단계에서 축소 임계(1,600)와 견줄 값', () {
    test('긴 변은 가로·세로 중 큰 쪽이다', () {
      const landscape = DocScannerCapture(
        path: 'x',
        widthPx: 1504,
        heightPx: 860,
        bytes: 1,
        reencoded: false,
      );
      const portrait = DocScannerCapture(
        path: 'x',
        widthPx: 860,
        heightPx: 1504,
        bytes: 1,
        reencoded: false,
      );
      expect(landscape.longEdgePx, 1504);
      expect(portrait.longEdgePx, 1504);
    });
  });
}
