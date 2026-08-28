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
