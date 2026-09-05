/// **파싱 원본**을 남기는 모델 (2026-09-05).
///
/// 🚨 **여기서 지키는 것은 「나중에 다시 파싱할 수 있는가」다.**
/// 원본은 저장하는 순간에만 남길 수 있어서, 이 규칙이 깨지면 되살릴 방법이
/// 없다 — 그래서 경계를 테스트로 고정한다.
library;

import 'package:connection_trace_ai_flutter/data/models/card_source_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scannedAt = DateTime.utc(2026, 9, 5, 12, 30);

  CardSourceModel sample({String rawText = '홍길동\n커넥션센스\n010-1234-5678'}) =>
      CardSourceModel(
        cardId: 'c1',
        rawText: rawText,
        parserVersion: kCardParserVersion,
        scannedAt: scannedAt,
      );

  group('저장하고 되읽기', () {
    test('⭐ 왕복해도 값이 그대로다 — 이게 깨지면 재파싱이 불가능해진다', () {
      final restored = CardSourceModel.fromJson(sample().toJson());

      expect(restored, isNotNull);
      expect(restored!.cardId, 'c1');
      expect(restored.rawText, '홍길동\n커넥션센스\n010-1234-5678');
      expect(restored.parserVersion, kCardParserVersion);
      expect(restored.scannedAt, scannedAt);
    });

    test('줄바꿈이 살아남는다 — 명함은 줄 구조가 곧 정보다', () {
      final restored = CardSourceModel.fromJson(
        sample(rawText: 'A아키텍처팀\n선임 Architect').toJson(),
      );

      expect(restored!.rawText.split('\n'), ['A아키텍처팀', '선임 Architect']);
    });
  });

  group('🚨 원본이 없을 때는 만들지 않는다', () {
    test('직접 입력한 명함은 원본 기록을 안 만든다', () {
      final source = CardSourceModel.forScan(
        cardId: 'c1',
        rawText: null,
        scannedAt: scannedAt,
      );

      expect(
        source,
        isNull,
        reason: '빈 기록을 만들면 「못 읽었다」와 「스캔한 적 없다」가 같아진다',
      );
    });

    test('공백만 있는 원문도 안 만든다', () {
      expect(
        CardSourceModel.forScan(
          cardId: 'c1',
          rawText: '   \n  ',
          scannedAt: scannedAt,
        ),
        isNull,
      );
    });

    test('원문이 있으면 만든다 — 그리고 앞뒤 공백은 다듬는다', () {
      final source = CardSourceModel.forScan(
        cardId: 'c1',
        rawText: '  홍길동\n커넥션센스  ',
        scannedAt: scannedAt,
      );

      expect(source, isNotNull);
      expect(source!.rawText, '홍길동\n커넥션센스');
      expect(source.parserVersion, kCardParserVersion);
    });
  });

  group('깨진 기록을 만나도 앱이 멈추지 않는다', () {
    test('🚨 못 읽으면 null 이다 — 예외를 던지지 않는다', () {
      expect(CardSourceModel.fromJson({}), isNull);
      expect(CardSourceModel.fromJson({'cardId': 'c1'}), isNull);
      expect(
        CardSourceModel.fromJson({'cardId': 'c1', 'rawText': ''}),
        isNull,
        reason: '원본은 있으면 좋은 것이지 없으면 앱이 멈춰야 하는 것이 아니다',
      );
    });

    test('시각이 깨져 있으면 안 읽는다 — 언제 것인지 모르는 기록은 쓸모가 없다', () {
      final json = sample().toJson()..['scannedAt'] = '어제';

      expect(CardSourceModel.fromJson(json), isNull);
    });
  });

  group('🚨 파서 판(版)', () {
    test('⭐ 판이 없는 옛 기록은 0으로 읽는다 — 최신 판으로 채우면 안 된다', () {
      final json = sample().toJson()..remove('parserVersion');

      final restored = CardSourceModel.fromJson(json);

      expect(
        restored!.parserVersion,
        0,
        reason: '최신 판으로 채우면 옛 원본이 재파싱 대상에서 조용히 빠진다',
      );
      expect(restored.parserVersion, isNot(kCardParserVersion));
    });

    test('판이 숫자가 아니어도 0으로 읽고 넘어간다', () {
      final json = sample().toJson()..['parserVersion'] = 'v1';

      expect(CardSourceModel.fromJson(json)!.parserVersion, 0);
    });

    test('옛 판으로 뽑힌 기록을 골라낼 수 있다 — 재파싱 대상이 이것이다', () {
      final records = [
        CardSourceModel.fromJson(sample().toJson()..remove('parserVersion'))!,
        CardSourceModel.fromJson(sample().toJson())!,
      ];

      final stale = records.where((r) => r.parserVersion < kCardParserVersion);

      expect(stale, hasLength(1));
      expect(stale.first.parserVersion, 0);
    });
  });

  test('🚨 toString 에 원문이 안 새어 나온다 — 제3자 개인정보다', () {
    final text = sample().toString();

    expect(text, isNot(contains('홍길동')));
    expect(text, isNot(contains('010-1234-5678')));
    expect(text, contains('자'), reason: '길이만 찍는다');
  });
}
