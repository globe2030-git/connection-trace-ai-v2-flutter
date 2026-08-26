// 내 명함 사진 보관 검증 (2026-08-26 사용자 지시).
//
// 종전에는 내 명함을 스캔해도 **글자만 쓰고 사진은 저장하지 않았다**(의도된
// 설계였다). 사진이 보이도록 바꾸면서, 화면을 봐서는 확인할 수 없는 두 가지를
// 코드 레벨에 고정한다.
//
// ① 저장·복원이 왕복하는가 (그 전에 저장된 프로필도 깨지지 않는가)
// ② 🚨 계정 삭제 때 **함께 지워지는가** — 내 명함 사진만 남으면 "전부
//    지웠다"가 거짓이 된다. 정리는 파일명 접두어로 도는데, 예약 id 가 그
//    접두어를 만들어 내는지는 화면에서 볼 수 없다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';

void main() {
  const withPhoto = MyProfileModel(
    name: '홍길동',
    title: '팀장',
    company: '가상상사',
    phone: '010-0000-0001',
    email: 'hong@example.invalid',
    address: '서울특별시 가상구 예시로 000',
    cardImagePath: '/docs/contact_card__my_profile_card.enc',
  );

  group('명함 사진 경로가 저장·복원을 왕복한다', () {
    test('toJson → fromJson 으로 경로가 그대로 돌아온다', () {
      final restored = MyProfileModel.fromJson(withPhoto.toJson());

      expect(restored.cardImagePath, '/docs/contact_card__my_profile_card.enc');
    });

    test('그 전에 저장된 프로필(키가 없음)은 null 로 읽힌다', () {
      // 마이그레이션을 두지 않은 근거다. 여기가 깨지면 예전 프로필이 안 열린다.
      final old = MyProfileModel.fromJson({
        'name': '홍길동',
        'title': '팀장',
        'company': '가상상사',
        'phone': '010-0000-0001',
        'email': 'hong@example.invalid',
        'address': '서울특별시 가상구 예시로 000',
      });

      expect(old.name, '홍길동');
      expect(old.cardImagePath, isNull);
    });

    test('copyWith 가 경로를 흘리지 않는다', () {
      expect(withPhoto.copyWith(title: '이사').cardImagePath, isNotNull);
    });

    test('clearCardImage 로 "지웠다"를 표현할 수 있다', () {
      // ?? 로는 null 을 못 넣는다 — 사진 지우기가 저장되지 않는다.
      expect(withPhoto.copyWith(clearCardImage: true).cardImagePath, isNull);
    });

    test('프로필 사진과 명함 사진은 서로 다른 값이다', () {
      final both = withPhoto.copyWith(avatarPath: '/docs/avatar.jpg');

      expect(both.avatarPath, '/docs/avatar.jpg');
      expect(both.cardImagePath, '/docs/contact_card__my_profile_card.enc');
      // 하나를 지워도 다른 하나는 남는다.
      expect(both.copyWith(clearAvatar: true).cardImagePath, isNotNull);
      expect(both.copyWith(clearCardImage: true).avatarPath, isNotNull);
    });
  });

  group('🚨 계정 삭제 때 함께 지워진다', () {
    test('예약 id 가 만드는 파일명이 정리 접두어와 맞는다', () {
      // deleteAllCardImages 는 'contact_card_' 로 시작하고 '.enc' 로 끝나는
      // 파일만 지운다. 내 명함 사진이 그 규칙 밖으로 나가면 계정을 지워도
      // 혼자 남는다 — 방침이 "전부 삭제"라고 말하는데 사실이 아니게 된다.
      final name = ContactImageService.fileNameForTest(
        ContactImageService.myProfileCardId,
      );

      expect(name.startsWith('contact_card_'), isTrue);
      expect(name.endsWith('.enc'), isTrue);
    });

    test('예약 id 는 실제 명함 id 와 겹치지 않는다', () {
      // 명함 id 는 UUID 계열이라 밑줄로 시작하지 않는다.
      expect(ContactImageService.myProfileCardId.startsWith('_'), isTrue);
    });
  });
}
