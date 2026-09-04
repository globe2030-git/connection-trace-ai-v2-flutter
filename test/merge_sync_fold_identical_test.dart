/// **두 기기가 같은 사람을 각각 등록한 것을 동기화가 접는다** (2026-09-04).
///
/// ## 왜 이 테스트가 생겼나
///
/// 판정기([isSafeToMergeAutomatically])는 2026-08-29에 만들어져 있었는데
/// **`lib/` 안에서 부르는 곳이 0건**이었다 — 테스트만 불렀다. 판정만 있고
/// **합치는 손이 없었다.** 이 저장소가 반복해서 겪은 모양이다(추가 79 —
/// 서비스는 정상, 부르는 쪽이 없음).
///
/// 🚨 **그래서 이 테스트가 지키는 것은 「판정이 맞는가」가 아니라
/// 「판정기가 실제로 불리는가」다.** 연결이 끊기면 여기서 깨진다.
///
/// ## 접기의 원칙 — 서버는 건드리지 않는다
///
/// 판정기 머리말이 경고한다: *"동기화는 아무도 안 보는 자리다 — 거기서
/// 자동으로 합치면 잃어도 모른다."* 그래서 접는 것은 **이 기기가 보는
/// 목록**뿐이고, 서버 원본 둘은 그대로 남는다.
library;

import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel c({
  required String id,
  String name = '홍길동',
  String company = '가상상사',
  String title = '부장',
  String phone = '010-0000-0000',
  String email = 'a@b.c',
  String? memo,
  String? cardImagePath,
  List<CommunicationLogModel> logs = const [],
  DateTime? updatedAt,
}) => ContactModel(
  id: id,
  name: name,
  company: company,
  title: title,
  phone: phone,
  email: email,
  tags: const [],
  talkingPoints: const [],
  memo: memo,
  cardImagePath: cardImagePath,
  commLogs: logs,
  updatedAt: updatedAt,
);

CommunicationLogModel log(String id) => CommunicationLogModel(
  id: id,
  type: 'call',
  summary: '통화',
  timestamp: DateTime.utc(2026, 9, 1),
);

void main() {
  group('동기화가 완전히 같은 명함을 접는다', () {
    test('⭐ 폰과 태블릿이 같은 사람을 각각 등록했다 — 목록에 하나만 남는다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: '폴드가-만든-id')],
        server: [c(id: '태블릿이-만든-id')],
        tombstones: const {},
      );
      expect(out.merged.length, 1);
    });

    test('🚨 사진이 한쪽에만 있으면 살린다 — 추가 552 에서 버렸던 자리다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b', cardImagePath: '/폴드/b.enc')],
        server: [c(id: 'a')],
        tombstones: const {},
      );
      expect(out.merged.length, 1);
      expect(out.merged.single.cardImagePath, '/폴드/b.enc');
    });

    test('메모가 한쪽에만 있어도 살린다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b', memo: '전시회에서 만남')],
        server: [c(id: 'a')],
        tombstones: const {},
      );
      expect(out.merged.single.memo, '전시회에서 만남');
    });

    test('🚨 남는 id 는 사전순으로 정해진다 — 기기마다 같은 답이 나와야 한다', () {
      // 같은 쌍을 순서만 바꿔 넣어도 결과가 같아야 한다.
      final a = ContactsRepository.mergeSync(
        local: [c(id: 'zzz')],
        server: [c(id: 'aaa')],
        tombstones: const {},
      );
      final b = ContactsRepository.mergeSync(
        local: [c(id: 'aaa')],
        server: [c(id: 'zzz')],
        tombstones: const {},
      );
      expect(a.merged.single.id, 'aaa');
      expect(b.merged.single.id, 'aaa');
    });

    test('🚨 서버로 올리는 목록은 접지 않는다 — 원본이 서버에 남아야 되돌릴 수 있다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b'), c(id: 'c', name: '다른사람')],
        server: [c(id: 'a')],
        tombstones: const {},
      );
      // 로컬에만 있던 둘은 그대로 올라간다. 접기는 화면용 목록에만 적용된다.
      expect(out.toPush.map((e) => e.id), containsAll(['b', 'c']));
    });
  });

  group('접으면 안 되는 것', () {
    test('🚨 소통 기록이 양쪽에 서로 다르면 접지 않는다 — 추가 553 에서 이력을 버렸다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b', logs: [log('폴드-기록')])],
        server: [c(id: 'a', logs: [log('태블릿-기록')])],
        tombstones: const {},
      );
      expect(out.merged.length, 2);
    });

    test('소통 기록이 한쪽에만 있으면 접고 살린다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b', logs: [log('폴드-기록')])],
        server: [c(id: 'a')],
        tombstones: const {},
      );
      expect(out.merged.length, 1);
      expect(out.merged.single.commLogs.single.id, '폴드-기록');
    });

    test('사람이 읽는 칸이 다르면 다른 사람이다 — 둘 다 남는다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'b', company: '다른회사')],
        server: [c(id: 'a')],
        tombstones: const {},
      );
      expect(out.merged.length, 2);
    });

    test('같은 id 는 접기 대상이 아니다 — 이미 위 병합이 다뤘다', () {
      final out = ContactsRepository.mergeSync(
        local: [c(id: 'a', memo: '새 메모', updatedAt: DateTime.utc(2026, 9, 2))],
        server: [c(id: 'a', updatedAt: DateTime.utc(2026, 9, 1))],
        tombstones: const {},
      );
      expect(out.merged.length, 1);
      expect(out.merged.single.memo, '새 메모');
    });
  });

  test('⭐ 멱등하다 — 접힌 결과를 다시 넣어도 같다', () {
    final once = ContactsRepository.mergeSync(
      local: [c(id: 'b', cardImagePath: '/폴드/b.enc')],
      server: [c(id: 'a')],
      tombstones: const {},
    );
    final twice = ContactsRepository.mergeSync(
      local: once.merged,
      server: const [],
      tombstones: const {},
    );
    expect(twice.merged.length, 1);
    expect(twice.merged.single.cardImagePath, '/폴드/b.enc');
  });
}
