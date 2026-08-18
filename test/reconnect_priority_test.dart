// F-10 재연락 루프(A+C)의 **규칙**을 검증한다.
//
// 화면이 아니라 규칙을 본다: 누가 후보가 되고, 어떤 순서로 오고, C에서 누른
// 것이 다음 A에 어떻게 되먹임되는가. 날짜 계산이 핵심이라 `now`를 인자로
// 고정해 두고 검사한다.
//
// 문구가 실제 데이터에서 나오는지는 `no_fabricated_reconnect_reason_test.dart`가
// 따로 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/reconnect_priority_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';

final _now = DateTime(2026, 8, 15, 10);

String _idAt(DateTime at) => at.millisecondsSinceEpoch.toString();

ContactModel _contact({
  String? id,
  required String name,
  DateTime? registeredAt,
  String? memo,
  List<CommunicationLogModel> logs = const [],
  String? outcome,
  DateTime? outcomeAt,
  DateTime? nextFollowUpAt,
  DateTime? snoozedUntil,
  int noResponseStreak = 0,
}) {
  return ContactModel(
    id: id ?? _idAt(registeredAt ?? DateTime(2025, 1, 1)),
    name: name,
    company: '',
    title: '',
    phone: '',
    email: '',
    tags: const [],
    talkingPoints: const [],
    commLogs: logs,
    memo: memo,
    lastReconnectOutcome: outcome,
    lastReconnectOutcomeAt: outcomeAt,
    nextFollowUpAt: nextFollowUpAt,
    reconnectSnoozedUntil: snoozedUntil,
    reconnectNoResponseStreak: noResponseStreak,
  );
}

CommunicationLogModel _log(DateTime at, {String type = 'call'}) =>
    CommunicationLogModel(type: type, summary: '', timestamp: at);

void main() {
  group('후보 자격', () {
    test('최근 30일 안에 연락한 사람은 뜨지 않는다', () {
      final recent = _contact(
        name: '최근',
        logs: [_log(DateTime(2026, 8, 1))], // 14일 전
      );
      final old = _contact(
        name: '오래',
        logs: [_log(DateTime(2026, 1, 1))],
      );

      final picked = ReconnectPriorityService.pick(
        contacts: [recent, old],
        now: _now,
      );

      expect(picked.map((c) => c.contact.name), ['오래']);
    });

    test('경계값 — 30일째는 아직 아니고, 31일째부터 후보다', () {
      final exactly30 = _contact(
        name: '삼십일',
        logs: [_log(_now.subtract(const Duration(days: 30)))],
      );
      final day31 = _contact(
        name: '삼십일일',
        logs: [_log(_now.subtract(const Duration(days: 31)))],
      );

      final picked = ReconnectPriorityService.pick(
        contacts: [exactly30, day31],
        now: _now,
      );

      expect(picked.map((c) => c.contact.name), ['삼십일일']);
    });

    test('스누즈 중이면 빠지고, 기간이 지나면 돌아온다', () {
      final snoozed = _contact(
        name: '넘김',
        logs: [_log(DateTime(2026, 1, 1))],
        snoozedUntil: _now.add(const Duration(days: 3)),
      );

      expect(
        ReconnectPriorityService.pick(contacts: [snoozed], now: _now),
        isEmpty,
      );

      // 스누즈가 끝난 뒤
      expect(
        ReconnectPriorityService.pick(
          contacts: [snoozed],
          now: _now.add(const Duration(days: 4)),
        ),
        hasLength(1),
      );
    });

    test('"이번엔 넘김"은 7일 뒤로 미룬다', () {
      final contact = _contact(name: '넘김', logs: [_log(DateTime(2026, 1, 1))]);
      final snoozed = ReconnectPriorityService.applySnooze(
        contact: contact,
        now: _now,
      );

      expect(
        snoozed.reconnectSnoozedUntil,
        _now.add(const Duration(days: ReconnectPriorityService.snoozeDays)),
      );
      expect(
        ReconnectPriorityService.pick(contacts: [snoozed], now: _now),
        isEmpty,
      );
      expect(
        ReconnectPriorityService.pick(
          contacts: [snoozed],
          now: _now.add(const Duration(days: 8)),
        ),
        hasLength(1),
      );
    });

    test('재연락 시점을 정했으면 그날이 오기 전에는 안 뜬다', () {
      final later = _contact(
        name: '나중에',
        logs: [_log(DateTime(2026, 1, 1))], // 방치 기준으로는 이미 후보
        nextFollowUpAt: _now.add(const Duration(days: 5)),
      );

      expect(
        ReconnectPriorityService.pick(contacts: [later], now: _now),
        isEmpty,
        reason: '사용자가 정한 시점이 앱의 30일 규칙보다 우선한다',
      );
    });

    test('재연락 시점이 되면 최근에 연락했더라도 최우선으로 뜬다', () {
      final due = _contact(
        name: '오늘',
        logs: [_log(_now.subtract(const Duration(days: 3)))], // 사흘 전 연락
        outcome: 'good',
        outcomeAt: _now.subtract(const Duration(days: 3)),
        nextFollowUpAt: _now.subtract(const Duration(hours: 1)),
      );
      final neglected = _contact(
        name: '방치',
        logs: [_log(DateTime(2024, 1, 1))],
      );

      final picked = ReconnectPriorityService.pick(
        contacts: [neglected, due],
        now: _now,
      );

      expect(picked.first.contact.name, '오늘');
      expect(picked.first.reason.kind, ReconnectReasonKind.followUpDue);
      expect(picked.first.reason.isStrong, isTrue);
    });

    test('하루에 3명까지만 고른다', () {
      final many = List.generate(
        10,
        (i) => _contact(
          id: 'id-$i',
          name: '사람$i',
          registeredAt: DateTime(2024, 1, 1),
          logs: [_log(DateTime(2024, 6, i + 1))],
        ),
      );

      final picked = ReconnectPriorityService.pick(
        contacts: many,
        now: _now,
      );

      expect(picked, hasLength(ReconnectPriorityService.dailyCount));
      expect(ReconnectPriorityService.dailyCount, 3);
    });

    test('후보가 없으면 빈 목록이다 — 억지로 채우지 않는다', () {
      final recentOnly = [
        _contact(name: 'A', logs: [_log(_now.subtract(const Duration(days: 2)))]),
        _contact(name: 'B', logs: [_log(_now.subtract(const Duration(days: 5)))]),
      ];

      expect(
        ReconnectPriorityService.pick(contacts: recentOnly, now: _now),
        isEmpty,
      );
    });
  });

  group('순서', () {
    test('근거가 있는 사람이 방치 기간만 있는 사람보다 위로 온다', () {
      // 방치 기간은 같게 두고 근거만 다르게 한다.
      final at = DateTime(2026, 2, 1);
      final bare = _contact(name: '근거없음', registeredAt: at);
      final withEvidence = _contact(
        name: '근거있음',
        registeredAt: at,
        memo: '만기 8월',
        logs: [_log(at)],
      );

      final picked = ReconnectPriorityService.pick(
        contacts: [bare, withEvidence],
        now: _now,
      );

      expect(picked.map((c) => c.contact.name), ['근거있음', '근거없음']);
    });

    test('오래 방치된 쪽이 위로 온다', () {
      final older = _contact(name: '오래', logs: [_log(DateTime(2025, 1, 1))]);
      final newer = _contact(name: '덜오래', logs: [_log(DateTime(2026, 5, 1))]);

      final picked = ReconnectPriorityService.pick(
        contacts: [newer, older],
        now: _now,
      );

      expect(picked.map((c) => c.contact.name), ['오래', '덜오래']);
    });

    test('점수가 같으면 이름순 — 같은 상황이면 항상 같은 순서가 나온다', () {
      final at = DateTime(2026, 1, 1);
      final a = _contact(id: 'z', name: '가', registeredAt: at, logs: [_log(at)]);
      final b = _contact(id: 'a', name: '나', registeredAt: at, logs: [_log(at)]);

      final first = ReconnectPriorityService.pick(
        contacts: [b, a],
        now: _now,
      );
      final second = ReconnectPriorityService.pick(
        contacts: [a, b],
        now: _now,
      );

      expect(first.map((c) => c.contact.name), ['가', '나']);
      expect(
        second.map((c) => c.contact.name),
        first.map((c) => c.contact.name),
      );
    });

    test('반응 "없음"이 쌓이면 뒤로 밀린다 — 사라지지는 않는다', () {
      final at = DateTime(2026, 1, 1);
      final ignored = _contact(
        name: '무응답',
        registeredAt: at,
        logs: [_log(at)],
        outcome: 'none',
        outcomeAt: DateTime(2026, 2, 1),
        noResponseStreak: 3,
      );
      final normal = _contact(name: '보통', registeredAt: at, logs: [_log(at)]);

      final picked = ReconnectPriorityService.pick(
        contacts: [ignored, normal],
        now: _now,
      );

      expect(picked.map((c) => c.contact.name), ['보통', '무응답']);
      expect(picked, hasLength(2), reason: '밀어낼 뿐 목록에서 지우지 않는다');
    });
  });

  group('C — 연락 후 후속', () {
    test('"좋음 + 2주 뒤"를 고르면 2주 뒤가 재연락 시점이 된다', () {
      final contact = _contact(name: '홍', logs: [_log(DateTime(2026, 1, 1))]);

      final updated = ReconnectPriorityService.applyOutcome(
        contact: contact,
        outcome: ReconnectOutcome.good,
        now: _now,
        followUpAfter: const Duration(days: 14),
      );

      expect(updated.lastReconnectOutcome, 'good');
      expect(updated.lastReconnectOutcomeAt, _now);
      expect(updated.nextFollowUpAt, _now.add(const Duration(days: 14)));
      expect(updated.reconnectNoResponseStreak, 0);

      // 그 전에는 안 뜨고
      expect(
        ReconnectPriorityService.pick(
          contacts: [updated],
          now: _now.add(const Duration(days: 13)),
        ),
        isEmpty,
      );
      // 그날이 되면 뜬다 — 이게 C→A 되먹임이다
      final due = ReconnectPriorityService.pick(
        contacts: [updated],
        now: _now.add(const Duration(days: 14, hours: 1)),
      );
      expect(due, hasLength(1));
      expect(due.single.reason.kind, ReconnectReasonKind.followUpDue);
    });

    test('"안 정함"이면 다음 시점을 비운다 — 날짜를 지어내지 않는다', () {
      final contact = _contact(
        name: '홍',
        logs: [_log(DateTime(2026, 1, 1))],
        nextFollowUpAt: _now.add(const Duration(days: 30)),
      );

      final updated = ReconnectPriorityService.applyOutcome(
        contact: contact,
        outcome: ReconnectOutcome.normal,
        now: _now,
        followUpAfter: null,
      );

      expect(updated.nextFollowUpAt, isNull);
      expect(updated.lastReconnectOutcome, 'normal');
    });

    test('반응 "없음"은 연속 횟수를 올리고, 다른 반응이 나오면 0으로 되돌린다', () {
      final base = _contact(name: '홍', logs: [_log(DateTime(2026, 1, 1))]);

      final once = ReconnectPriorityService.applyOutcome(
        contact: base,
        outcome: ReconnectOutcome.none,
        now: _now,
      );
      expect(once.reconnectNoResponseStreak, 1);

      final twice = ReconnectPriorityService.applyOutcome(
        contact: once,
        outcome: ReconnectOutcome.none,
        now: _now,
      );
      expect(twice.reconnectNoResponseStreak, 2);

      final recovered = ReconnectPriorityService.applyOutcome(
        contact: twice,
        outcome: ReconnectOutcome.good,
        now: _now,
      );
      expect(recovered.reconnectNoResponseStreak, 0);
    });

    test('후속을 남기면 남아 있던 스누즈가 풀린다', () {
      final snoozed = _contact(
        name: '홍',
        logs: [_log(DateTime(2026, 1, 1))],
        snoozedUntil: _now.add(const Duration(days: 5)),
      );

      final updated = ReconnectPriorityService.applyOutcome(
        contact: snoozed,
        outcome: ReconnectOutcome.good,
        now: _now,
        followUpAfter: const Duration(days: 7),
      );

      expect(
        updated.reconnectSnoozedUntil,
        isNull,
        reason: '스누즈가 남아 있으면 사용자가 정한 재연락 시점이 와도 막힌다',
      );
    });

    test('C 값은 저장·복원을 넘어 살아남는다', () {
      final contact = ReconnectPriorityService.applyOutcome(
        contact: _contact(name: '홍', logs: [_log(DateTime(2026, 1, 1))]),
        outcome: ReconnectOutcome.good,
        now: _now,
        followUpAfter: const Duration(days: 7),
      );

      final roundTripped = ContactModel.fromJson(contact.toJson());
      expect(roundTripped.lastReconnectOutcome, 'good');
      expect(roundTripped.lastReconnectOutcomeAt, contact.lastReconnectOutcomeAt);
      expect(roundTripped.nextFollowUpAt, contact.nextFollowUpAt);
      expect(roundTripped.reconnectNoResponseStreak, 0);

      // 서버 백업 경로에도 함께 올라가야 기기를 바꿔도 약속이 남는다.
      final fromBackup = ContactModel.fromJson(contact.toBackupJson());
      expect(fromBackup.nextFollowUpAt, contact.nextFollowUpAt);
      expect(fromBackup.lastReconnectOutcome, 'good');
    });

    test('예전 데이터(F-10 필드 없음)를 읽어도 기본값으로 안전하게 열린다', () {
      final legacy = ContactModel.fromJson({
        'id': '1',
        'name': '홍',
        'company': '',
        'title': '',
        'phone': '',
        'email': '',
        'tags': <String>[],
        'talkingPoints': <String>[],
      });

      expect(legacy.lastReconnectOutcome, isNull);
      expect(legacy.nextFollowUpAt, isNull);
      expect(legacy.reconnectSnoozedUntil, isNull);
      expect(legacy.reconnectNoResponseStreak, 0);
    });
  });

  group('등록 시점 추정', () {
    test('id가 시각이 아니면 추측하지 않는다', () {
      final contact = _contact(id: 'uuid-abc', name: '홍');
      expect(ReconnectPriorityService.registeredAtOf(contact, _now), isNull);
    });

    test('미래이거나 말이 안 되는 값도 추측하지 않는다', () {
      final future = _contact(
        id: _idAt(_now.add(const Duration(days: 1))),
        name: '홍',
      );
      expect(ReconnectPriorityService.registeredAtOf(future, _now), isNull);

      final tooOld = _contact(id: '12345', name: '홍');
      expect(ReconnectPriorityService.registeredAtOf(tooOld, _now), isNull);
    });

    test('밀리초 id면 등록 시각으로 읽는다', () {
      final at = DateTime(2025, 3, 4, 5, 6);
      final contact = _contact(id: _idAt(at), name: '홍');
      expect(ReconnectPriorityService.registeredAtOf(contact, _now), at);
    });
  });

  // -------------------------------------------------------------------
  // 문구 — 0일일 때 한국어가 깨지던 자리 (추가 313)
  //
  // 실기기에서 **"오늘째 연락 없음"**이 그대로 화면에 실렸다. 규칙은 이
  // 파일이 촘촘히 덮고 있었는데 **문구는 아무도 안 보고 있었다.**
  //
  // ⚠️ 아래 테스트는 **실제로 그 문구가 나오는 경로**를 타야 한다. 처음에
  // 썼던 판본은 `nextFollowUpAt`만 세워 두고 검사했는데, 그러면 이유가
  // "다시 연락하기로 한 때"로 빠져 **문구를 안 거치고도 통과**했다.
  // 통과하는데 아무것도 안 보는 테스트가 제일 나쁘다.
  // -------------------------------------------------------------------
  group('문구 — 0일 (추가 313)', () {
    test('⚠️ "오늘 전 연락"이 아니라 "오늘 연락"이다', () {
      // 오늘 연락해서 반응이 좋았고, 후속 시점도 오늘 — 이유 ①로 간다.
      final contact = _contact(
        name: '오늘반응좋음',
        registeredAt: DateTime(2026, 1, 1),
        outcome: 'good',
        outcomeAt: _now.subtract(const Duration(hours: 2)),
        nextFollowUpAt: _now.subtract(const Duration(hours: 1)),
      );

      final text = ReconnectPriorityService.pick(
        contacts: [contact],
        now: _now,
      ).single.reason.text;

      expect(text, contains('오늘 연락'));
      expect(text, isNot(contains('오늘 전')), reason: '"오늘 전 연락"은 말이 안 된다');
    });

    test('⭐ 하루 이상 지난 자리는 예전 그대로 "N일 전"이다', () {
      final contact = _contact(
        name: '사흘전반응좋음',
        registeredAt: DateTime(2026, 1, 1),
        outcome: 'good',
        outcomeAt: _now.subtract(const Duration(days: 3)),
        nextFollowUpAt: _now.subtract(const Duration(hours: 1)),
      );

      expect(
        ReconnectPriorityService.pick(
          contacts: [contact],
          now: _now,
        ).single.reason.text,
        contains('3일 전'),
      );
    });

    test('⭐ 방치 문구는 예전 그대로 "N째 연락 없음"이다', () {
      final contact = _contact(
        name: '오래방치',
        registeredAt: _now.subtract(const Duration(days: 40)),
      );

      expect(
        ReconnectPriorityService.pick(
          contacts: [contact],
          now: _now,
        ).single.reason.text,
        contains('째 연락 없음'),
      );
    });

    // 📌 방치 0일은 **지금 규칙으로는 후보가 되지 않는다** — 후보가 되려면
    // 30일을 넘거나 후속 시점이 됐어야 하는데, 후자는 이유 ①로 빠진다.
    // 그래서 "오늘째 연락 없음"은 실기기에서 임계값을 낮춰야 보였다.
    // 문구 함수를 고친 것은 **그 자리가 언제든 열릴 수 있어서**이지,
    // 지금 사용자가 보고 있다는 뜻이 아니다. 여기에 적어 둔다.
  });
}
