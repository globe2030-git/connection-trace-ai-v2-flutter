// "같은 경로에 덮어쓴 이미지가 갱신되는가"를 캐시 수준에서 검증한다.
//
// 이 결함(통합본 E-07)은 **코드가 정상 동작하는데 화면만 옛것인** 유형이라
// 위젯을 그려 보는 것만으로는 안 잡힌다 — 저장도 setState도 다 성공한다.
// 문제는 `FileImage`의 캐시 키가 **파일 경로**라는 점 하나뿐이다.
// 그래서 캐시에서 실제로 빠지는지를 직접 본다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/image_file_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 투명 PNG. 디코딩만 되면 되므로 가장 작은 것을 쓴다.
final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('덮어쓴 이미지 경로를 캐시에서 비운다', (tester) async {
    final dir = Directory.systemTemp.createTempSync('img_cache_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/avatar.jpg')..writeAsBytesSync(_tinyPng);

    final provider = FileImage(file);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();

    // 실제 디코딩이 일어나야 캐시에 들어간다 — runAsync 안에서 돌린다.
    await tester.runAsync(() async {
      final completer = Completer<void>();
      provider
          .resolve(ImageConfiguration.empty)
          .addListener(
            ImageStreamListener(
              (_, _) {
                if (!completer.isCompleted) completer.complete();
              },
              onError: (error, _) {
                if (!completer.isCompleted) completer.completeError(error);
              },
            ),
          );
      await completer.future;
    });

    expect(
      cache.containsKey(provider),
      isTrue,
      reason: '먼저 캐시에 들어가 있어야 이 테스트가 의미가 있다',
    );

    // 파일 내용을 바꿔도 경로가 같으면 캐시는 그대로다 — 그래서 비워야 한다.
    file.writeAsBytesSync(_tinyPng);
    await tester.runAsync(() => evictImageFileCache(file.path));

    expect(
      cache.containsKey(provider),
      isFalse,
      reason: '캐시가 남아 있으면 화면은 계속 옛 사진을 보여준다',
    );
  });
}
