import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨 **「백업됐다」고 잘못 말하던 것**(2026-08-28).
///
/// ## 실측
///
/// ```
/// 폴드 화면   「백업 104/2000장 · 기기를 바꿔도 복원됩니다」
/// 서버 실측    users/{uid}/cards/ → 0개
/// 아이폰       명함 126 · 서버 사진 130 · id 일치 126   ← 이쪽은 맞다
/// ```
///
/// **장부만 보면 둘을 구분할 수 없다.** 그래서 서버에 직접 물어 **두 숫자를
/// 나란히** 보여 준다.
///
/// ⚠️ **문구를 흐리지 않는다.** *"확인 중"* 으로 바꾸면 **실제로 잘 된 기기까지
/// 흐려진다** — 맞는 말을 틀리게 바꾸는 것이다.
///
/// 🚨 **없는 것보다 「있다고 잘못 말하는 것」이 나쁘다.** 사진이 안 보이면
/// 이용자가 알지만, 백업이 안 된 것은 **기기를 잃은 뒤에야** 안다.
///
/// ## ⭐ 그리고 실패 건수는 기기 안에 있었는데 아무도 못 봤다
///
/// `summarize()` 가 `failed`·`quotaExceeded` 를 세는데 **화면이 `synced` 만
/// 썼다.** 값이 없어서가 아니라 **보여 주지 않아서** 몰랐다. 진단 화면에도
/// 없다(`grep -n "백업" ocr_stats_view.dart` → 주석 한 줄뿐).
void main() {
  final code = File(
    'lib/presentation/features/settings/views/settings_view.dart',
  ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  group('🚨 서버에 직접 물어본다', () {
    test('⭐ 서버 목록을 조회한다', () {
      expect(
        code.contains('listSyncedContactIds(uid)'),
        isTrue,
        reason: '기기 장부만 보면 「완료」와 「진짜 올라감」을 구분할 수 없다',
      );
    });

    test('🚨 어긋나면 그것부터 말한다', () {
      expect(code.contains('어긋납니다'), isTrue);
      expect(
        code.contains('_serverCount != s.synced'),
        isTrue,
        reason: '두 숫자를 실제로 견줘야 어긋남이 드러난다',
      );
    });

    test('⭐ 맞을 때는 문구를 안 바꾼다', () {
      expect(
        code.contains('기기를 바꿔도 복원됩니다'),
        isTrue,
        reason: '아이폰은 126/126 으로 실제로 맞는다 — 거기서도 흐리면 '
            '맞는 말을 틀리게 바꾸는 것이다',
      );
    });
  });

  group('🚨 「못 물어봤다」와 「0개」를 가른다', () {
    test('⭐ 조회 실패를 따로 다룬다', () {
      expect(code.contains('_serverCheckFailed'), isTrue);
      expect(
        code.contains('서버 확인은 못 했습니다'),
        isTrue,
        reason: '네트워크가 없어 못 물어본 것을 「없다」고 하면 그것도 거짓말이다',
      );
    });

    test('🚨 실패와 0개를 같은 값으로 받지 않는다', () {
      expect(
        code.contains('_serverCount = onServer?.length') &&
            code.contains('uid != null && onServer == null'),
        isTrue,
        reason: 'null(조회 실패)과 0(정말 없음)이 갈려야 한다',
      );
    });
  });

  group('⭐ 실패 건수를 보여 준다 — 지금까지 아무도 못 봤다', () {
    test('어긋날 때 내역을 함께 적는다', () {
      expect(code.contains("if (s.failed > 0) '실패 \${s.failed}'"), isTrue);
      expect(
        code.contains("if (s.quotaExceeded > 0) '한도초과 \${s.quotaExceeded}'"),
        isTrue,
      );
    });

    test('⚠️ 맞을 때는 내역을 안 붙인다 — 읽을 것만 늘어난다', () {
      // 정상 문구 줄에 내역이 섞이지 않았는지 그 줄만 본다.
      final okLine = code
          .split('\n')
          .firstWhere((l) => l.contains('기기를 바꿔도 복원됩니다'));
      expect(
        okLine.contains('실패') || okLine.contains('한도초과'),
        isFalse,
        reason: '맞는 기기에서 숫자를 늘리면 읽을 것만 많아진다',
      );
    });
  });
}
