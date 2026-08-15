import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/ocr_origin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자동 인식 표시(F-09)의 **판정 규칙**과 **연결 상태**를 고정한다.
///
/// 이 표시는 틀려도 화면이 멀쩡하고 저장도 정상이라 눈으로는 안 잡힌다 —
/// 표시가 안 붙거나(자동 인식인데 안 보임) 잘못 남는(고쳤는데 그대로) 것 둘 다
/// "코드는 맞는데 실물이 틀린" 유형이다(CLAUDE.md 4절). 그래서 규칙과 배선을
/// 함께 검사한다.
void main() {
  group('자동 인식 표시 판정', () {
    const snapshot = {
      'name': '홍길동',
      'company': '카카오',
      'empty': '',
    };

    test('⭐ 자동 인식이 채운 값 그대로면 표시한다', () {
      expect(
        isStillOcrValue(key: 'name', snapshot: snapshot, currentText: '홍길동'),
        isTrue,
      );
    });

    test('⭐ 사용자가 고치면 표시가 사라진다', () {
      expect(
        isStillOcrValue(key: 'name', snapshot: snapshot, currentText: '홍길순'),
        isFalse,
        reason: '한 글자만 달라져도 더 이상 자동 인식 값이 아니다',
      );
    });

    test('사용자가 지우면 표시가 사라진다', () {
      expect(
        isStillOcrValue(key: 'name', snapshot: snapshot, currentText: ''),
        isFalse,
      );
    });

    test('앞뒤 공백은 무시한다', () {
      expect(
        isStillOcrValue(key: 'name', snapshot: snapshot, currentText: '  홍길동 '),
        isTrue,
        reason: '스냅샷은 trim()된 값이라, 공백까지 따지면 공백 하나에 표시가 '
            '사라져 사용자에겐 깜빡이는 것으로 보인다',
      );
    });

    test('파서가 못 채운 칸은 표시하지 않는다', () {
      expect(
        isStillOcrValue(key: 'title', snapshot: snapshot, currentText: '팀장'),
        isFalse,
        reason: '스냅샷에 없는 키 — 사용자가 직접 친 값이다',
      );
    });

    test('스냅샷 값이 빈 문자열이면 채운 것으로 치지 않는다', () {
      expect(
        isStillOcrValue(key: 'empty', snapshot: snapshot, currentText: ''),
        isFalse,
      );
    });

    test('자동 인식 대상이 아닌 칸(key 없음)은 언제나 표시하지 않는다', () {
      expect(
        isStillOcrValue(key: null, snapshot: snapshot, currentText: '아무 값'),
        isFalse,
        reason: '태그·관심사·메모는 파서가 채우지 않는다',
      );
    });

    test('스냅샷이 비어 있으면(스캔 전) 아무 표시도 없다', () {
      expect(
        isStillOcrValue(key: 'name', snapshot: const {}, currentText: '홍길동'),
        isFalse,
      );
    });
  });

  group('폼 배선', () {
    // 파서가 채우는 키 목록과 화면이 표시에 쓰는 키 목록은 **같아야** 한다.
    // 새 필드를 추가하면서 한쪽만 손대면, 자동 인식이 채우는데 표시는 안 붙는
    // (또는 그 반대) 상태가 조용히 생긴다. 사람이 알아채기 어려운 종류라
    // 소스를 훑어 고정한다 — no_seeded_form_defaults_test.dart와 같은 방식.
    final source = File(
      'lib/presentation/features/wallet/views/add_card_modal_view.dart',
    ).readAsStringSync();

    Set<String> keysIn(RegExp pattern) => pattern
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    test('⭐ 파서가 채우는 칸과 표시를 붙인 칸이 정확히 일치한다', () {
      // `fieldSources` 맵의 키 — 파서가 실제로 채우는 칸.
      final filled = keysIn(RegExp(r"'(\w+)': \(_\w+Controller, result\."));
      // `_buildFormField(... ocrKey: 'x' ...)` — 표시를 붙인 칸.
      final badged = keysIn(RegExp(r"ocrKey: '(\w+)'"));

      expect(
        filled,
        isNotEmpty,
        reason: '패턴이 안 맞으면 이 테스트가 아무것도 검사하지 않는 채 통과한다',
      );
      expect(
        badged,
        equals(filled),
        reason: '파서가 채우는 칸(${filled.length}개)과 표시를 붙인 칸'
            '(${badged.length}개)이 어긋났다. 필드를 추가했다면 '
            '_buildFormField에 ocrKey를, initState에 _watchOcrBadge를 함께 넣을 것',
      );
    });

    test('⭐ 표시를 붙인 칸은 값 변화 감시도 걸려 있다', () {
      final badged = keysIn(RegExp(r"ocrKey: '(\w+)'"));
      final watched = keysIn(RegExp(r"_watchOcrBadge\('(\w+)'"));

      expect(
        watched,
        equals(badged),
        reason: '감시가 빠진 칸은 사용자가 고쳐도 표시가 남는다 — '
            '"고치면 사라진다"는 약속이 깨진다',
      );
    });
  });
}
