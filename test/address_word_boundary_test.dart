/// 주소 표시 글자(`로`·`길`·`동`·`구`)는 **낱말 끝에 있어야 한다**
/// (2026-08-29, globe2030님 제보로 실물 재현).
///
/// ## 무엇이 문제였나
///
/// 규칙이 `(서울|…)…(로|길|동|구)…` 였는데, **낱말 안에 든 글자**도 걸렸다.
///
/// ```
/// FC서울프로축구단 | GS칼텍스서울Kixx배구단
///    └서울      └「프로」의 로   └「축구단」의 구     → 주소로 잡혔다
/// ```
///
/// 🚨 **진짜 주소 줄이 바로 아래 있었는데도 먼저 걸린 쪽이 이겼다.**
///
/// ✅ **실물**: 그 명함에서 **주소 칸에 회사 이름이** 들어가 있었다.
/// globe2030님 표현으로 *"직함과 부서 빼고 모두 잘못된 상태"*였고, 나중에
/// *"휴대폰까지 정상"*으로 좁혀졌다.
///
/// 📌 **맞은 셋이 왜 맞았는지가 단서였다** — 직함·부서는 **키워드**로, 휴대폰은
/// **숫자 모양**으로 찾으니 줄이 엉켜도 걸린다. **이름·회사·주소처럼 줄을 골라
/// 쓰는 칸만 틀렸다.**
library;

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('🚨 낱말 안에 든 글자를 주소로 보지 않는다', () {
    test('⭐ 회사 이름 줄을 주소로 집지 않는다 — 실물 재현', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '마케팅팀 | 대리',
        'FC서울프로축구단 | GS칼텍스서울Kixx배구단',
        '서울시 마포구 월드컵로 240 서울월드컵경기장',
        'mobile 010-0000-0000',
      ]);
      expect(r.address, isNotNull);
      expect(
        r.address!.contains('축구단'),
        isFalse,
        reason: '「프로」의 로, 「축구단」의 구에 걸려 회사 줄이 주소가 됐다',
      );
      expect(r.address!.contains('마포구'), isTrue);
    });

    test('「프로」만 있는 줄은 주소가 아니다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '서울프로덕션',
        '010-0000-0000',
      ]);
      expect(r.address ?? '', isEmpty, reason: '주소로 보면 안 된다');
    });
  });

  group('멀쩡한 주소는 그대로 잡는다', () {
    test('도로명 + 건물번호', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '서울시 마포구 월드컵로 240',
        '010-0000-0000',
      ]);
      expect(r.address, contains('월드컵로'));
    });

    test('숫자가 붙어 있어도(테헤란로123)', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '서울특별시 강남구 테헤란로123',
        '010-0000-0000',
      ]);
      expect(r.address, contains('테헤란로'));
    });

    test('동으로 끝나는 지번 주소', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '서울시 마포구 상암동 1602',
        '010-0000-0000',
      ]);
      expect(r.address, contains('상암동'));
    });

    test('구 뒤에 쉼표가 와도', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        '경기도 성남시 분당구, 판교로 235',
        '010-0000-0000',
      ]);
      expect(r.address, isNotNull);
    });
  });
}
