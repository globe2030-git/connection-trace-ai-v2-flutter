/// 저장된 명함 사진 경로가 **낡아도 다시 찾는다**(2026-08-28, 추가 554).
///
/// ## 무엇이 문제였나
///
/// 명함에 적어 두는 것은 **절대경로**(`<문서폴더>/contact_card_<id>.enc`)인데,
/// **iOS 문서 폴더 경로에는 앱 컨테이너 UUID가 들어 있어 앱을 다시 깔면
/// 바뀐다.** Android는 `/data/user/0/<패키지>/…`라 안 바뀐다.
///
/// ✅ **실물로 갈렸다**: 같은 코드가 도는데 **폴드는 옛 명함까지 사진이 보이고
/// 아이폰은 안 보였다.** 화면에는 「스캔한 명함」 머리글만 남고 그림 자리가
/// 비었다 — 못 읽으면 그림만 사라지게 돼 있어서다.
///
/// 📌 **파일은 멀쩡히 있었다.** 서버 업로드는 저장된 경로를 안 쓰고 명함
/// id에서 경로를 다시 만들기 때문에 잘 됐다 — **업로드는 되는데 화면만 비는**
/// 갈라진 상태였다. 그래서 "사진이 없다"가 아니라 "경로가 낡았다"가 원인이다.
///
/// ⚠️ **재연결 코드는 있었는데 두 곳에서 막혀 있었다.**
///   ① `cardImagePath != null`이면 건드리지 않는다 — 낡은 경로도 "있는" 것이다
///   ② 경로가 다 차 있으면 아예 시작도 안 한다(IO를 아끼려던 이른 반환)
/// 그래서 아이폰에서는 **고칠 기회가 오지 않았다.**
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel c(String id, {String? path}) => ContactModel(
  id: id,
  name: '이름$id',
  company: '',
  title: '',
  phone: '',
  email: '',
  tags: const [],
  talkingPoints: const [],
  cardImagePath: path,
);

void main() {
  group('낡은 경로를 지금 경로로 바꾼다', () {
    test('⭐ 경로가 있어도 파일 위치가 다르면 바꾼다 — 이것이 아이폰에서 깨진 자리다', () {
      final out = ContactsRepository.relinkCardImagePaths(
        [c('a', path: '/옛/컨테이너/contact_card_a.enc')],
        {'a': '/지금/컨테이너/contact_card_a.enc'},
      );
      expect(out.single.cardImagePath, '/지금/컨테이너/contact_card_a.enc');
    });

    test('경로가 비어 있으면 채운다 — 예전 동작 그대로', () {
      final out = ContactsRepository.relinkCardImagePaths(
        [c('a')],
        {'a': '/지금/contact_card_a.enc'},
      );
      expect(out.single.cardImagePath, '/지금/contact_card_a.enc');
    });

    test('같은 경로면 그대로 둔다 — 방금 등록한 명함은 값이 안 바뀐다', () {
      final same = '/지금/contact_card_a.enc';
      final input = [c('a', path: same)];
      final out = ContactsRepository.relinkCardImagePaths(input, {'a': same});
      expect(identical(out.single, input.single), isTrue);
    });

    test('🚨 기기에 파일이 없으면 손대지 않는다 — 없는 경로를 지어내지 않는다', () {
      final out = ContactsRepository.relinkCardImagePaths(
        [c('a', path: '/옛/contact_card_a.enc'), c('b')],
        const {},
      );
      expect(out[0].cardImagePath, '/옛/contact_card_a.enc');
      expect(out[1].cardImagePath, isNull);
    });

    test('사진이 정말 없는 명함은 계속 null', () {
      final out = ContactsRepository.relinkCardImagePaths(
        [c('없는아이')],
        {'다른아이': '/지금/contact_card_다른아이.enc'},
      );
      expect(out.single.cardImagePath, isNull);
    });
  });

  group('막고 있던 두 곳이 열렸나 — 규칙만 고치고 안 부르면 소용이 없다', () {
    final src = File(
      'lib/data/repositories/contacts_repository.dart',
    ).readAsStringSync();

    test('경로가 다 차 있어도 재연결을 시작한다', () {
      expect(
        src.contains('_contacts.every((c) => c.cardImagePath != null)'),
        isFalse,
        reason: '낡은 경로도 "차 있는" 것이라 이 이른 반환이 고칠 기회를 막았다',
      );
    });

    test('서버 내려받기 기준은 「기기에 파일이 있느냐」다', () {
      expect(
        src.contains("c.cardImagePath == null && !existing.containsKey(c.id)"),
        isFalse,
        reason: '낡은 경로를 든 명함도 파일이 없을 수 있다',
      );
    });
  });

  group('화면도 스스로 한 번 더 찾는다 — 저장소 재연결을 기다리지 않는다', () {
    test('편집 화면과 상세 화면이 명함 id를 넘긴다', () {
      final edit = File(
        'lib/presentation/features/wallet/views/add_card_modal_view.dart',
      ).readAsStringSync();
      final detail = File(
        'lib/presentation/features/wallet/views/contact_detail_view.dart',
      ).readAsStringSync();
      expect(edit.contains('contactId: widget.contactToEdit?.id'), isTrue);
      expect(detail.contains('contactId: contact.id'), isTrue);
    });

    test('읽는 쪽이 id로 다시 찾을 줄 안다', () {
      final svc = File(
        'lib/core/services/contact_image_service.dart',
      ).readAsStringSync();
      final body = svc.substring(svc.indexOf('Future<Uint8List?> loadDecryptedCardImage'));
      final fn = body.substring(0, body.indexOf('\n  /// 로컬에 암호문 파일이 없는'));
      expect(fn.contains('findExistingCardImagePath'), isTrue);
    });
  });
}
