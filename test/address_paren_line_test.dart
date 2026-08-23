// **괄호만으로 이루어진 줄**을 상세주소에 이어 붙이는 규칙(추가 428).
//
// ## 무엇이 문제였나
//
// 명함은 법정동·건물명을 `(역삼동, 어반벤치빌딩)`처럼 **따로 한 줄로** 인쇄하는
// 일이 흔하다. 그런데 상세주소를 채우는 폴백들이 전부 `addressDetail == null`
// 일 때만 돌아서, 그 줄이 오기 전에 이미 `2층`이 잡혀 있으면 **통째로
// 버려졌다.**
//
// ⚠️ **괄호라고 다 주소가 아니다.** 명함의 괄호는 영문 병기(`(Marketing
// Company)`)나 영문 이름(`(Daniel)`)에도 쓰인다. 아무 괄호나 붙이면
// 상세주소가 엉뚱한 말로 오염된다 — 아래 검사들이 그 경계를 잠근다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  group('괄호 줄 이어 붙이기', () {
    test('⭐ 법정동·건물명 괄호 줄이 상세주소에 붙는다', () {
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '2층',
        '(역삼동, 어반벤치빌딩)',
      ]);
      expect(r.addressDetail, contains('2층'));
      expect(r.addressDetail, contains('역삼동'));
      expect(r.addressDetail, contains('어반벤치빌딩'));
    });

    test('상세주소가 비어 있으면 기존 경로가 처리한다 — 중복해 붙이지 않는다', () {
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '(역삼동, 어반벤치빌딩)',
      ]);
      // 어느 경로로 들어가든 한 번만 들어가야 한다.
      final n = '역삼동'.allMatches(r.addressDetail).length;
      expect(n, lessThanOrEqualTo(1));
    });
  });

  group('⚠️ 괄호라고 다 붙이지 않는다 — 이 경계가 규칙의 절반이다', () {
    test('영문 병기 괄호는 안 붙는다', () {
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '2층',
        '(Marketing Company)',
      ]);
      expect(r.addressDetail, isNot(contains('Marketing')));
    });

    test('영문 이름 괄호는 안 붙는다', () {
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '2층',
        '(Daniel)',
      ]);
      expect(r.addressDetail, isNot(contains('Daniel')));
    });

    test('괄호 안이 주소 조각이 아니면 안 붙는다', () {
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '2층',
        '(대표이사)',
      ]);
      expect(r.addressDetail, isNot(contains('대표이사')));
    });

    test('줄 전체가 괄호가 아니면 안 붙는다', () {
      // 앞뒤에 다른 글자가 있으면 다른 칸의 값일 수 있다.
      final r = parse([
        '홍길동',
        '서울시 강남구 테헤란로 325',
        '2층',
        '소속 (역삼동, 어반벤치빌딩) 담당',
      ]);
      expect(r.addressDetail, isNot(contains('어반벤치빌딩')));
    });
  });
}
