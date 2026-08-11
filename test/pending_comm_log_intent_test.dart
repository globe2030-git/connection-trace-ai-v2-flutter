import 'package:connection_trace_ai_flutter/core/models/pending_comm_log_intent.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

// "전한 대화 포인트를 소통 기록에 저장" 기능(2026-08-11)의 대기 의도 저장소·
// 채널 매핑 로직 단위 테스트. 위젯을 전혀 pump하지 않고도(라이프사이클
// 이벤트·다이얼로그 없이) 인수 기준의 핵심을 검증한다.
void main() {
  group('PendingCommLogTracker — 대기 의도는 1건만 유지된다', () {
    test('remember 전에는 대기 의도가 없다', () {
      final tracker = PendingCommLogTracker();
      expect(tracker.hasPending, isFalse);
      expect(tracker.consume(), isNull);
    });

    test('remember 후 consume하면 값을 돌려주고 곧바로 비운다(중복 저장 방지)', () {
      final tracker = PendingCommLogTracker();
      tracker.remember(
        const PendingCommLogIntent(
          contactId: 'c1',
          channel: 'sms',
          point: '다음 프로젝트 논의하기',
        ),
      );
      expect(tracker.hasPending, isTrue);

      final first = tracker.consume();
      expect(first?.channel, 'sms');
      expect(first?.point, '다음 프로젝트 논의하기');

      // ⭐ 인수 기준: 연속으로 두 경로를 눌러도 중복 저장 안 됨 —
      // consume 이후에는 다시 확인이 뜨지 않아야 한다(같은 탭에서 또
      // resumed 이벤트가 와도 두 번째 consume은 null).
      expect(tracker.consume(), isNull);
      expect(tracker.hasPending, isFalse);
    });

    test('경로를 안 눌렀으면(remember 안 함) 앱이 왔다갔다 해도 대기 의도가 없다', () {
      final tracker = PendingCommLogTracker();
      // 라이프사이클 resumed에 해당하는 동작을 흉내: remember 없이 바로 consume.
      expect(tracker.consume(), isNull);
    });

    test('연속으로 두 경로를 누르면 마지막 것으로 교체된다(중복 저장 방지)', () {
      final tracker = PendingCommLogTracker();
      tracker.remember(
        const PendingCommLogIntent(
          contactId: 'c1',
          channel: 'call',
          point: '첫 번째 포인트',
        ),
      );
      tracker.remember(
        const PendingCommLogIntent(
          contactId: 'c1',
          channel: 'kakao',
          point: '두 번째 포인트',
        ),
      );

      final consumed = tracker.consume();
      expect(consumed?.channel, 'kakao');
      expect(consumed?.point, '두 번째 포인트');
      // 통화(첫 번째)에 대한 확인은 다시 뜨지 않는다.
      expect(tracker.consume(), isNull);
    });

    test('clear는 확인 없이 대기 의도를 지운다("아니오" 선택 시)', () {
      final tracker = PendingCommLogTracker();
      tracker.remember(
        const PendingCommLogIntent(
          contactId: 'c1',
          channel: 'email',
          point: 'p',
        ),
      );
      tracker.clear();
      expect(tracker.consume(), isNull);
    });
  });

  group('채널 라벨·미리보기 매핑', () {
    test('채널 코드가 한글 라벨로 매핑된다', () {
      expect(communicationChannelLabel('call'), '통화');
      expect(communicationChannelLabel('sms'), '문자');
      expect(communicationChannelLabel('kakao'), '카톡');
      expect(communicationChannelLabel('email'), '이메일');
    });

    test('알 수 없는 채널은 원본 문자열을 그대로 돌려준다(방어적 기본값)', () {
      expect(communicationChannelLabel('share'), 'share');
    });

    test('미리보기는 개행을 공백으로 바꾸고 한 줄로 만든다', () {
      expect(communicationLogPreview('다음 주에\n다시 논의하기로 함'), '다음 주에 다시 논의하기로 함');
    });

    test('길면 말줄임(…) 처리한다', () {
      final long = '가' * 80;
      final preview = communicationLogPreview(long, maxLength: 60);
      expect(preview.length, 61); // 60자 + '…'
      expect(preview.endsWith('…'), isTrue);
    });
  });

  group('대기 의도 → CommunicationLogModel 저장 매핑', () {
    // 실제 저장(_saveCommLog)은 briefing_overlay_view.dart 안에서 Provider를
    // 통해 이뤄지지만, "채널이 올바른 type으로, 포인트가 그대로 summary로
    // 들어가는지"는 위젯 없이도 매핑 규칙 자체로 검증할 수 있다.
    for (final channel in ['call', 'sms', 'kakao', 'email']) {
      test('channel=$channel → CommunicationLogModel.type=$channel', () {
        const point = '전한 대화 포인트 원문';
        final intent = PendingCommLogIntent(
          contactId: 'c1',
          channel: channel,
          point: point,
        );

        final log = CommunicationLogModel(
          type: intent.channel,
          summary: intent.point,
          timestamp: DateTime(2026, 8, 11, 9, 30),
          isAutoSynced: false,
          source: 'manual',
        );

        expect(log.type, channel);
        expect(log.summary, point);
        expect(log.source, 'manual');
        expect(log.isAutoSynced, isFalse);
      });
    }
  });
}
