/// "전한 대화 포인트를 소통 기록에 저장" 기능(2026-08-11)에서 쓰는 대기 의도.
///
/// 통화/문자/카톡/더보기(이메일)로 실제로 앱을 벗어난 순간 기억해 두었다가,
/// 앱이 다시 활성화되면 한 번 확인한 뒤 `CommunicationLogModel`로 저장한다.
/// `channel`은 `CommunicationLogModel.type`과 같은 값을 쓴다
/// ('call'|'sms'|'kakao'|'email'). 더보기의 일반 공유(이메일 외)는 애초에
/// 이 의도를 만들지 않는다(결정 ①-(a), 기록 안 함).
class PendingCommLogIntent {
  final String contactId;
  final String channel;
  final String point;

  const PendingCommLogIntent({
    required this.contactId,
    required this.channel,
    required this.point,
  });
}

/// 확인 다이얼로그에서 사용자가 고른 결과.
enum PendingCommLogAction { discard, edit, save }

/// 대기 의도를 **1건만** 유지하는 아주 작은 저장소.
///
/// - 연속으로 다른 경로를 눌러도 [remember]가 이전 값을 덮어써 마지막 1건만
///   남는다(중복 저장 방지 — 인수 기준 "연속으로 두 경로 눌러도 중복 저장
///   안 됨").
/// - [consume]은 값을 반환함과 동시에 비운다. 확인 다이얼로그를 처리하기
///   "시작하는 순간" 바로 소거해야, 다이얼로그가 떠 있는 도중 앱이 다시
///   백그라운드/포그라운드를 오가도 두 번 뜨지 않는다.
class PendingCommLogTracker {
  PendingCommLogIntent? _current;

  bool get hasPending => _current != null;

  void remember(PendingCommLogIntent intent) {
    _current = intent;
  }

  /// 값을 반환하고 즉시 비운다. 애초에 없었거나 이미 소거됐으면 null —
  /// 이 경우 호출자는 아무 UI도 띄우지 않는다("경로를 안 눌렀는데 앱만
  /// 왔다갔다 → 확인 안 뜸").
  PendingCommLogIntent? consume() {
    final value = _current;
    _current = null;
    return value;
  }

  void clear() {
    _current = null;
  }
}

/// 채널 코드를 사용자에게 보여줄 한글 라벨로 바꾼다.
String communicationChannelLabel(String channel) => switch (channel) {
  'call' => '통화',
  'sms' => '문자',
  'kakao' => '카톡',
  'email' => '이메일',
  _ => channel,
};

/// 확인 다이얼로그 미리보기 — 포인트 한 줄만, 길면 말줄임. 전화번호·이메일
/// 등 개인정보 원문은 절대 넣지 않는다(스펙 4번 — 저장 내용은 대화
/// 포인트뿐).
String communicationLogPreview(String point, {int maxLength = 60}) {
  final singleLine = point.replaceAll('\n', ' ').trim();
  return singleLine.length > maxLength
      ? '${singleLine.substring(0, maxLength)}…'
      : singleLine;
}
