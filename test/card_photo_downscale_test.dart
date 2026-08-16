// 보관본 축소 검사(2026-08-16).
//
// 무엇을 지키려는 검사인가:
// ① 축소가 **실패해도 저장을 막지 않는다** — 사용자가 잃는 것(명함)이 얻는
//    것(용량)보다 크다.
// ② **작은 사진을 건드리지 않는다** — 다시 구우면 화질만 깎이고 크기는 오히려
//    늘 수 있다.
// ③ 가로세로 비가 유지된다 — 명함이 찌그러지면 안 된다.
//
// ⚠️ 이 검사로는 "서버에 축소본이 실제로 올라가는가"를 못 본다. 그건
// 플래그를 켠 빌드를 테스터가 쓴 뒤 서버 실물을 조회해야 안다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:connection_trace_ai_flutter/core/utils/card_photo_downscale.dart';

Uint8List _jpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  // 단색이면 JPEG이 극단적으로 잘 압축돼 "줄였더니 커졌다" 분기가 자주
  // 걸린다. 실제 명함처럼 잡티가 있는 그림을 만든다.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 256, (y * 13) % 256, (x * y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 100));
}

void main() {
  group('needsDownscale', () {
    test('긴 변이 1600을 넘으면 줄인다', () {
      expect(needsDownscale(2934, 1636), isTrue); // 실제 크롭 결과 크기
      expect(needsDownscale(1636, 2934), isTrue); // 회전본
    });

    test('1600 이하면 건드리지 않는다', () {
      expect(needsDownscale(1600, 900), isFalse);
      expect(needsDownscale(800, 600), isFalse);
    });
  });

  group('downscaledSize — 비를 유지한다', () {
    test('가로가 긴 사진', () {
      final s = downscaledSize(2934, 1636);
      expect(s.width, 1600);
      // 1636 * 1600 / 2934 = 892.x
      expect(s.height, 892);
    });

    test('세로가 긴 사진(회전본)', () {
      final s = downscaledSize(1636, 2934);
      expect(s.height, 1600);
      expect(s.width, 892);
    });

    test('줄일 필요가 없으면 그대로', () {
      final s = downscaledSize(1200, 800);
      expect(s.width, 1200);
      expect(s.height, 800);
    });

    test('짧은 변이 0으로 반내림되지 않는다', () {
      final s = downscaledSize(30000, 1);
      expect(s.width, 1600);
      expect(s.height, greaterThanOrEqualTo(1));
    });
  });

  group('downscaleForArchive', () {
    test('큰 사진은 실제로 작아진다', () {
      final original = _jpeg(2934, 1636);
      final out = downscaleForArchive(original);
      expect(out.length, lessThan(original.length));

      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 1600);
      expect(decoded.height, 892);
    });

    test('작은 사진은 원본을 그대로 돌려준다 — 재인코딩하지 않는다', () {
      final original = _jpeg(800, 600);
      final out = downscaleForArchive(original);
      expect(identical(out, original), isTrue);
    });

    test('디코딩할 수 없으면 원본을 그대로 — 저장을 막지 않는다', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      final out = downscaleForArchive(garbage);
      expect(identical(out, garbage), isTrue);
    });

    test('빈 바이트에도 던지지 않는다', () {
      final empty = Uint8List(0);
      expect(() => downscaleForArchive(empty), returnsNormally);
    });

    test('줄인 결과가 더 크면 원본을 쓴다', () {
      // 이미 세게 압축된 큰 사진을 품질 80으로 다시 구우면 커질 수 있다.
      final image = img.Image(width: 2000, height: 1200);
      final tiny = Uint8List.fromList(img.encodeJpg(image, quality: 1));
      final out = downscaleForArchive(tiny);
      expect(out.length, lessThanOrEqualTo(tiny.length));
    });
  });

  group('⚠️ 1,600px 경계 — 축소를 건너뛰는지 알 수 있어야 한다', () {
    test('정확히 1600이면 건너뛴다 — 설계상 맞지만 원본이 그대로 간다', () {
      final original = _jpeg(1600, 900);
      final r = downscaleForArchiveWithInfo(original);
      expect(r.downscaled, isFalse);
      expect(identical(r.bytes, original), isTrue);
    });

    test('1601이면 줄인다', () {
      final r = downscaleForArchiveWithInfo(_jpeg(1601, 900));
      expect(r.downscaled, isTrue);
    });

    test('큰 사진은 줄였다고 알려 준다', () {
      final r = downscaleForArchiveWithInfo(_jpeg(2934, 1636));
      expect(r.downscaled, isTrue);
      expect(r.bytes.length, lessThan(_jpeg(2934, 1636).length));
    });
  });

  group('상수 — 값이 바뀌면 비용 계산이 어긋난다', () {
    test('긴 변 1600 · 품질 80', () {
      // 이 값들은 비용 스펙(card-photo-storage-cost-spec-2026-08-16.md)의
      // 계산 전제다. 바꾸려면 그 문서의 원가도 함께 고쳐야 한다.
      expect(kCardPhotoMaxLongSide, 1600);
      expect(kCardPhotoJpegQuality, 80);
    });
  });
}

// ⚠️ 1,600px 경계 — 손익/원가 세션이 찾은 위험(2026-08-16).
//
// 긴 변이 정확히 1,600이면 축소를 건너뛰고 원본(quality:100)이 그대로 올라간다.
// 설계는 맞지만(작은 사진을 다시 구우면 화질만 깎인다) **그 사실을 알 수
// 있어야** 한다 — 기기에 따라 조용히 일어나기 때문이다.
