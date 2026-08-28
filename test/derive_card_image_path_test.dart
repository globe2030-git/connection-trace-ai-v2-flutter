/// **저장된 경로를 정답으로 삼지 않는다**(2026-08-28, 추가 559).
///
/// ## 554에서 한 걸음 더 가는 것이다
///
/// 554는 *"저장된 경로가 낡았으면 고쳐 쓴다"*까지 갔다. 그건 **틀릴 수 있는
/// 값을 계속 먼저 믿는 구조**를 남긴다. 명함에 적힌 경로는 **저장하던 그
/// 순간의 절대경로**이고, iOS 문서 폴더 경로에는 앱 컨테이너 UUID가 들어 있어
/// **앱을 다시 깔면 바뀐다.**
///
/// 📌 파일명은 **명함 id로 결정된다.** 그래서 언제든 다시 만들 수 있다 —
/// 서버 업로드는 처음부터 그렇게 하고 있었고, 그래서 **업로드는 멀쩡했는데
/// 화면만 비었다.** 이제 화면도 같은 방식으로 찾는다.
///
/// 저장된 경로는 없애지 않는다. **사진이 있는지 없는지의 표시**로 계속 쓰이고,
/// 정본에 파일이 없을 때 마지막으로 시도한다.
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('파일명은 명함 id로 결정된다 — 그래서 언제든 다시 만들 수 있다', () {
    test('규칙이 바뀌면 기기에 있는 파일을 못 찾는다 — 고정한다', () {
      expect(
        ContactImageService.fileNameForTest('abc'),
        'contact_card_abc.enc',
      );
    });

    test('명함마다 다른 파일명', () {
      expect(
        ContactImageService.fileNameForTest('a'),
        isNot(ContactImageService.fileNameForTest('b')),
      );
    });
  });

  group('읽는 순서가 뒤집혔나', () {
    final src = File(
      'lib/core/services/contact_image_service.dart',
    ).readAsStringSync();
    final fn = src.substring(src.indexOf('Future<Uint8List?> loadDecryptedCardImage'));
    final body = fn.substring(0, fn.indexOf('\n  /// 로컬에 암호문 파일이 없는'));

    test('⭐ 명함 id로 만든 정본을 먼저 본다', () {
      expect(body.contains('canonicalPath(contactId)'), isTrue);
      // 정본이 후보 목록의 앞에 와야 한다.
      expect(body.indexOf('?canonical'), lessThan(body.indexOf(', path]')));
    });

    test('저장된 경로도 버리지 않는다 — 마지막으로 시도한다', () {
      expect(body.contains('path]'), isTrue);
    });

    test('둘 다 없으면 null — 없는 경로를 지어내지 않는다', () {
      expect(body.contains('if (found == null) return null;'), isTrue);
    });

    test('문서 폴더는 한 번만 묻는다 — 명함이 수백 장이다', () {
      expect(src.contains('_docsPathCache'), isTrue);
    });
  });

  group('화면이 명함 id를 넘기나 — 안 넘기면 예전 동작 그대로다', () {
    test('목록·상세·주변 아바타 전부', () {
      for (final f in [
        'lib/presentation/features/wallet/views/wallet_view.dart',
        'lib/presentation/features/wallet/views/contact_detail_view.dart',
        'lib/presentation/features/radar/views/radar_view.dart',
        'lib/presentation/features/radar/views/reconnect_today_section.dart',
        'lib/presentation/features/radar/views/nearby_map_group_sheet.dart',
      ]) {
        expect(
          File(f).readAsStringSync().contains('contactId: contact.id'),
          isTrue,
          reason: '$f 가 명함 id를 안 넘기면 그 화면만 낡은 경로를 믿는다',
        );
      }
    });

    test('아바타가 그 id를 실제로 쓴다', () {
      final src = File(
        'lib/presentation/common/contact_avatar.dart',
      ).readAsStringSync();
      expect(src.contains('contactId: widget.contactId'), isTrue);
      // id가 바뀌면 다시 읽어야 한다 — 목록 재사용에서 어긋난다.
      expect(src.contains('oldWidget.contactId != widget.contactId'), isTrue);
    });
  });
}
