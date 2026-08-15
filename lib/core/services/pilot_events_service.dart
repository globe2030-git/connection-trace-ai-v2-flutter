import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 대화 포인트를 전달한 채널 종류. 서버 규칙(`firestore.rules`의
/// `isValidPilotClientEvent`)이 허용하는 값과 정확히 같아야 한다 — 여기서
/// 벗어난 값을 보내면 규칙이 조용히 막는다(계측이라 실패해도 실제 전송
/// 기능에는 영향 없음).
const kPilotCopySendChannels = {'call', 'sms', 'kakao', 'email'};

/// [channel]이 계측 가능한 채널인지(순수 함수, Firestore 접근 없음). 서버
/// 규칙의 허용 목록과 반드시 같은 값을 유지해야 한다 — 어긋나면 앱은 "보낸
/// 척" 기록하지만 서버는 조용히 거부해 지표가 실제보다 낮게 잡힌다.
bool isValidPilotCopySendChannel(String channel) =>
    kPilotCopySendChannels.contains(channel);

/// 브리핑 반응(👍/👎 또는 1~5 척도) 입력이 유효한지(순수 함수). 서버 규칙과
/// 동일한 조건: 둘 다 없으면 무효, 척도는 1~5 범위만 허용.
bool isValidPilotFeedback({bool? thumbsUp, int? rating}) {
  if (thumbsUp == null && rating == null) return false;
  if (rating != null && (rating < 1 || rating > 5)) return false;
  return true;
}

/// 파일럿(베타) 계측 — 대화 포인트 복사/전송 이벤트와 브리핑 직후 반응
/// (피드백)을 `pilotEvents/{uid}/events/{eventId}`에 남긴다.
///
/// 배경: docs/planning/beta-observability-plan.md, 세션 작업 지시서
/// (2026-08-15). "명함 3장+AI 1회" 활성화 판정과 가입 주차 코호트는 서버
/// (Cloud Functions, index.ts의 `maybeRecordActivationEvent`/
/// `bootstrapAccount`)가 기록하고, 이 서비스는 **클라이언트에서만 알 수
/// 있는 두 이벤트**(실제로 채널을 눌러 전송한 순간, 브리핑을 본 사용자의
/// 즉각 반응)만 다룬다.
///
/// ### 개인정보 원칙(CLAUDE.md 4절)
/// - **대화 포인트 원문·상대방 식별 정보는 절대 남기지 않는다.** 어떤
///   채널로 보냈다는 사실, 시각, (피드백이면) 반응 값만 남긴다.
/// - Firestore 보안 규칙이 허용 필드를 화이트리스트로 강제하므로, 여기서
///   실수로 다른 필드를 넣어도 서버가 최종적으로 거부한다(2중 방어).
///
/// 로그인 안 했거나(uid 없음) Firestore 쓰기가 실패하면 조용히 무시한다 —
/// `OcrStatsService`와 같은 원칙: 계측 실패가 실제 기능(전송·브리핑 열람)을
/// 막으면 안 된다.
class PilotEventsService {
  /// 테스트에서 갈아끼울 수 있게 열어 둔다.
  final FirebaseFirestore Function() _firestoreFactory;
  final String? Function() _currentUid;

  PilotEventsService({
    FirebaseFirestore Function()? firestoreFactory,
    String? Function()? currentUid,
  }) : _firestoreFactory = firestoreFactory ?? (() => FirebaseFirestore.instance),
       _currentUid = currentUid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  /// 대화 포인트를 [channel]로 실제로 전달한 순간(앱을 벗어나는 데 성공한
  /// 직후, `_SendChannelRow.onSent`) 호출한다. 대화 포인트 원문은 받지
  /// 않는다 — 애초에 이 서비스가 알 필요가 없다.
  Future<void> recordCopySend(String channel) async {
    if (!isValidPilotCopySendChannel(channel)) {
      debugPrint('알 수 없는 계측 채널 — 건너뜀: $channel');
      return;
    }
    await _record({'type': 'copy_send', 'channel': channel});
  }

  /// 브리핑 직후 반응(👍/👎, 선택적으로 1~5 척도)을 기록한다. 두 값 모두
  /// 없는 호출은 만들지 않는다(서버 규칙도 같은 조건을 강제).
  Future<void> recordFeedback({bool? thumbsUp, int? rating}) async {
    if (!isValidPilotFeedback(thumbsUp: thumbsUp, rating: rating)) {
      debugPrint('유효하지 않은 피드백 입력 — 건너뜀 (thumbsUp=$thumbsUp, rating=$rating)');
      return;
    }
    final fields = <String, dynamic>{'type': 'feedback'};
    if (thumbsUp != null) {
      fields['thumbsUp'] = thumbsUp;
    }
    if (rating != null) {
      fields['rating'] = rating;
    }
    await _record(fields);
  }

  Future<void> _record(Map<String, dynamic> fields) async {
    try {
      final uid = _currentUid();
      if (uid == null) return; // 게스트는 남기지 않는다.
      final ref = _firestoreFactory()
          .collection('pilotEvents')
          .doc(uid)
          .collection('events')
          .doc();
      await ref.set({...fields, 'uid': uid, 'at': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('파일럿 계측 이벤트 기록 실패: $e');
    }
  }
}
