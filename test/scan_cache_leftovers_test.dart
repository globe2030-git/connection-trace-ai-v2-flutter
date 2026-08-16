// 이미 쌓인 캐시 잔재 정리 검사(2026-08-16, 추가 248).
//
// 무엇을 지키려는 검사인가:
// ① **우리 것만** 지운다 — 다른 구성요소의 캐시 폴더(WebView·fm_cache)를 지우면
//    그쪽이 깨진다. 오늘 파일 주인을 이름 모양으로 짐작해 두 번 틀렸으므로,
//    "안 지운다"는 쪽을 검사로 못 박는다.
// ② **방금 만든 것은 안 지운다** — 지금 스캔에 쓰이는 중일 수 있다.
// ③ **탈퇴에서는 전부** 지운다 — 방침이 "탈퇴 시 전부 파기"라고 적고 있다.
// ④ **던지지 않는다** — 정리 실패로 앱이 막히면 안 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/scan_temp_cleanup.dart';

void main() {
  group('이름 판정 — 우리 것만', () {
    test('카메라 원본', () {
      expect(isCameraCaptureName('CAP167556052032855569.jpg'), isTrue);
      expect(isCameraCaptureName('CAP_old.JPG'), isTrue);
      // 확장자가 다르면 카메라 원본이 아니다.
      expect(isCameraCaptureName('CAPTION.txt'), isFalse);
      expect(isCameraCaptureName('contact_card_1.enc'), isFalse);
    });

    test('image_picker 재인코딩 사본', () {
      expect(isScaledCopyName('scaled_743.png'), isTrue);
      expect(isScaledCopyName('743.png'), isFalse);
    });

    test('image_picker 폴더는 UUID 모양만', () {
      expect(
        isPickerCacheDirName('0429937d-4357-44c5-9185-8119cc4f57da'),
        isTrue,
      );
      // ⚠️ 실기기에 함께 있던 다른 구성요소의 캐시 폴더들 — 절대 걸리면 안 된다.
      expect(isPickerCacheDirName('WebView'), isFalse);
      expect(isPickerCacheDirName('Crash Reports'), isFalse);
      expect(isPickerCacheDirName('fm_cache'), isFalse);
      expect(isPickerCacheDirName('flutter_engine'), isFalse);
      // 모양이 비슷해도 자릿수가 다르면 아니다.
      expect(isPickerCacheDirName('0429937d-4357-44c5-9185'), isFalse);
    });
  });

  group('sweepPickerAndCameraLeftovers — 실제 폴더에서', () {
    late Directory cache;
    final old = DateTime.now().subtract(const Duration(hours: 3));

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('scan_cache_test');
    });

    tearDown(() async {
      if (cache.existsSync()) await cache.delete(recursive: true);
    });

    test('오래된 촬영 원본·재인코딩 사본을 지우고 남의 것은 남긴다', () async {
      final cap = File('${cache.path}/CAP123.jpg')..writeAsStringSync('a');
      final scaled = File('${cache.path}/scaled_743.png')
        ..writeAsStringSync('b');
      final fresh = File('${cache.path}/CAP999.jpg')..writeAsStringSync('c');
      final theirs = File('${cache.path}/flutter.impeller.vkcache')
        ..writeAsStringSync('d');
      cap.setLastModifiedSync(old);
      scaled.setLastModifiedSync(old);
      theirs.setLastModifiedSync(old);

      final removed = await sweepPickerAndCameraLeftovers(cache);

      expect(removed, 2);
      expect(cap.existsSync(), isFalse);
      expect(scaled.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue, reason: '방금 찍은 것은 남아야 한다');
      expect(theirs.existsSync(), isTrue, reason: '남의 파일은 남아야 한다');
    });

    test('UUID 폴더 안 사진을 지우고, 비면 폴더까지 지운다', () async {
      final dir = Directory('${cache.path}/0429937d-4357-44c5-9185-8119cc4f57da')
        ..createSync();
      final photo = File('${dir.path}/642.png')..writeAsStringSync('a');
      photo.setLastModifiedSync(old);

      final removed = await sweepPickerAndCameraLeftovers(cache);

      expect(removed, 1);
      expect(photo.existsSync(), isFalse);
      expect(dir.existsSync(), isFalse, reason: '비면 폴더도 정리한다');
    });

    test('⚠️ UUID 폴더에 사진 아닌 것이 있으면 그것도 폴더도 남긴다', () async {
      final dir = Directory('${cache.path}/04b0558f-85e6-483a-8125-23c7233bd81f')
        ..createSync();
      final photo = File('${dir.path}/753.jpg')..writeAsStringSync('a');
      final other = File('${dir.path}/데이터.bin')..writeAsStringSync('b');
      photo.setLastModifiedSync(old);
      other.setLastModifiedSync(old);

      final removed = await sweepPickerAndCameraLeftovers(cache);

      expect(removed, 1);
      expect(photo.existsSync(), isFalse);
      expect(other.existsSync(), isTrue, reason: '이미지가 아니면 손대지 않는다');
      expect(dir.existsSync(), isTrue, reason: '우리 것이 아닐 수 있어 폴더를 남긴다');
    });

    test('⚠️ UUID가 아닌 폴더는 열어 보지도 않는다', () async {
      final dir = Directory('${cache.path}/WebView')..createSync();
      final theirs = File('${dir.path}/aa.png')..writeAsStringSync('a');
      theirs.setLastModifiedSync(old);

      final removed = await sweepPickerAndCameraLeftovers(cache);

      expect(removed, 0);
      expect(theirs.existsSync(), isTrue);
    });

    test('탈퇴 정리(maxAge 0)는 방금 만든 것까지 쓸어낸다', () async {
      final cap = File('${cache.path}/CAP123.jpg')..writeAsStringSync('a');
      final dir = Directory('${cache.path}/8f7f7e91-6efb-41a9-8ebb-66c194c96cf7')
        ..createSync();
      final photo = File('${dir.path}/907.png')..writeAsStringSync('b');
      final theirs = File('${cache.path}/flutter.impeller.vkcache')
        ..writeAsStringSync('c');

      final removed = await sweepPickerAndCameraLeftovers(
        cache,
        maxAge: Duration.zero,
      );

      expect(removed, 2);
      expect(cap.existsSync(), isFalse);
      expect(photo.existsSync(), isFalse);
      expect(theirs.existsSync(), isTrue, reason: '탈퇴에서도 남의 파일은 안 지운다');
    });

    test('없는 폴더에도 던지지 않는다', () async {
      expect(await sweepPickerAndCameraLeftovers(Directory('/없는/폴더')), 0);
    });
  });
}
