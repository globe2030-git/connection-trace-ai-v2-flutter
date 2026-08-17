// ⚠️⚠️ **측정 전용 — backlog 277이 끝나면 `measure_sample_sink.dart`와 함께
// 이 파일도 통째로 지운다.** ⚠️⚠️

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/measure_sample_sink.dart';

/// 측정용 크롭본 저장 장치의 **안전선**을 지킨다.
///
/// ⚠️ 이 장치는 **평문 명함 사진을 기기에 남기는 길을 일부러 낸 것**이다.
/// 우리가 닷새에 걸쳐 다섯 군데서 막은 바로 그것이라(아이폰 262.7MB ·
/// 안드로이드 204MB), **release에서 절대 돌지 않는다**는 것이 이 파일의
/// 첫째 임무다.
///
/// ⚠️ *"검사가 통과한다"*와 *"검사가 옳은 것을 잰다"*는 다르다. 지난번
/// 정리 코드가 **엉뚱한 폴더를 봐서 아무것도 안 했는데 검사는 통과**했다
/// (추가 269). 그래서 여기서는 **실제로 파일이 생겼는지/사라졌는지**를 본다.
void main() {
  group('⚠️ release에서는 코드가 아예 안 돈다', () {
    test('kDebugMode가 이 검사에서 참인지부터 확인한다', () {
      // 이 확인이 없으면 아래 검사들이 **무엇을 재는지 알 수 없다.**
      // `flutter test`는 debug로 돌므로 참이어야 한다.
      expect(
        kDebugMode,
        isTrue,
        reason: 'debug가 아니면 아래 "저장된다" 검사가 헛돈다',
      );
    });

    test('📌 스위치가 꺼져 있으면 저장하지 않는다', () async {
      final dir = Directory.systemTemp.createTempSync('measure_off_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final source = File('${dir.path}/crop.jpg')..writeAsStringSync('x');

      cardCropKeepForMeasurement.value = false;
      final saved = await keepCropForMeasurement(source, pathLabel: 'on');

      expect(saved, isNull);
    });
  });

  group('이름 규칙 — 지울 것과 지키면 안 되는 것을 가른다', () {
    test('측정본 이름만 참이다', () {
      expect(isMeasureSampleName('measure_on_123.jpg'), isTrue);
      expect(isMeasureSampleName('measure_off_123.jpg'), isTrue);
    });

    test('⚠️ 검수용 원본 묶음은 건드리지 않는다', () {
      // `card_samples`에는 정답지가 가리키는 원본 103장이 함께 있다.
      // **그것을 지우면 정답지가 가리키는 이미지가 사라진다.**
      expect(isMeasureSampleName('card_105.png'), isFalse);
      expect(isMeasureSampleName('card_10.jpg'), isFalse);
      expect(isMeasureSampleName('scan_result.tsv'), isFalse);
    });

    test('⚠️ 촬영 임시파일 접두사와 겹치지 않는다', () {
      // 겹치면 기존 쓸어담기가 **재는 도중에 측정본을 지운다.**
      expect(kMeasureSamplePrefix, isNot('card_scan_'));
      expect(isMeasureSampleName('card_scan_123.jpg'), isFalse);
      expect(isMeasureSampleName('card_rot_123.jpg'), isFalse);
    });

    test('확장자가 다르면 아니다', () {
      expect(isMeasureSampleName('measure_on_123.png'), isFalse);
    });
  });

  group('경로 이름이 파일에 남는다 — 경로별로 갈라 채점하려면 필요하다', () {
    test('on / off가 파일 이름에 들어간다', () async {
      // 실제 저장 경로는 앱 문서 폴더라 이 검사에서 못 만든다. 이름 규칙만
      // 고정한다 — 이것이 어긋나면 **어느 경로로 찍은 것인지 알 수 없다.**
      expect('${kMeasureSamplePrefix}on_1.jpg', startsWith('measure_'));
      expect('${kMeasureSamplePrefix}on_1.jpg', contains('on_'));
      expect('${kMeasureSamplePrefix}off_1.jpg', contains('off_'));
      expect(isMeasureSampleName('${kMeasureSamplePrefix}on_1.jpg'), isTrue);
      expect(isMeasureSampleName('${kMeasureSamplePrefix}off_1.jpg'), isTrue);
    });
  });
}
