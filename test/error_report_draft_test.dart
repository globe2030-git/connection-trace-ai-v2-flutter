import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/error_report_draft.dart';

void main() {
  group('오류 신고 초안 (P2-11)', () {
    test('제목은 어느 화면이었는지 한눈에 보인다', () {
      expect(buildErrorReportSubject('AI 대화 가이드'), '[오류] AI 대화 가이드');
    });

    test('본문에 화면·코드·설명·시각·버전이 모두 들어간다', () {
      final body = buildErrorReportBody(
        code: 'ai-timeout',
        codeLabel: 'AI 응답이 제때 오지 않음',
        screenLabel: 'AI 대화 가이드',
        occurredAt: DateTime(2026, 9, 2, 14, 5),
        appVersion: '1.0.0 (12) · a1b2c3d',
      );
      expect(body, contains('AI 대화 가이드'));
      expect(body, contains('ai-timeout'));
      expect(body, contains('AI 응답이 제때 오지 않음'));
      expect(body, contains('2026-09-02 14:05'));
      expect(body, contains('1.0.0 (12) · a1b2c3d'));
    });

    test('코드만 적지 않는다 — 사람이 읽을 설명이 코드 옆에 붙는다', () {
      final body = buildErrorReportBody(
        code: 'ai-quota-exceeded',
        codeLabel: 'AI 사용 한도에 도달',
        screenLabel: 'AI 대화 가이드',
        occurredAt: DateTime(2026, 9, 2),
        appVersion: '1.0.0',
      );
      // 영문 코드만 있으면 사용자가 자기가 무엇을 보내는지 모른 채 보낸다.
      expect(body, contains('ai-quota-exceeded (AI 사용 한도에 도달)'));
    });

    test('한 자리 수 월·일·시·분은 0을 채운다', () {
      final body = buildErrorReportBody(
        code: 'x',
        codeLabel: 'y',
        screenLabel: 'z',
        occurredAt: DateTime(2026, 1, 2, 3, 4),
        appVersion: 'v',
      );
      expect(body, contains('2026-01-02 03:04'));
    });

    test('앱이 쓴 것임을 밝히고, 고쳐도 된다고 알린다', () {
      final body = buildErrorReportBody(
        code: 'ai-network',
        codeLabel: '앱과 서버 사이 통신 실패',
        screenLabel: 'AI 대화 가이드',
        occurredAt: DateTime(2026, 9, 2),
        appVersion: '1.0.0',
      );
      // 채우기만 하고 보내지 않는다는 것이 화면 글로도 보여야 한다 — 앱이 만든
      // 문장이 사용자 데이터로 그대로 저장된 전례가 이 저장소에 둘 있다.
      expect(body, contains('앱이 자동으로 적은'));
      expect(body, contains('고치거나 지우셔도 됩니다'));
    });
  });

  group('🚨 제3자 개인정보가 실려 나가지 않는다 (소스 검사)', () {
    // ReconnectPriorityService의 "가짜 이유 금지" 테스트와 같은 방식이다 —
    // 동작이 아니라 **소스에 그런 코드를 쓸 수 없게** 막는다. 이 초안은 문의
    // 본문으로 서버에 저장되므로, 명함 주인의 정보가 한 글자도 섞이면 안 된다.

    test('초안 생성기는 명함(Contact)을 아예 모른다', () {
      final src = File('lib/core/utils/error_report_draft.dart').readAsStringSync();
      expect(
        src.contains('ContactModel'),
        isFalse,
        reason: '초안 생성기가 명함을 받으면 무엇을 싣는지 이 파일 밖에서 정해진다',
      );
      expect(src.contains('import'), isFalse, reason: '의존성이 없어야 담을 것도 없다');
    });

    test('오류 신고 핸들러가 명함이나 예외 원문을 싣지 않는다', () {
      final src = File(
        'lib/presentation/features/briefing/views/briefing_overlay_view.dart',
      ).readAsStringSync();
      final start = src.indexOf('Future<void> _reportError()');
      expect(start, isNot(-1), reason: '_reportError 를 찾지 못했다');
      // 함수 본문만 잘라 본다. 뒤에 오는 다음 메서드 주석 전까지.
      final end = src.indexOf('/// F-08', start);
      expect(end, greaterThan(start));
      final body = src.substring(start, end);

      expect(
        body.contains('widget.contact'),
        isFalse,
        reason: '명함 주인의 정보를 문의 본문에 실으면 제3자 개인정보가 서버에 저장된다',
      );
      expect(
        body.contains('_errorMessage'),
        isFalse,
        reason: '_errorMessage 는 예외 원문을 담을 수 있다 — 코드만 싣는다',
      );
    });
  });
}
