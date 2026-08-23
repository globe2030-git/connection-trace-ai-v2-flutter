// 한 줄에 나란히 인쇄된 **영문 병기**를 떼는 규칙(추가 430).
//
// ## 왜 이 규칙이 있나
//
// 2026-08-23에 사용자가 **회사명 정답을 한글 주 표기로 통일**했다(추가 424).
// 정답이 `케이스랩`인데 파서가 `케이스랩 K.ACE LAB`을 내면 틀린 것이 된다.
//
// ⚠️ **정답지를 가른 규칙과 같은 규칙이어야 한다.** 다르면 채점기와 파서가
// 서로 다른 답을 옳다고 본다 — 2026-08-23 하루에 채점기에서 세 번 겪은
// 종류의 사고다.
//
// ## ⚠️ "손대지 않는 줄"이 규칙의 절반이다
//
// 96장 전 필드 전후 대조에서 **직함 줄을 안 빼면 4장이 깨졌다.** 아래 검사는
// 그 조건들을 하나씩 잠근다 — 조건이 사라지면 조용히 다른 칸이 망가진다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  group('영문 병기 떼기', () {
    test('⭐ 한글명 뒤에 붙은 영문명을 뗀다', () {
      final r = parse(['케이스랩 K.ACE LAB', '홍길동', '010-1234-5678']);
      expect(r.company, '케이스랩');
    });

    test('⭐ 괄호로 묶인 영문 병기도 뗀다', () {
      final r = parse([
        '서울관광재단 (STO, Seoul Tourism Organization)',
        '홍길동',
        '010-1234-5678',
      ]);
      expect(r.company, '서울관광재단');
    });

    test('⚠️ 괄호 안에 한글이 있으면 뗀 게 아니라 법인 표기다', () {
      // 이 조건이 없으면 `(주)컴플러스`가 `컴플러스`가 된다. 추가 424에서
      // 정답지를 고칠 때 실제로 낸 버그이고 적용 직전에 잡았다.
      final r = parse(['(주)컴플러스 comm.Plus', '홍길동', '010-1234-5678']);
      expect(r.company, '(주)컴플러스');
    });

    test('⚠️ 영문 전용 회사명은 손대지 않는다', () {
      // 한글이 없으면 그 영문이 곧 회사명이다 — 떼면 값이 사라진다.
      final r = parse(['Commplus Inc.', '홍길동', '010-1234-5678']);
      expect(r.company, contains('Commplus'));
    });
  });

  group('⚠️ 손대지 않는 줄 — 이 조건들이 규칙의 절반이다', () {
    test('직함이 든 줄은 건드리지 않는다', () {
      // 96장 실측에서 이 조건이 없을 때 직함 4장이 깨졌다. 영문 직함이
      // 한글과 한 줄에 있으면 같이 떨어져 나간다.
      final r = parse([
        '홍길동',
        '이사 Business Development',
        '010-1234-5678',
      ]);
      expect(r.title, contains('Business Development'));
    });

    test('이메일 줄은 건드리지 않는다', () {
      final r = parse(['담당 hong@example.com', '홍길동', '010-1234-5678']);
      expect(r.email, 'hong@example.com');
    });

    test('홈페이지 줄은 건드리지 않는다', () {
      final r = parse(['누리집 www.example.com', '홍길동', '010-1234-5678']);
      expect(r.website, contains('example.com'));
    });

    test('숫자가 여럿인 줄(주소·번호)에서 주소가 온전히 남는다', () {
      // ⚠️ 처음에 `Gangnam-gu`가 남는지로 검사했다가 깨졌다. 그 영문은 **이
      // 규칙이 아니라** 이미 있던 주소 잡음 제거(`_stripBrandNoiseFromAddress
      // Detail`)가 떼는 것이다 — 이 변경 **이전에도** 똑같이 떨어졌다.
      //
      // 이 규칙이 지켜야 할 것은 "주소 줄을 건드려 주소를 망가뜨리지 않는
      // 것"이므로 그것을 검사한다.
      final r = parse([
        '서울시 강남구 테헤란로 123 Gangnam-gu',
        '홍길동',
        '010-1234-5678',
      ]);
      expect(r.address, '서울시 강남구 테헤란로 123');
    });
  });

  test('⚠️ 다 떼면 남는 게 없을 때는 원문을 그대로 둔다', () {
    // 값이 없는 것보다 낫다 — 추가 183과 반대 방향의 손실을 막는다.
    final r = parse(['㈜ ABC', '홍길동', '010-1234-5678']);
    expect(r.company.isNotEmpty, isTrue);
  });
}
