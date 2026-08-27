import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨 **좌표를 못 찾았을 때 세 화면이 한 목소리인지** 지킨다(2026-08-28).
///
/// ## 왜 이 테스트가 있나
///
/// P1-25 안내가 **세 곳**에 있는데, 오래 서로 반대로 말하고 있었다.
///
/// ```
/// ① 저장 다이얼로그   "주소 자체가 틀렸다는 뜻은 아닙니다"   당신 잘못이 아니다
/// ② 편집 인라인       "주소를 확인해 주세요"                당신이 확인하라
/// ③ 상세 (GeoNoticeRow)  지역표시/숨김을 갈라 말함
/// ```
///
/// **①과 ②가 같은 사건을 두고 반대로 말했다.** 그리고 **왜 실패하는지는 아직
/// 아무도 모른다** — 2026-08-28 실기기에서 진단 화면을 처음 읽었더니 **실패로
/// 기록된 것이 통틀어 1건**이었고 3회 실패로 포기된 명함은 0장이었다.
///
/// 🚨 **모르면 화면이 단정하면 안 된다.** "확인해 주세요"는 주소에 문제가
/// 있다고 단정하는 말이다. ①은 단정하지 않고, ②는 단정했다.
///
/// ## ⚠️ 왜 화면을 띄우지 않고 소스를 읽나
///
/// ②는 `add_card_modal_view.dart`(4,000줄 넘음) 안에 있고, 그 화면을 띄우려면
/// 저장소·프로바이더를 통째로 세워야 한다. **여기서 지키려는 것은 동작이 아니라
/// 말이라** 소스를 읽는 편이 값싸고 정확하다.
///
/// 📌 같은 손을 이미 쓰고 있다 — `ocr_stats_rules_sync_test.dart` 가
/// `firestore.rules` 를 읽어 대조한다.
void main() {
  /// 주석을 걷어 낸 소스. **경위를 적은 주석이 문구 검사에 걸리면 안 된다** —
  /// 옛 문구를 왜 버렸는지 주석에 남기는 것이 이 저장소의 방식이라, 그 설명
  /// 자체가 "옛 문구가 아직 있다"로 읽히면 남길 수가 없어진다.
  String codeOf(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final editSource = codeOf(
    'lib/presentation/features/wallet/views/add_card_modal_view.dart',
  );
  final detailSource = codeOf(
    'lib/presentation/features/wallet/views/geo_notice_row.dart',
  );

  group('🚨 이용자를 탓하지 않는다', () {
    test('⭐ 편집 화면이 "주소를 확인해 주세요"라고 하지 않는다', () {
      expect(
        editSource.contains('주소를 확인해 주세요'),
        isFalse,
        reason: '왜 실패하는지 아직 모른다 — 실패로 기록된 것이 통틀어 1건이다. '
            '"확인해 주세요"는 주소에 문제가 있다고 단정하는 말이라 근거가 '
            '생기기 전까지 쓸 수 없다. 추가 537이 "도로명을 넣으세요"를 막은 '
            '것과 뿌리가 같다 — 둘 다 모르는 것을 단정한다',
      );
    });

    test('⭐ 저장 다이얼로그의 "틀렸다는 뜻은 아닙니다"는 남아 있어야 한다', () {
      expect(
        editSource.contains('주소 자체가 틀렸다는 뜻은 아닙니다'),
        isTrue,
        reason: '셋 중 이것만 단정하지 않는다. 다른 문구를 여기에 맞추는 것이지 '
            '이것을 내리는 것이 아니다',
      );
    });
  });

  group('🚨 고장처럼 보이지 않는다', () {
    test('⭐ 편집 화면이 location_off 를 쓰지 않는다', () {
      expect(
        editSource.contains('Icons.location_off'),
        isFalse,
        reason: 'location_off 는 "꺼짐/차단"으로 읽힌다. 이건 고장이 아니라 '
            '알림이다',
      );
    });

    test('⭐ 편집과 상세가 같은 아이콘을 쓴다', () {
      expect(editSource.contains('Icons.place_outlined'), isTrue);
      expect(
        detailSource.contains('Icons.place_outlined'),
        isTrue,
        reason: '같은 사건을 두 화면이 다른 그림으로 말하면 다른 일로 읽힌다',
      );
    });
  });
}
