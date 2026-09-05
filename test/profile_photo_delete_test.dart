// 프로필 화면의 「사진 지우기」가 **실제로 지우는지** 못 박는 검사
// (2026-09-05, 추가 695. 결함은 추가 687에서 찾았다).
//
// 무엇을 지키려는 검사인가:
// ① **지운다고 했으면 서버 사본까지 지운다** — 종전에는 모델의 경로만 비워
//    기기의 `.enc` · Cloud Storage 사본 · 백업 장부의 「백업됨」이 전부 남았다.
//    그런데 화면은 *"이 기기에만 있어 지우면 되돌릴 수 없어요"*라고 말했다.
//    🚨 **이용자가 「지웠다」고 믿는 것이 서버에 남는 것**이 이 결함의 실질이다.
// ② **경로가 끊겨도 서버는 지운다** — 서버에서 복원한 직후처럼 기기 파일이
//    없는 상태가 있다. 거기서 넘어가면 **나중에 지울 수도 없는 고아 사본**이
//    된다. `ContactsRepository.deleteContact`가 같은 이유로 같은 갈래를 갖는다.
// ③ **부르는 곳이 다시 사라지지 않는다** — 이 결함의 정체는 로직이 틀린 것이
//    아니라 **`deleteCardImage`를 아무도 안 부른 것**이었다([추가 79]의
//    *"서비스는 정상인데 부르는 쪽이 없다"*와 같은 모양). 그래서 「부른다」
//    자체를 검사한다.
//
// ⚠️ 왜 위젯 테스트가 아닌가: 이 화면은 `ImagePicker`·`path_provider`·
// Firebase를 함께 쓴다. 그것을 전부 가짜로 세우는 비용보다, **판정을 순수
// 함수로 빼서 직접 재는 편**이 정확하고 빠르다. 판정이 화면 안에 있으면
// 다시 사라져도 아무도 모른다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/presentation/features/radar/views/my_profile_edit_modal_view.dart';

/// 화면 파일 — ③에서 소스를 직접 읽는다.
const _viewPath =
    'lib/presentation/features/radar/views/my_profile_edit_modal_view.dart';

void main() {
  group('「지우기」를 누르고 저장하면 어디까지 지우나', () {
    test('안 눌렀으면 아무것도 안 지운다', () {
      expect(
        profileCardPhotoDeletionFor(
          cleared: false,
          savedPath: '/docs/contact_card__my_profile_card.enc',
          uid: 'u1',
        ),
        ProfileCardPhotoDeletion.none,
      );
    });

    test('🚨 눌렀고 기기에 파일이 있으면 **서버 사본까지** 지운다', () {
      expect(
        profileCardPhotoDeletionFor(
          cleared: true,
          savedPath: '/docs/contact_card__my_profile_card.enc',
          uid: 'u1',
        ),
        ProfileCardPhotoDeletion.localAndServer,
      );
    });

    test('🚨 경로가 끊겼어도 서버는 지운다 — 안 그러면 고아 사본이 된다', () {
      // 서버에서 복원한 직후 등 기기 파일이 없는 상태.
      expect(
        profileCardPhotoDeletionFor(cleared: true, savedPath: null, uid: 'u1'),
        ProfileCardPhotoDeletion.serverOnly,
      );
    });

    test('로그인하지 않았으면 서버에 지울 것도 권한도 없다', () {
      expect(
        profileCardPhotoDeletionFor(cleared: true, savedPath: null, uid: null),
        ProfileCardPhotoDeletion.none,
      );
    });

    test('로그인 전이라도 기기 파일은 지운다', () {
      expect(
        profileCardPhotoDeletionFor(
          cleared: true,
          savedPath: '/docs/contact_card__my_profile_card.enc',
          uid: null,
        ),
        ProfileCardPhotoDeletion.localAndServer,
      );
    });
  });

  group('🚨 부르는 곳이 다시 사라지지 않는다', () {
    late String source;

    setUpAll(() {
      final file = File(_viewPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$_viewPath 가 없다. 옮겼다면 이 검사의 상수도 함께 고칠 것.',
      );
      source = file.readAsStringSync();
    });

    test('명함 사진 삭제가 deleteCardImage 를 부른다', () {
      expect(
        source.contains('deleteCardImage('),
        isTrue,
        reason:
            '이 화면이 deleteCardImage 를 안 부르면 「지우기」가 서버 사본을 '
            '남긴다 — 그것이 추가 687에서 찾은 결함이다.',
      );
    });

    test('판정 함수를 실제로 쓴다 — 갈래가 화면에 다시 흩어지지 않는다', () {
      expect(
        source.contains('profileCardPhotoDeletionFor('),
        isTrue,
        reason:
            '판정을 화면 안에 다시 인라인하면 검사가 그것을 못 본다. '
            'profileCardPhotoDeletionFor 를 거쳐야 한다.',
      );
    });

    test('아바타 삭제에도 확인을 묻는다', () {
      // 되돌릴 수 없는 조작에는 확인을 붙인다 — 명함 사진 쪽과 같은 원칙.
      expect(
        source.contains("title: Text('프로필 사진을 지울까요?')") ||
            source.contains("Text('프로필 사진을 지울까요?')"),
        isTrue,
        reason:
            '아바타 「지우기」에 확인 다이얼로그가 없으면 누르는 순간 사라진다. '
            '2026-09-05 이전이 그랬다.',
      );
    });

    test('아바타 파일명이 한 군데에서만 온다', () {
      // 지우는 쪽과 저장하는 쪽이 다른 이름을 쓰면 **안 지워진다.**
      expect(
        kProfileAvatarFileName,
        'my_profile_avatar.jpg',
        reason: '파일명을 바꾸면 예전에 저장된 사진을 못 찾는다.',
      );
      // 리터럴은 **상수를 선언하는 그 줄에만** 있어야 한다. 다른 줄에 또
      // 박혀 있으면 저장하는 쪽과 지우는 쪽이 어긋날 수 있다.
      final stray = source
          .split('\n')
          .asMap()
          .entries
          .where(
            (e) =>
                e.value.contains("'my_profile_avatar.jpg'") &&
                !e.value.contains('kProfileAvatarFileName ='),
          )
          .map((e) => '${e.key + 1}: ${e.value.trim()}')
          .toList();
      expect(
        stray,
        isEmpty,
        reason:
            '화면 안에 파일명이 직접 박혀 있다. kProfileAvatarFileName 을 쓸 것 — '
            '저장하는 쪽과 지우는 쪽이 어긋나면 지워지지 않는다.\n'
            '${stray.join('\n')}',
      );
    });
  });
}
