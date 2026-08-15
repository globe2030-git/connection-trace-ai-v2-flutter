import 'package:connection_trace_ai_flutter/core/utils/seeded_memo_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자동 삽입 메모 정리의 **대상 판정**을 고정한다.
///
/// 이 판정이 틀리면 **사용자가 직접 쓴 메모를 지운다.** 되돌릴 수 없는 삭제라,
/// 태그 정리(E-08, `seeded_tag_cleanup_test.dart`)와 같은 원칙으로 **대상을
/// 최대한 좁게** 잡는 것이 맞는지 검사한다.
void main() {
  const seeded = 'AI OCR 스캔으로 자동 추출된 명함 텍스트 정보입니다.';

  group('자동 삽입 메모 판정', () {
    test('⭐ 그 문장 하나뿐이면 정리 대상이다', () {
      expect(isSeededScanMemo(seeded), isTrue);
    });

    test('앞뒤 공백·줄바꿈은 무시한다', () {
      expect(
        isSeededScanMemo('  $seeded\n'),
        isTrue,
        reason: '저장·복원을 거치며 줄바꿈이 붙는 경우가 있다',
      );
    });

    test('⭐ 사용자가 뒤에 덧붙였으면 건드리지 않는다', () {
      expect(
        isSeededScanMemo('$seeded\n\n지난주 미팅에서 신제품 얘기 나눔'),
        isFalse,
        reason: '덧붙였다는 것은 그 칸을 의식하고 손댔다는 뜻이다 — '
            '지우면 사용자가 쓴 내용까지 사라진다',
      );
    });

    test('⭐ 사용자가 앞에 덧붙인 경우도 건드리지 않는다', () {
      expect(isSeededScanMemo('메모: $seeded'), isFalse);
    });

    test('문장이 조금이라도 다르면 대상이 아니다', () {
      expect(
        isSeededScanMemo('AI OCR 스캔으로 자동 추출된 명함 정보입니다.'),
        isFalse,
        reason: '사용자가 고쳤을 수 있다. 정확히 같을 때만 지운다',
      );
    });

    test('빈 메모·null은 대상이 아니다', () {
      expect(isSeededScanMemo(''), isFalse);
      expect(isSeededScanMemo(null), isFalse);
      expect(isSeededScanMemo('   '), isFalse);
    });

    test('사용자가 직접 쓴 평범한 메모는 대상이 아니다', () {
      expect(isSeededScanMemo('골프 좋아하심. 다음달 세미나 초대 예정'), isFalse);
    });
  });

  /// 2026-08-15 실기기 확인에서, 위 좁은 판정이 놓치는 모양이 나왔다 —
  /// 앱이 만든 `[이전 정보 · …]` 블록 **아래**에 문구가 붙어 있는 경우.
  /// 사람이 쓴 글이 아닌데 "덧붙였다"에 걸려 남았고, 문구는 그대로 AI
  /// 브리핑에 실려 나갔다. 그래서 **그 줄만** 걷어내는 판정을 따로 둔다.
  group('자동 삽입 문구가 든 줄 판정·제거', () {
    test('⭐ 앱이 만든 이전 정보 블록 아래에 붙어 있어도 대상이다', () {
      const memo = '[이전 정보 · 2026-08-14] E Mail / 010-0000-0000\n$seeded';
      expect(memoHasSeededScanLine(memo), isTrue);
      expect(
        withoutSeededScanLine(memo),
        '[이전 정보 · 2026-08-14] E Mail / 010-0000-0000',
        reason: '문구 줄만 빠지고 앞 블록은 그대로 남아야 한다',
      );
    });

    test('⭐ 사용자가 쓴 내용은 지우지 않는다', () {
      const memo = '$seeded\n\n지난주 미팅에서 신제품 얘기 나눔';
      expect(memoHasSeededScanLine(memo), isTrue);
      expect(
        withoutSeededScanLine(memo),
        '지난주 미팅에서 신제품 얘기 나눔',
        reason: '메모를 통째로 비우면 사용자가 쓴 문장까지 사라진다',
      );
    });

    test('그 문장뿐이면 결과가 비고, 옛 판정과 같은 결과가 된다', () {
      expect(memoHasSeededScanLine(seeded), isTrue);
      expect(withoutSeededScanLine(seeded), isEmpty);
    });

    test('⭐ 다른 글과 한 줄에 섞여 있으면 건드리지 않는다', () {
      const memo = '메모: $seeded';
      expect(
        memoHasSeededScanLine(memo),
        isFalse,
        reason: '그 줄을 사용자가 직접 편집했다는 뜻이다. '
            'substring을 도려내면 "메모:" 같은 조각이 남는다',
      );
    });

    test('문장이 조금이라도 다른 줄은 대상이 아니다', () {
      expect(
        memoHasSeededScanLine('AI OCR 스캔으로 자동 추출된 명함 정보입니다.'),
        isFalse,
      );
    });

    test('빈 메모·null은 대상이 아니다', () {
      expect(memoHasSeededScanLine(''), isFalse);
      expect(memoHasSeededScanLine(null), isFalse);
    });

    test('같은 문장이 여러 줄 있으면 전부 걷어낸다', () {
      const memo = '$seeded\n실제 메모\n$seeded';
      expect(withoutSeededScanLine(memo), '실제 메모');
    });
  });
}
