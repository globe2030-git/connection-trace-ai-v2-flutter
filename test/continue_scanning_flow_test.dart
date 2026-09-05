import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨 **연속 등록 — 저장 뒤에 흐름이 안 끊기는지**(globe2030님 요청, 2026-08-28).
///
/// > *"한장 한장 할때도 연속으로 할때도 명함추가 버튼이 위에 있어서 불편해"*
/// > *"그럴 경우 저장 이후에 계속 다시 눌러야 해"*
///
/// ## 원인은 버튼 위치가 아니었다
///
/// 저장하면 `Navigator.pop` 으로 시트가 닫히고 명함 지갑으로 돌아갔다. 그래서
/// 다음 장을 찍으려면 **머리글 오른쪽 위 버튼을 다시 눌러야** 했다.
/// globe2030님이 하루에 **아이폰 126장 · 폴드 190장**을 그렇게 등록했다.
///
/// 📌 버튼을 아래로 옮겨도 **그 반복은 그대로 남는다.** 그래서 흐름을 잇는
/// 쪽을 먼저 고쳤다.
///
/// ## ⚠️ 왜 화면을 띄우지 않고 소스를 읽나
///
/// 이 흐름은 **시트 → 다이얼로그 → 카메라 라우트**가 겹쳐 있어 위젯 테스트로
/// 세우려면 카메라·OCR·저장소를 전부 가짜로 만들어야 한다. 그 비용에 비해
/// 여기서 지키려는 것은 **"갈래가 제대로 나 있는가"** 몇 가지뿐이다.
///
/// 📌 같은 손을 이미 쓰고 있다 — `geo_notice_wording_sync_test`,
/// `ocr_stats_rules_sync_test`.
///
/// 🚨 **그래서 이 테스트는 「동작한다」를 증명하지 않는다.** 실기기 확인이
/// 따로 필요하고, 그것을 대신하지 않는다.
void main() {
  String codeOf(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final source = codeOf(
    'lib/presentation/features/wallet/views/add_card_modal_view.dart',
  );

  group('🚨 빠져나갈 길이 항상 있다', () {
    test('⭐ "그만하고 지갑으로"가 있다', () {
      expect(
        source.contains('그만하고 지갑으로'),
        isTrue,
        reason: '실수로 계속 찍히는 상태에 갇히면 빠져나갈 길이 없다. '
            '2026-08-26 광고 동의 오탭과 같은 유형의 위험이다',
      );
    });

    test('⭐ 묻지 않고 이어지지 않는다 — 확인 창을 거친다', () {
      expect(source.contains('_askKeepScanning'), isTrue);
      expect(
        source.contains('keepScanning = await _askKeepScanning'),
        isTrue,
        reason: '이어가는 유일한 경로가 이 물음을 지나야 한다',
      );
    });

    test('⭐ 창을 바깥 탭으로 닫으면 "그만"이 된다', () {
      expect(
        source.contains('await _askKeepScanning(contact.name) ?? false'),
        isTrue,
        reason: 'null(취소)을 false로 받는다 — 안 되는 쪽으로 안전하게',
      );
    });
  });

  group('🚨 저장은 건드리지 않았다', () {
    test('⭐ 저장이 먼저, 묻는 것은 그다음', () {
      // ⚠️ **인자까지 넣어 찾지 않는다** — 예전에는 `.addContact(contact)` 로
      // 찾았는데, 2026-09-05에 파싱 원본을 함께 넘기면서 호출이 여러 줄로
      // 바뀌자 **의도는 그대로인데 이 검사만 깨졌다.**
      //
      // 📌 이 테스트가 지키려는 것은 **순서**이지 인자 모양이 아니다.
      final save = source.indexOf('.addContact(');
      final ask = source.indexOf('_askKeepScanning(contact.name)');
      expect(save, greaterThan(-1));
      expect(ask, greaterThan(-1));
      expect(
        save,
        lessThan(ask),
        reason: '무엇을 고르든 명함은 이미 남아 있어야 한다 — 물음이 저장을 '
            '막는 자리에 있으면 안 된다',
      );
    });

    test('⭐ 수정할 때는 묻지 않는다', () {
      expect(
        source.contains('if (!_isEditing) {\n      keepScanning ='),
        isTrue,
        reason: '수정은 한 건짜리 작업이라 이어 찍을 이유가 없다',
      );
    });
  });

  group('연속으로 열 때 촬영까지 바로 간다', () {
    test('⭐ 두 번째부터는 촬영 화면으로 들어간다', () {
      expect(source.contains('startWithScan'), isTrue);
      expect(
        source.contains('if (mounted) _performOcrScan(isFromCamera: true);'),
        isTrue,
        reason: '이것이 없으면 등록 화면만 열리고 촬영 버튼을 또 눌러야 한다 — '
            'globe2030님이 불편하다고 한 그 한 번이 그대로 남는다',
      );
    });

    test('🚨 이어 열 때 앞 명함 값을 물려주지 않는다', () {
      expect(
        source.contains('prefillData = null;') &&
            source.contains('contact = null;'),
        isTrue,
        reason: '물려주면 앞사람 정보가 다음 명함에 그대로 남는다 — '
            '제3자 개인정보가 엉뚱한 명함에 붙는다',
      );
    });

    test('⭐ 지갑 화면이 사라졌으면 다시 열지 않는다', () {
      expect(
        source.contains('if (!context.mounted) return null;'),
        isTrue,
        reason: '어디에도 안 붙은 시트가 뜬다',
      );
    });
  });
}
