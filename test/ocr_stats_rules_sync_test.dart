import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱이 보내는 값과 `firestore.rules` 의 허용 목록이 **어긋나지 않는지** 잰다.
///
/// ## 🚨 왜 필요한가 — 조용히 거부된다
///
/// `ocrStats/{uid}` 쓰기는 규칙이 `nameSource` 맵의 키를 **허용 목록으로**
/// 검사한다. 목록에 없는 키가 하나라도 있으면 **문서 전체가 거부된다.**
///
/// ⚠️ **그런데 앱은 그 실패를 삼킨다** — 통계 업로드는 부가 기능이라 실패해도
/// 화면이 안 멈춘다. 그래서 **아무도 모른 채 계속 거부된다.**
///
/// 실제로 그랬다: `OcrNameSource.romanizedSurname` 를 추가하면서(추가 429)
/// 규칙을 같이 안 고쳐, **그 경로로 이름을 뽑은 명함을 스캔할 때마다 통계가
/// 통째로 버려지고 있었다.** logcat 에서 `permission-denied` 로 잡혔고 원인을
/// 찾기까지 따로 시간이 들었다.
///
/// ## 왜 `verify_rules.py` 로는 부족한가
///
/// 그쪽은 **Firebase 서버에 규칙을 보내 평가**한다 — 실제 엔진이라 신뢰도가
/// 높지만 **네트워크와 `firebase login` 이 필요해 `flutter test` 에서 안 돈다.**
/// 이 테스트는 **파일 두 개를 읽어 대조만** 하므로 커밋할 때마다 돈다.
///
/// 📌 둘은 보는 것이 다르다 — 저쪽은 *"규칙이 의도대로 허용/거부하는가"*, 이쪽은
/// *"앱이 보내는 값이 목록에 다 있는가"*.
///
/// ⚠️ **규칙 파일의 형식이 바뀌면 이 테스트가 먼저 깨진다.** 그것을 부담이
/// 아니라 **신호**로 본다 — 형식이 바뀌었으면 사람이 한 번 봐야 한다.
/// 깨졌을 때 **무엇을 해야 하는지**를 메시지에 담는다.
///
/// 📌 *"expected 12 got 11"* 만 뜨면 다음 사람이 **형식이 바뀐 것인지 값이
/// 빠진 것인지** 모른다.
String _howToFix(String enumName, String fnName, Set<String> missing) =>
    '$enumName 에 ${missing.join(", ")} 이(가) 있는데 '
    'firestore.rules 의 $fnName 허용 목록에 없다.\n'
    '고치는 법: firestore.rules 에서 (1) $fnName 의 hasOnly 목록에 그 이름을 '
    '넣고 (2) 바로 아래에 isOcrCount 검사 줄을 같이 넣는다.\n'
    '🚨 그리고 배포해야 실제로 고쳐진다 — 병합만으로는 서버 규칙이 안 바뀐다.';

Set<String> _allowedKeys(String rules, String fnName) {
  final fn = RegExp('$fnName' r'\(m\)\s*\{.*?hasOnly\(\[(.*?)\]\)', dotAll: true)
      .firstMatch(rules);
  expect(
    fn,
    isNotNull,
    reason: '$fnName 의 hasOnly 목록을 못 찾았다 — 규칙 파일 형식이 바뀌었으면 '
        '이 테스트를 함께 고쳐야 한다',
  );
  return RegExp("'([^']+)'")
      .allMatches(fn!.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final rules = File('firestore.rules').readAsStringSync();

  group('🚨 앱이 보내는 값이 rules 허용 목록에 다 있다', () {
    test('⭐ nameSource — 하나라도 빠지면 통계가 통째로 거부된다', () {
      final allowed = _allowedKeys(rules, 'isValidOcrNameSourceMap');
      final emitted = OcrNameSource.values.map((e) => e.name).toSet();
      final missing = emitted.difference(allowed);
      expect(
        missing,
        isEmpty,
        reason: _howToFix('OcrNameSource', 'isValidOcrNameSourceMap', missing),
      );
    });

    test('⭐ companySource — 지금 맞는다고 앞으로도 맞는 것은 아니다', () {
      final allowed = _allowedKeys(rules, 'isValidOcrCompanySourceMap');
      final emitted = OcrCompanySource.values.map((e) => e.name).toSet();
      final missing = emitted.difference(allowed);
      expect(
        missing,
        isEmpty,
        reason:
            _howToFix('OcrCompanySource', 'isValidOcrCompanySourceMap', missing),
      );
    });
  });

  group('허용 목록에 값 검사가 빠진 키가 없다', () {
    /// 🚨 키를 목록에만 넣고 `isOcrCount` 검사를 빠뜨리면 **아무 값이나 들어간다.**
    /// 목록과 검사는 **짝**이어야 한다.
    test('⭐ nameSource 의 키마다 isOcrCount 검사가 있다', () {
      final allowed = _allowedKeys(rules, 'isValidOcrNameSourceMap')
        ..remove('none'); // 'none' 은 값을 세지 않는다
      final missing = allowed
          .where((k) => !rules.contains("('$k' in m) || isOcrCount(m.$k)"))
          .toList();
      expect(
        missing,
        isEmpty,
        reason: '허용 목록에는 있는데 값 검사가 없다 — 그 키로는 어떤 값이든 '
            '들어간다',
      );
    });
  });

  group('⚠️ rules 에만 있고 앱이 안 보내는 키', () {
    /// 이것은 **실패가 아니라 알림**이다. 앱에서 지운 값이 규칙에 남아 있으면
    /// 규칙이 실물보다 넓다 — 당장 해롭지는 않지만 **왜 남았는지 알아야 한다.**
    test('있으면 목록을 남긴다', () {
      final allowed = _allowedKeys(rules, 'isValidOcrNameSourceMap')
        ..remove('none');
      final emitted = OcrNameSource.values.map((e) => e.name).toSet();
      final stale = allowed.difference(emitted);
      expect(
        stale,
        isEmpty,
        reason: '앱이 더 이상 안 보내는 값이 규칙에 남아 있다: $stale — '
            '지워도 되는지 확인할 것',
      );
    });
  });
}
