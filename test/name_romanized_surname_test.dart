// 같은 줄의 **로마자가 한글 성씨의 표기**와 맞으면 그 낱말을 이름으로 확정한다
// (추가 429).
//
// ## 왜 이 신호인가
//
// 실측 96장에서 이름을 못 맞힌 20장 중 **낱말 하나로 멀쩡히 서 있는데 못 고른
// 것이 5장**이었고, **다섯 장 전부** 한글 이름 옆에 로마자가 같은 줄에 있었다.
// 그중 넷이 `Sun-Kyoung Lee`·`Yoon Choi`처럼 **그 사람 이름의 로마자 표기**다.
// 한국 명함에서 아주 흔한 모양인데 파서가 확신하지 못해 다른 줄에 밀렸다.
//
// ⭐ 나머지 하나는 `Ma soft`(로고 오독)였고 **성씨 표기와 안 맞아 저절로
// 빠진다** — 크기·위치로는 못 가르던 것을 글자가 가른다.
//
// ## ⚠️ 이 표에는 표준이 없다
//
// `이`는 Lee·Yi·Rhee·Li로 쓰고, `Go`·`No`·`Won`·`Min`은 영어 단어와 겹친다.
// 그래서 **한글 이름 모양 낱말이 같은 줄에 있을 때만** 보고 **정확히 같을
// 때만** 인정한다. 아래 검사들이 그 경계를 잠근다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  group('로마자 성씨 신호', () {
    test('⭐ 한글 이름 + 그 이름의 로마자면 확정한다', () {
      final r = parse(['이선경 Sun-Kyoung Lee', '02-123-4567']);
      expect(r.name, '이선경');
      expect(r.parseShape?.nameSource, OcrNameSource.romanizedSurname);
    });

    test('⭐ 성씨가 뒤에 오는 표기도 잡는다', () {
      final r = parse(['조용호 Cho Yong Ho', '02-123-4567']);
      expect(r.name, '조용호');
    });

    test('⭐ 한글 이름 모양 낱말이 둘일 때 로마자가 가리키는 쪽을 고른다', () {
      // 이 신호가 없으면 먼저 오는 줄이 이긴다 — 실측 96장에서 그 때문에
      // 3장이 엉뚱한 줄을 이름으로 삼았다.
      final r = parse([
        '영업부팀',
        '박상현 Sang-Hyun Park',
        '02-123-4567',
      ]);
      expect(r.name, '박상현');
    });
  });

  group('⚠️ 걸러지는 것 — 이 경계가 신호의 값이다', () {
    test('로고 오독은 성씨 표기와 안 맞아 빠진다', () {
      // `Ma soft`(M2SOFT 로고)는 성씨 표기 어디에도 없다.
      final r = parse(['Ma soft 마소프트', '02-123-4567']);
      expect(r.parseShape?.nameSource, isNot(OcrNameSource.romanizedSurname));
    });

    test('로마자만 있고 한글 이름 낱말이 없으면 안 본다', () {
      // 표기 목록에는 `lee`가 있지만 같은 줄에 한글 이름 낱말이 없다.
      final r = parse(['Lee Consulting Group', '02-123-4567']);
      expect(r.parseShape?.nameSource, isNot(OcrNameSource.romanizedSurname));
    });

    test('⚠️ 부분 일치는 인정하지 않는다', () {
      // `한`의 표기 `han`이 `Handong`에 들어 있지만 낱말이 다르다.
      // 부분 일치를 허용하면 엉뚱한 영단어마다 걸린다.
      final r = parse(['한동훈 Handong Corp', '02-123-4567']);
      expect(r.parseShape?.nameSource, isNot(OcrNameSource.romanizedSurname));
    });

    test('이미 강한 근거로 이름을 찾았으면 건드리지 않는다', () {
      final r = parse(['대표이사 김철수', '이선경 Sun-Kyoung Lee']);
      expect(r.name, '김철수');
    });
  });
}
