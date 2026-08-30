// 회사명이 직함 줄 한가운데 박혀 있는 명함 (추가 615).
//
// ```
// K.ACE LAB 케이스랩 개발실장     ← 로고 · 회사 · 직함이 한 줄이다
// ```
//
// ⭐ **「고르기」로는 못 닿는 자리다.** 자국을 심어 보니 `케이스랩` 이
// `leftover` 에 **아예 오지 않았다** — 이 줄이 통째로 직함으로 잡혀서다.
// 그동안 회사 칸에는 엉뚱한 값이 들어갔다(사람 영문 이름 · 주소 조각).
//
// ⚠️ 이 검사의 반은 **하지 않기로 한 것**을 지킨다. 규칙을 넓히면 직함 칸이
// 흔들린다 — 직함은 이 파서에서 회사 다음으로 나쁜 칸이라 더 잃기 쉽다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('⭐ 앞이 영문·가운데가 회사·끝이 직함이면 갈라 담는다', () {
    test('K.ACE LAB 케이스랩 개발실장 (IMG_4255)', () {
      final r = OcrScannerService.parseLinesForTesting([
        '박홍규',
        'Hong Gyu, Park',
        'K.ACE LAB 케이스랩 개발실장',
        'E. hg.park@kacelab.com',
        '온라인 기획',
      ]);
      expect(r.company, '케이스랩');
      expect(r.title, '개발실장');
      expect(r.name, '박홍규');
    });

    test('K.ACE LAB 케이스랩 대표 (IMG_4256)', () {
      final r = OcrScannerService.parseLinesForTesting([
        '강승혜',
        'Seung Hye, Kang',
        'K.ACE LAB 케이스랩 대표',
        'E. canksh@kacelab.com',
      ]);
      expect(r.company, '케이스랩');
      expect(r.title, '대표');
    });
  });

  group('🚨 가운데가 부서면 손대지 않는다 — 직함 칸을 흔들지 않으려는 것이다', () {
    test('Manager 서비스구매팀 — 가운데가 부서 모양이다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        'Manager 서비스구매팀 이상화',
        '02-1234-5678',
      ]);
      expect(r.company, isNot('서비스구매팀'));
    });

    test('끝이 직함 낱말이 아니면 손대지 않는다', () {
      final r = OcrScannerService.parseLinesForTesting([
        '홍길동',
        'ABC 서울사무소 광화문',
        '02-1234-5678',
      ]);
      expect(r.company, isNot('서울사무소'));
    });
  });
}
