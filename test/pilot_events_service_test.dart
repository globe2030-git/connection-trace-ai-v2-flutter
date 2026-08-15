import 'package:connection_trace_ai_flutter/core/services/pilot_events_service.dart';
import 'package:flutter_test/flutter_test.dart';

// PilotEventsService의 Firestore 접근 없이도 검증 가능한 순수 로직만 테스트.
// firestore.rules의 isValidPilotClientEvent와 같은 조건을 클라이언트 쪽에도
// 동일하게 두었으므로, 두 쪽이 어긋나면 앱은 "보낸 척" 기록하지만 서버가
// 조용히 거부해 지표가 실제보다 낮게 잡힌다 — 그 어긋남을 여기서 잡는다.
void main() {
  group('isValidPilotCopySendChannel — 서버 규칙의 채널 허용목록과 동일해야 함', () {
    for (final channel in ['call', 'sms', 'kakao', 'email']) {
      test('$channel은 유효한 채널', () {
        expect(isValidPilotCopySendChannel(channel), isTrue);
      });
    }

    test('허용 목록에 없는 채널은 무효(예: fax, share)', () {
      expect(isValidPilotCopySendChannel('fax'), isFalse);
      expect(isValidPilotCopySendChannel('share'), isFalse);
      expect(isValidPilotCopySendChannel(''), isFalse);
    });
  });

  group('isValidPilotFeedback — 서버 규칙의 feedback 조건과 동일해야 함', () {
    test('thumbsUp만 있으면 유효', () {
      expect(isValidPilotFeedback(thumbsUp: true), isTrue);
      expect(isValidPilotFeedback(thumbsUp: false), isTrue);
    });

    test('rating만 있고 1~5 범위면 유효', () {
      for (var r = 1; r <= 5; r++) {
        expect(isValidPilotFeedback(rating: r), isTrue);
      }
    });

    test('rating이 범위를 벗어나면 무효', () {
      expect(isValidPilotFeedback(rating: 0), isFalse);
      expect(isValidPilotFeedback(rating: 6), isFalse);
      expect(isValidPilotFeedback(rating: -1), isFalse);
    });

    test('thumbsUp도 rating도 없으면 무효(빈 반응)', () {
      expect(isValidPilotFeedback(), isFalse);
    });

    test('thumbsUp과 rating이 함께 있어도 유효(둘 다 기록 가능)', () {
      expect(isValidPilotFeedback(thumbsUp: true, rating: 4), isTrue);
    });
  });
}
