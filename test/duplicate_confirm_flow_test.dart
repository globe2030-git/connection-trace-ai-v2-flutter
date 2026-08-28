import 'dart:io';

import 'package:connection_trace_ai_flutter/core/utils/contact_field_diff.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨 **같은 사람이 두 줄로 쌓이던 것**을 막는다(globe2030님 제보, 2026-08-28).
///
/// > *"같은 사람을 중복된 이름과 핸드폰번호가 있는데 두 장으로 등록하네"*
/// > *"같은 이름과 휴대폰이 있는 명함이 들어오면 새로운 명함으로 등록할지 묻고,
/// >  새로운 명함으로 한다면 그 전에거는 과거의 명함으로 남기는거야"*
///
/// ## 무엇이 문제였나 — 창이 둘이고 서로 어긋났다
///
/// ```
/// 첫 창 (저장 흐름 1-b)   [취소] [그래도 추가]        ← 두 줄이 생기는 유일한 길
/// 둘째 창 (저장 직전)      [기존 유지] [업데이트]      ← 「새로 추가」가 없다
/// ```
///
/// 🚨 **첫 창에서 「그래도 추가」를 골라도 둘째 창이 다시 물었고, 거기서
/// 「업데이트」를 누르면 합쳐졌다** — **첫 창의 선택이 버려졌다.**
///
/// ⚠️ 그리고 **「그래도 추가」로 가면 이전 명함 기록 경로에 아예 안 갔다.**
/// globe2030님이 원한 *"명함이 바뀐 히스토리"* 가 그래서 안 쌓였다.
///
/// ## 바뀐 것 — **언제나 한 줄**
///
/// ```
/// 「같은 분의 새 명함인가요?」  [그대로 두기] [새 명함으로 등록]
/// ```
///
/// 📌 겸직은 「과거」가 아니라 **표시할 명함을 고르는 문제**다 — 그건 저장
/// 구조를 바꾼 뒤(설계 문서 참고)라 이번 범위 밖이다.
ContactModel card({
  String id = 'c1',
  String company = '가상상사',
  String title = '팀장',
  String? department,
  String phone = '010-1111-2222',
  String? officePhone,
  String email = 'a@example.invalid',
  String? address,
}) => ContactModel(
  id: id,
  name: '홍길동',
  company: company,
  title: title,
  department: department,
  phone: phone,
  officePhone: officePhone,
  email: email,
  address: address,
  tags: const [],
  talkingPoints: const [],
);

void main() {
  _mergeKeepsCardImageTests();

  group('🚨 무엇이 달라지는지 센다 — 값은 안 바꾼다', () {
    test('⭐ 양쪽 다 값이 있고 다르면 differs', () {
      final d = diffContacts(
        existing: card(title: '본부장'),
        incoming: card(title: 'mono. alliance'),
      );
      expect(d.length, 1);
      expect(d.single.label, '직함');
      expect(d.single.kind, FieldChangeKind.differs);
      expect(d.single.existing, '본부장');
      expect(d.single.incoming, 'mono. alliance');
    });

    test('🚨 기존에만 있으면 onlyInExisting — 사라질 뻔한 값이다', () {
      final d = diffContacts(
        existing: card(officePhone: '070-3281-8881'),
        incoming: card(),
      );
      expect(d.single.label, '사무실 전화');
      expect(
        d.single.kind,
        FieldChangeKind.onlyInExisting,
        reason: '이걸 안 보여 주면 070 번호가 사라진 줄도 모른다',
      );
    });

    test('⭐ 새 명함에만 있으면 onlyInIncoming', () {
      final d = diffContacts(
        existing: card(),
        incoming: card(department: '영업1팀'),
      );
      expect(d.single.label, '부서');
      expect(d.single.kind, FieldChangeKind.onlyInIncoming);
    });

    test('⭐ 같은 칸은 안 담는다 — 볼 것이 없다', () {
      expect(diffContacts(existing: card(), incoming: card()), isEmpty);
    });

    test('⭐ 앞뒤 공백만 다른 것은 같다고 본다', () {
      expect(
        diffContacts(existing: card(title: '팀장'), incoming: card(title: '  팀장  ')),
        isEmpty,
      );
    });

    test('⭐ 이름은 세지 않는다 — 같아야 여기까지 온다', () {
      final d = diffContacts(existing: card(), incoming: card());
      expect(d.map((e) => e.label), isNot(contains('이름')));
    });
  });

  group('🚨 배선 — 창이 하나만 남았는가', () {
    final edit = File(
      'lib/presentation/features/wallet/views/add_card_modal_view.dart',
    ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

    test('🚨 「그래도 추가」가 사라졌다', () {
      expect(
        edit.contains('그래도 추가'),
        isFalse,
        reason: '이 버튼이 지갑에 두 줄을 만들던 유일한 길이다',
      );
    });

    test('🚨 「이미 등록된 것 같아요」 첫 창이 사라졌다', () {
      expect(edit.contains('이미 등록된 것 같아요'), isFalse);
    });

    test('⭐ 남은 창의 갈래가 globe2030님 말씀대로다', () {
      expect(edit.contains('같은 분의 새 명함인가요?'), isTrue);
      expect(edit.contains('새 명함으로 등록'), isTrue);
      expect(edit.contains('그대로 두기'), isTrue);
    });

    test('⭐ 지난 명함이 남는다는 것을 문구가 말한다', () {
      expect(
        edit.contains('지난 명함으로 남습니다'),
        isTrue,
        reason: '무엇이 일어나는지 모른 채 고르게 하면 안 된다',
      );
    });

    test('🚨 합치기도 연속 등록 흐름에 탄다', () {
      expect(
        edit.contains('_askKeepScanning(updated.name)'),
        isTrue,
        reason: '안 태우면 연속 등록 중 중복이 걸릴 때마다 흐름이 끊긴다 — '
            '새 명함 저장은 이어지는데 합치기만 끊기고 있었다',
      );
    });
  });
}

/// 🚨 **합치면 명함 사진이 사라지던 것**(2026-08-28).
///
/// globe2030님: *"아이폰에서 한 장 찍었는데 쎔네일 안나와"*
///
/// ## 서버 실측이 원인을 가리켰다
///
/// ```
/// 명함 126장 · 서버 사진 130개 · id 일치 126
/// ```
///
/// **사진은 만들어져 서버까지 올라갔는데 명함이 그것을 안 가리켰다.**
/// 「저장이 안 된다」도 「경로가 죽었다」도 「계정 키가 다르다」도 아니고
/// **연결을 안 한 것**이었다.
///
/// ## 왜 안 이어졌나
///
/// 사진을 만드는 코드가 **중복 분기 아래**에 있어서, 합치기로 가면
/// **거기 도달조차 하지 않았다.** 그리고 `copyWith` 에 `cardImagePath` ·
/// `useCardAsAvatar` 가 **아예 없었다.**
void _mergeKeepsCardImageTests() {
  final edit = File(
    'lib/presentation/features/wallet/views/add_card_modal_view.dart',
  ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  group('🚨 합치기가 명함 사진을 지킨다', () {
    test('⭐ 합치기 전에 사진을 저장한다', () {
      expect(
        edit.contains('contactId: existing.id') &&
            edit.contains('saveEncryptedCardImage'),
        isTrue,
        reason: '분기 아래에 있으면 합치기로 갈 때 도달조차 안 한다',
      );
    });

    test('🚨 existing.id 로 저장한다 — 새 id 로 하면 영영 못 찾는다', () {
      expect(
        edit.contains('contactId: existing.id'),
        isTrue,
        reason: '합치면 살아남는 것이 existing.id 다. 파일 이름이 안 맞으면 '
            '나중에 다시 잇지도 못한다',
      );
    });

    test('⭐ copyWith 가 사진을 넘긴다', () {
      expect(edit.contains('cardImagePath: cardImagePath'), isTrue);
      expect(edit.contains('useCardAsAvatar: cardImagePath == null'), isTrue);
    });

    test('🚨 새 사진이 없으면 기존 것을 안 지운다', () {
      expect(
        edit.contains('String? mergedCardImagePath = existing.cardImagePath'),
        isTrue,
        reason: '기본값이 기존 경로여야 한다 — null 로 시작하면 사진 없이 '
            '합칠 때 기존 사진이 지워진다',
      );
      expect(
        edit.contains('if (saved != null) mergedCardImagePath = saved'),
        isTrue,
        reason: '저장이 실패해도 기존 것을 지키다 — 오늘 officePhone 이 null 로 '
            '덮이던 것과 같은 함정이다',
      );
    });

    test('⭐ 사진이 없으면 대표 이미지도 끈다', () {
      expect(
        edit.contains('useCardAsAvatar: cardImagePath == null\n          ? false'),
        isTrue,
        reason: '사진이 없는데 켜 두면 화면이 빈 자리를 그린다',
      );
    });
  });
}
