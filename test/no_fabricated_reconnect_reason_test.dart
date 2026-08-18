// F-10 A의 "이유" 문구가 **실제 데이터에서만** 나오는지 검사한다.
//
// 왜 이 검사가 따로 필요한가: 이 결함은 **코드가 정상 동작하는데 내용이 거짓인**
// 유형이라 기능 테스트로 안 잡힌다. 화면은 잘 뜨고 목록도 잘 나오며, 다만 옆에
// 붙은 이유가 사실이 아닐 뿐이다. 그 사람의 실제 기록을 아는 사용자가 보기
// 전까지는 아무도 모른다(CLAUDE.md 4절 "코드 리뷰로는 안 잡히는 결함").
//
// 왜 하필 여기가 위험한가: A의 이유는 사용자가 **그걸 보고 연락할지 말지를
// 정하는** 값이다. "2주 전 통화 반응 좋았어요"를 믿고 전화를 걸었는데 그런 통화가
// 없었으면, 그 사용자는 이 기능을 다시는 안 믿는다. 근거 없는 문장 하나가 나머지
// 이유 전부를 같이 죽인다.
//
// 이 저장소에서 실제로 겪은 같은 유형:
// - 2026-08-14 명함 등록 태그 기본값 `'AI, IT'`가 박혀 있었다.
// - 2026-08-15 메모에 `'AI OCR 스캔으로 자동 추출된…'`이 자동으로 들어갔다.
//   ⚠️ **둘 다 앱이 만든 문장이 사용자 데이터로 저장돼 AI 요청에까지 실려 나갔다.**
//
// 검사 둘:
//  ① 이유 문구를 만드는 곳이 `reconnect_priority_service.dart` 하나뿐인가
//     (소스 훑기 — 화면 코드가 손으로 이유를 쓰면 출처를 추적할 수 없다).
//  ② 나온 문구가 실제 데이터로 되짚어지는가 (메모 인용은 원본의 부분 문자열,
//     근거 없으면 Tier1 아님).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/reconnect_priority_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';

ContactModel _contact({
  required String id,
  String name = '홍길동',
  String? memo,
  List<CommunicationLogModel> logs = const [],
  String? outcome,
  DateTime? outcomeAt,
  DateTime? nextFollowUpAt,
  DateTime? snoozedUntil,
  int noResponseStreak = 0,
}) {
  return ContactModel(
    id: id,
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

/// 오래 전에 등록된 것으로 보이게 하는 id(밀리초 문자열).
String _idAt(DateTime at) => at.millisecondsSinceEpoch.toString();

void main() {
  group('① 이유 문구는 한 곳에서만 만든다', () {
    test('reconnect_priority_service 밖에서 이유 문구를 손으로 쓰지 않는다', () {
      // 이유 문장에만 쓰이는 표현들. 화면 코드에서 이 말이 리터럴로 발견되면
      // 누군가 서비스를 거치지 않고 직접 문구를 만든 것이다.
      final reasonPhrases = <String>[
        '반응이 좋았어요',
        '연락 없음',
        '한 번도 연락 기록 없음',
        '다시 연락하기로 한 때',
        '다시 연락할 때',
        '메모: "',
      ];

      const owner = 'lib/core/services/reconnect_priority_service.dart';
      final offenders = <String>[];

      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final path = file.path.replaceAll(r'\', '/');
        if (path.endsWith(owner)) continue;
        final src = file.readAsStringSync();
        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // 주석 줄은 문구가 아니라 설명이다.
          if (line.trimLeft().startsWith('//')) continue;
          for (final phrase in reasonPhrases) {
            if (line.contains(phrase)) {
              offenders.add('$path:${i + 1} — "$phrase"\n    ${line.trim()}');
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A의 "이유"는 ReconnectPriorityService만 만든다.\n'
            '화면 코드가 직접 문구를 쓰면 그 문장이 어떤 데이터에서 나왔는지\n'
            '추적할 수 없고, 근거 없는 이유가 섞여도 아무도 모른다.\n'
            '${offenders.join('\n')}',
      );
    });
  });

  group('② 나온 문구가 실제 데이터로 되짚어진다', () {
    final now = DateTime(2026, 8, 15, 10);

    test('아무 데이터도 없으면 이야기를 지어내지 않는다', () {
      // 등록 시각도 알 수 없는(id가 시각이 아닌) 명함.
      final picked = ReconnectPriorityService.pick(
        contacts: [_contact(id: 'not-a-timestamp')],
        now: now,
      );

      expect(picked, hasLength(1));
      final reason = picked.single.reason;
      expect(reason.kind, ReconnectReasonKind.noHistory);
      expect(reason.text, '한 번도 연락 기록 없음');
      expect(reason.isStrong, isFalse, reason: '근거가 없으면 Tier1이 될 수 없다');
      expect(reason.memoExcerpt, isNull);
    });

    test('방치 기간만 알면 그것만 말한다 — Tier2', () {
      final picked = ReconnectPriorityService.pick(
        contacts: [_contact(id: _idAt(DateTime(2026, 4, 15)))],
        now: now,
      );

      expect(picked, hasLength(1));
      final reason = picked.single.reason;
      expect(reason.kind, ReconnectReasonKind.neglectedOnly);
      expect(reason.isStrong, isFalse);
      // 4개월(122일) → "4개월째 연락 없음"
      expect(reason.text, '4개월째 연락 없음');
    });

    test('메모 인용은 반드시 원본 메모의 부분 문자열이다', () {
      const memo = '보험 만기 8월, 자녀 대학 진학 준비 중이라고 함';
      final picked = ReconnectPriorityService.pick(
        contacts: [
          _contact(
            id: _idAt(DateTime(2026, 3, 1)),
            memo: memo,
            logs: [
              CommunicationLogModel(
                type: 'call',
                summary: '만기 안내',
                timestamp: DateTime(2026, 3, 10),
              ),
            ],
          ),
        ],
        now: now,
      );

      final reason = picked.single.reason;
      expect(reason.memoExcerpt, isNotNull);
      expect(
        memo.contains(reason.memoExcerpt!),
        isTrue,
        reason: '메모 인용은 요약·재작성 없이 원본을 그대로 잘라야 한다',
      );
      expect(reason.text.contains(reason.memoExcerpt!), isTrue);
      // 실제로 통화 기록이 있으므로 "통화"라고 말해도 된다.
      expect(reason.text.contains('통화'), isTrue);
      expect(reason.isStrong, isTrue);
    });

    test('채널을 확신할 수 없으면 채널 이름을 말하지 않는다', () {
      // 반응을 남긴 시각과 소통 기록 사이가 하루를 넘으면, 그 반응이 어느
      // 경로였는지 알 수 없다 — "통화"라고 쓰면 그것도 거짓이 된다.
      final picked = ReconnectPriorityService.pick(
        contacts: [
          _contact(
            id: _idAt(DateTime(2026, 1, 1)),
            outcome: 'good',
            outcomeAt: DateTime(2026, 7, 1),
            logs: [
              CommunicationLogModel(
                type: 'call',
                summary: '',
                timestamp: DateTime(2026, 2, 1),
              ),
            ],
          ),
        ],
        now: now,
      );

      final text = picked.single.reason.text;
      expect(text.contains('통화'), isFalse);
      expect(text.contains('문자'), isFalse);
      expect(text.contains('카톡'), isFalse);
      expect(text.contains('이메일'), isFalse);
      expect(text.contains('반응이 좋았어요'), isTrue);
    });

    test('C 기록이 없으면 반응에 대해 아무 말도 하지 않는다', () {
      final picked = ReconnectPriorityService.pick(
        contacts: [
          _contact(
            id: _idAt(DateTime(2026, 1, 1)),
            logs: [
              CommunicationLogModel(
                type: 'sms',
                summary: '',
                timestamp: DateTime(2026, 2, 1),
              ),
            ],
          ),
        ],
        now: now,
      );

      final reason = picked.single.reason;
      expect(reason.text.contains('반응'), isFalse);
      expect(reason.kind, ReconnectReasonKind.logged);
    });

    test('모든 이유 문구는 정해진 형태 중 하나다 — 자유 문장이 섞이지 않는다', () {
      // 여러 상황을 한꺼번에 돌려, 나온 문구가 전부 알려진 틀에 맞는지 본다.
      // 틀에 없는 문장이 나오면 어디선가 새 문구가 생긴 것이다.
      final contacts = <ContactModel>[
        _contact(id: 'x'),
        _contact(id: _idAt(DateTime(2025, 1, 1))),
        _contact(id: _idAt(DateTime(2025, 1, 1)), memo: '메모 있음'),
        _contact(
          id: _idAt(DateTime(2025, 1, 1)),
          logs: [
            CommunicationLogModel(
              type: 'kakao',
              summary: '',
              timestamp: DateTime(2026, 1, 5),
            ),
          ],
        ),
        _contact(
          id: _idAt(DateTime(2025, 1, 1)),
          outcome: 'good',
          outcomeAt: DateTime(2026, 6, 1),
        ),
        _contact(
          id: _idAt(DateTime(2025, 1, 1)),
          outcome: 'good',
          outcomeAt: DateTime(2026, 6, 1),
          nextFollowUpAt: DateTime(2026, 8, 1),
        ),
        _contact(
          id: _idAt(DateTime(2025, 1, 1)),
          nextFollowUpAt: DateTime(2026, 8, 1),
        ),
      ];

      // 기간 표현: '오늘' | 'N일' | 'N주' | 'N개월'
      const dur = r'(오늘|\d+일|\d+주|\d+개월)';
      const channel = r'(통화|문자|이메일|카톡|연락)';
      const memo = r'( · 메모: "[^"]*")?';
      final allowed = <RegExp>[
        RegExp('^한 번도 연락 기록 없음\$'),
        RegExp('^$dur째 연락 없음$memo\$'),
        RegExp('^연락 기록 없음$memo\$'),
        RegExp('^$dur 전 $channel$memo\$'),
        RegExp('^$dur 전 $channel 반응이 좋았어요$memo\$'),
        RegExp('^$dur 전 $channel 반응이 좋았어요 · 다시 연락할 때$memo\$'),
        RegExp('^다시 연락하기로 한 때$memo\$'),
      ];

      final picked = ReconnectPriorityService.pick(
        contacts: contacts,
        now: now,
        limit: contacts.length,
      );
      expect(picked, hasLength(contacts.length));

      for (final candidate in picked) {
        final text = candidate.reason.text;
        expect(
          allowed.any((re) => re.hasMatch(text)),
          isTrue,
          reason:
              '알려진 이유 틀에 없는 문구가 나왔다: "$text"\n'
              '새 문구를 추가했다면 이 목록에도 함께 추가해서, 무엇이 화면에\n'
              '나갈 수 있는지가 한눈에 보이도록 유지할 것.',
        );
      }
    });
  });
}
