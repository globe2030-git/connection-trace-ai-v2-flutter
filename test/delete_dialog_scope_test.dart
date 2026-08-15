// 삭제 안내가 "기기에서만"으로 읽히지 않는지 보는 검사(2026-08-16).
//
// 왜 필요한가: 명함을 지우면 기기뿐 아니라 **서버(Firestore)와 다른 기기**
// 에서도 사라지고 되돌릴 수 없다. 삭제 기록(묘비)이 남아 다른 기기도 따라
// 지우기 때문이다(P1-39 A안). 그런데 안내는 "기기에서 삭제됩니다"라고만
// 적혀 있어, 사용자가 **이 폰에서만 지우는 것**으로 읽을 수 있었다.
//
// 문구가 다시 "기기에서"로 돌아가면 이 검사가 잡는다. 위젯을 띄우지 않고
// 소스를 훑는다 — no_seeded_form_defaults_test.dart와 같은 방식이다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('삭제 안내가 서버까지 지워진다는 것을 알린다', () {
    final src = File(
      'lib/presentation/features/wallet/views/wallet_view.dart',
    ).readAsStringSync();

    // 대화상자 본문(content:)에 쓰인 안내만 본다.
    expect(
      src.contains('기기와 서버에서 모두'),
      isTrue,
      reason: '삭제 안내에 서버도 지워진다는 사실이 있어야 한다',
    );
    expect(
      src.contains('되돌릴 수 없습니다'),
      isTrue,
      reason: '되돌릴 수 없다는 것을 알려야 한다 — 사진은 복구 수단이 없다',
    );
  });

  test('"기기에서 삭제됩니다"라는 옛 문구가 남아 있지 않다', () {
    final src = File(
      'lib/presentation/features/wallet/views/wallet_view.dart',
    ).readAsStringSync();
    expect(
      src.contains('기록이 기기에서 삭제됩니다'),
      isFalse,
      reason: '이 폰에서만 지우는 것으로 읽힌다',
    );
  });
}
