/// F-10 **A. 재연락 우선순위** — "오늘 연락하면 좋은 사람"을 정하는 규칙.
///
/// ## 이 파일이 지켜야 하는 것
///
/// **AI를 부르지 않고, 서버로 아무것도 보내지 않는다.** 순위도 이유도 전부
/// 기기 안에서 이 파일의 규칙만으로 정한다. AI는 사용자가 [연락 가이드]를
/// 눌렀을 때만 개입한다(기존 브리핑). 그래야 사용자가 "왜 이 사람이 떴는지"를
/// 되짚을 수 있고, 순위를 매기려고 인맥 정보를 밖으로 내보내는 일이 없다.
///
/// **⚠️ 가짜 이유 금지 — 이 기능의 성패가 여기 걸려 있다.** 화면에 뜨는 "이유"는
/// 사용자가 그걸 보고 연락할지 말지를 정하는 값이다. 근거 없는 문장이 하나라도
/// 섞이면 나머지 이유까지 못 믿게 되고 기능 전체가 죽는다. 그래서
/// [ReconnectReason]은 **실제 데이터가 있을 때만** 만들어지며, 근거가 없으면
/// 이야기를 지어내는 대신 "한 번도 연락 기록 없음"이라고 그대로 말한다.
///
/// 이 규칙은 `test/reconnect_priority_test.dart`(동작)와
/// `test/no_fabricated_reconnect_reason_test.dart`(문구 출처)가 함께 지킨다.
/// 특히 뒤엣것은 **이 파일 밖에서 이유 문구를 손으로 쓰는 것**을 막는다 —
/// 이 저장소에서 앱이 만든 문장이 사용자 데이터로 저장되고 AI 요청에까지
/// 실려 나간 일이 두 번 있었다(태그 기본값 `'AI, IT'`, 메모 자동 문구).
library;

import '../../data/models/contact_model.dart';

/// 이유의 종류. 종류마다 **어떤 실제 데이터가 있어야 하는지**가 정해져 있다.
enum ReconnectReasonKind {
  /// C에서 사용자가 "언제 다시"로 고른 날짜가 됐다. 가장 강한 근거 —
  /// 사용자 본인이 직접 정한 시점이다.
  followUpDue,

  /// 직전 연락 반응이 "좋음"이었다(C 기록).
  goodOutcome,

  /// 소통 기록이 있고 메모도 있다.
  loggedWithMemo,

  /// 소통 기록이 있다(메모는 없음).
  logged,

  /// 소통 기록은 없지만 메모가 있다.
  memoOnly,

  /// 근거가 방치 기간뿐이다.
  neglectedOnly,

  /// 아무 데이터도 없다.
  noHistory,
}

/// 화면에 보여 줄 이유 한 줄.
///
/// [text]는 [ReconnectPriorityService]만 만든다. 밖에서 새로 조립하지 말 것 —
/// 그 순간 출처를 추적할 수 없는 문장이 생긴다.
class ReconnectReason {
  final ReconnectReasonKind kind;
  final String text;

  /// 메모에서 따온 부분(있으면). **반드시 원본 메모의 부분 문자열이다** —
  /// 요약하거나 다듬지 않는다. 회귀 테스트가 이걸 검사한다.
  final String? memoExcerpt;

  const ReconnectReason._({
    required this.kind,
    required this.text,
    this.memoExcerpt,
  });

  /// 스펙의 Tier1(강한 근거) 여부. 구체적 근거가 있는 이유만 강하다.
  bool get isStrong =>
      kind != ReconnectReasonKind.neglectedOnly &&
      kind != ReconnectReasonKind.noHistory;
}

/// 한 명의 후보.
class ReconnectCandidate {
  final ContactModel contact;
  final ReconnectReason reason;
  final double score;

  /// 마지막 소통 시점(기록이 없으면 null). 화면에서 다시 계산하지 않도록 같이 넘긴다.
  final DateTime? lastContactAt;

  const ReconnectCandidate({
    required this.contact,
    required this.reason,
    required this.score,
    required this.lastContactAt,
  });
}

/// C(연락 후 후속)에서 사용자가 고른 반응.
enum ReconnectOutcome { good, normal, none }

extension ReconnectOutcomeCode on ReconnectOutcome {
  String get code => switch (this) {
    ReconnectOutcome.good => 'good',
    ReconnectOutcome.normal => 'normal',
    ReconnectOutcome.none => 'none',
  };

  static ReconnectOutcome? fromCode(String? code) => switch (code) {
    'good' => ReconnectOutcome.good,
    'normal' => ReconnectOutcome.normal,
    'none' => ReconnectOutcome.none,
    _ => null,
  };
}

class ReconnectPriorityService {
  ReconnectPriorityService._();

  /// 하루에 보여 주는 인원. 스펙 확정값 3명.
  ///
  /// 작게 잡은 이유: 20명이 뜨면 그건 목록이지 "오늘 할 일"이 아니다. 다 못
  /// 하면 매일 밀린 느낌만 남고, 그러면 사용자는 이 섹션을 안 보게 된다.
  static const int dailyCount = 3;

  /// "방치"로 보는 기준. 스펙 확정값 30일.
  static const int neglectThresholdDays = 30;

  /// 스누즈("이번엔 넘김") 기간. 스펙 확정값 7일.
  static const int snoozeDays = 7;

  /// 메모에서 따올 최대 길이. 길면 이유 줄이 화면을 밀어낸다.
  static const int memoExcerptMaxLength = 24;

  /// 오늘 연락하면 좋은 사람 [dailyCount]명을 고른다.
  ///
  /// [now]를 인자로 받는 이유: 날짜 규칙이 핵심이라 테스트에서 시간을 고정해야
  /// 한다. `DateTime.now()`를 안에서 부르면 그 규칙을 검증할 수 없다.
  static List<ReconnectCandidate> pick({
    required List<ContactModel> contacts,
    required DateTime now,
    int limit = dailyCount,
  }) {
    final candidates = <ReconnectCandidate>[];

    for (final contact in contacts) {
      final lastContactAt = lastContactTimeOf(contact);

      // 스누즈 중이면 무조건 뺀다. 사용자가 "이번엔 넘김"이라고 말한 것을
      // 다음 날 또 들이미는 것은 이 기능이 미움받는 가장 빠른 길이다.
      final snoozedUntil = contact.reconnectSnoozedUntil;
      if (snoozedUntil != null && snoozedUntil.isAfter(now)) continue;

      // 사용자가 C에서 "2주 뒤"라고 정했으면 그 전에는 뜨지 않는다.
      // 정한 날짜가 됐으면 30일 규칙과 무관하게 후보다 — 사용자 본인이
      // 정한 시점이 앱의 방치 기준보다 우선한다.
      final followUpAt = contact.nextFollowUpAt;
      final followUpDue = followUpAt != null && !followUpAt.isAfter(now);
      if (followUpAt != null && !followUpDue) continue;

      final neglectedDays = _neglectedDaysOf(contact, lastContactAt, now);

      if (!followUpDue) {
        // 최근에 연락했으면 뺀다.
        if (neglectedDays != null && neglectedDays <= neglectThresholdDays) {
          continue;
        }
      }

      final reason = _buildReason(
        contact: contact,
        now: now,
        lastContactAt: lastContactAt,
        neglectedDays: neglectedDays,
        followUpDue: followUpDue,
      );

      candidates.add(
        ReconnectCandidate(
          contact: contact,
          reason: reason,
          score: _scoreOf(
            contact: contact,
            neglectedDays: neglectedDays,
            followUpDue: followUpDue,
          ),
          lastContactAt: lastContactAt,
        ),
      );
    }

    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // 점수가 같으면 이름순 — 정렬이 매번 달라지면 사용자는 목록이 무작위라고
      // 느낀다. 같은 상황에서는 같은 순서가 나와야 한다.
      final byName = a.contact.name.compareTo(b.contact.name);
      if (byName != 0) return byName;
      return a.contact.id.compareTo(b.contact.id);
    });

    return candidates.take(limit).toList(growable: false);
  }

  /// 마지막 소통 기록 시점. 기록이 없으면 null.
  static DateTime? lastContactTimeOf(ContactModel contact) {
    DateTime? latest;
    for (final log in contact.commLogs) {
      if (latest == null || log.timestamp.isAfter(latest)) {
        latest = log.timestamp;
      }
    }
    return latest;
  }

  /// 이 명함을 등록한 시각의 **추정치**.
  ///
  /// 별도 `createdAt` 필드가 없다. 새 명함의 `id`는
  /// `DateTime.now().millisecondsSinceEpoch.toString()`이라(add_card_modal_view)
  /// 거기서 되읽는다. 형식이 다르거나 말이 안 되는 값이면 **추측하지 않고
  /// null을 준다** — 모르는 것을 아는 척하면 그게 곧 가짜 근거가 된다.
  static DateTime? registeredAtOf(ContactModel contact, DateTime now) {
    final millis = int.tryParse(contact.id);
    if (millis == null) return null;
    // 2010-01-01 이전이거나 미래면 id가 시각이 아니라는 뜻이다.
    const earliest = 1262304000000; // 2010-01-01
    if (millis < earliest) return null;
    final parsed = DateTime.fromMillisecondsSinceEpoch(millis);
    if (parsed.isAfter(now)) return null;
    return parsed;
  }

  /// "며칠째 연락이 없나". 소통 기록이 있으면 그 시점부터, 없으면 등록
  /// 시점부터 센다. 둘 다 모르면 null(= 기간을 말할 수 없음).
  static int? _neglectedDaysOf(
    ContactModel contact,
    DateTime? lastContactAt,
    DateTime now,
  ) {
    final since = lastContactAt ?? registeredAtOf(contact, now);
    if (since == null) return null;
    final days = now.difference(since).inDays;
    return days < 0 ? 0 : days;
  }

  // ---------------------------------------------------------------------
  // 점수
  // ---------------------------------------------------------------------

  /// 점수 = 방치도 + 근거강도 + C 후속 신호.
  ///
  /// 스펙의 "중요표시 가중"은 1차에서 제외한다 — `isPriority`가 지금 거의 모든
  /// 명함에서 true(기본값)라 가중치로서 아무것도 구분하지 못한다.
  static double _scoreOf({
    required ContactModel contact,
    required int? neglectedDays,
    required bool followUpDue,
  }) {
    var score = 0.0;

    // 방치도 — 개월 단위로 환산하고 1년에서 멈춘다. 3년 전 사람이 6개월 전
    // 사람보다 무조건 위로 오면, 사실상 다시는 연락 안 할 사람만 계속 뜬다.
    if (neglectedDays != null) {
      final months = neglectedDays / 30.0;
      score += months.clamp(0.0, 12.0);
    }

    // 근거강도 — 할 말이 있는 사람이 위로 온다. 연락할 구실이 있는 쪽이
    // 실제로 연락으로 이어진다.
    if ((contact.memo ?? '').trim().isNotEmpty) score += 2;
    if (contact.commLogs.isNotEmpty) score += 2;

    // C 후속 신호
    if (followUpDue) {
      // 사용자가 직접 정한 날짜다. 다른 무엇보다 위에 온다.
      score += 20;
    }
    if (contact.lastReconnectOutcome == 'good') score += 3;

    // 반응 "없음"이 반복되면 덜 자주 띄운다. 지우지는 않는다 — 상황이
    // 바뀔 수 있고, 앱이 사람을 대신 포기하는 것은 월권이다.
    score -= contact.reconnectNoResponseStreak * 4;

    return score;
  }

  // ---------------------------------------------------------------------
  // 이유 — 여기서만 만든다
  // ---------------------------------------------------------------------

  static ReconnectReason _buildReason({
    required ContactModel contact,
    required DateTime now,
    required DateTime? lastContactAt,
    required int? neglectedDays,
    required bool followUpDue,
  }) {
    final memoExcerpt = _memoExcerptOf(contact);
    final outcome = contact.lastReconnectOutcome;
    final outcomeAt = contact.lastReconnectOutcomeAt;

    // ① 사용자가 정한 재연락 시점이 됐다 — 가장 강한 근거.
    if (followUpDue && outcome == 'good' && outcomeAt != null) {
      final ago = _agoTextOf(outcomeAt, now);
      final channel = _channelLabelNear(contact, outcomeAt);
      final head = channel == null ? '$ago 연락' : '$ago $channel';
      return ReconnectReason._(
        kind: ReconnectReasonKind.followUpDue,
        text: _joinWithMemo('$head 반응이 좋았어요 · 다시 연락할 때', memoExcerpt),
        memoExcerpt: memoExcerpt,
      );
    }
    if (followUpDue) {
      return ReconnectReason._(
        kind: ReconnectReasonKind.followUpDue,
        text: _joinWithMemo('다시 연락하기로 한 때', memoExcerpt),
        memoExcerpt: memoExcerpt,
      );
    }

    // ② 직전 반응이 좋았다.
    if (outcome == 'good' && outcomeAt != null) {
      final ago = _agoTextOf(outcomeAt, now);
      final channel = _channelLabelNear(contact, outcomeAt);
      final head = channel == null ? '$ago 연락' : '$ago $channel';
      return ReconnectReason._(
        kind: ReconnectReasonKind.goodOutcome,
        text: _joinWithMemo('$head 반응이 좋았어요', memoExcerpt),
        memoExcerpt: memoExcerpt,
      );
    }

    // ③ 소통 기록이 있다.
    if (lastContactAt != null) {
      final ago = _agoTextOf(lastContactAt, now);
      final channel = _channelLabelNear(contact, lastContactAt);
      final head = channel == null ? '$ago 연락' : '$ago $channel';
      return ReconnectReason._(
        kind: memoExcerpt == null
            ? ReconnectReasonKind.logged
            : ReconnectReasonKind.loggedWithMemo,
        text: _joinWithMemo(head, memoExcerpt),
        memoExcerpt: memoExcerpt,
      );
    }

    // ④ 기록은 없지만 메모가 있다.
    if (memoExcerpt != null) {
      final head = neglectedDays == null
          ? '연락 기록 없음'
          : '${_durationTextOf(neglectedDays)}째 연락 없음';
      return ReconnectReason._(
        kind: ReconnectReasonKind.memoOnly,
        text: _joinWithMemo(head, memoExcerpt),
        memoExcerpt: memoExcerpt,
      );
    }

    // ⑤ 방치 기간만 안다.
    if (neglectedDays != null) {
      return ReconnectReason._(
        kind: ReconnectReasonKind.neglectedOnly,
        text: '${_durationTextOf(neglectedDays)}째 연락 없음',
      );
    }

    // ⑥ 아무것도 모른다. **여기서 이야기를 지어내지 않는다.**
    return const ReconnectReason._(
      kind: ReconnectReasonKind.noHistory,
      text: '한 번도 연락 기록 없음',
    );
  }

  /// 메모에서 따올 조각. **원본의 부분 문자열만** 낸다.
  static String? _memoExcerptOf(ContactModel contact) {
    final memo = (contact.memo ?? '').replaceAll('\n', ' ').trim();
    if (memo.isEmpty) return null;
    if (memo.length <= memoExcerptMaxLength) return memo;
    return memo.substring(0, memoExcerptMaxLength);
  }

  static String _joinWithMemo(String head, String? memoExcerpt) =>
      memoExcerpt == null ? head : '$head · 메모: "$memoExcerpt"';

  /// [at] 무렵에 실제로 있었던 소통 기록의 채널 이름.
  ///
  /// 하루 안에 있는 기록만 인정한다. "통화"라고 썼는데 실제로는 문자였으면
  /// 그것도 거짓말이므로, 확실하지 않으면 채널을 말하지 않는다(null).
  static String? _channelLabelNear(ContactModel contact, DateTime at) {
    CommunicationLogModel? nearest;
    var nearestGap = const Duration(days: 1);
    for (final log in contact.commLogs) {
      final gap = log.timestamp.difference(at).abs();
      if (gap <= nearestGap) {
        nearest = log;
        nearestGap = gap;
      }
    }
    return switch (nearest?.type) {
      'call' => '통화',
      'sms' => '문자',
      'email' => '이메일',
      'kakao' => '카톡',
      _ => null,
    };
  }

  /// "3일 전" / "2주 전" / "5개월 전".
  static String _agoTextOf(DateTime at, DateTime now) {
    final days = now.difference(at).inDays;
    return '${_durationTextOf(days < 0 ? 0 : days)} 전';
  }

  /// 기간을 사람이 읽는 단위로. 오늘이면 '오늘'.
  static String _durationTextOf(int days) {
    if (days <= 0) return '오늘';
    if (days < 14) return '$days일';
    if (days < 60) return '${days ~/ 7}주';
    return '${days ~/ 30}개월';
  }

  // ---------------------------------------------------------------------
  // C — 연락 후 후속을 명함에 반영
  // ---------------------------------------------------------------------

  /// 사용자가 C에서 고른 값을 명함에 반영한 새 [ContactModel]을 만든다.
  ///
  /// [followUpAfter]가 null이면 "안 정함" — 다음 시점을 비운다(억지로 날짜를
  /// 만들어 넣지 않는다).
  static ContactModel applyOutcome({
    required ContactModel contact,
    required ReconnectOutcome outcome,
    required DateTime now,
    Duration? followUpAfter,
  }) {
    // 반응 "없음"이 이어지면 A에서 덜 자주 뜨게 한다. 다른 반응이 한 번이라도
    // 나오면 0으로 되돌린다 — 한 번 안 받았다고 영영 밀려나면 안 된다.
    final streak = outcome == ReconnectOutcome.none
        ? contact.reconnectNoResponseStreak + 1
        : 0;

    return contact.copyWith(
      lastReconnectOutcome: outcome.code,
      lastReconnectOutcomeAt: now,
      nextFollowUpAt: followUpAfter == null ? null : now.add(followUpAfter),
      reconnectNoResponseStreak: streak,
      clearNextFollowUpAt: followUpAfter == null,
      // 후속을 남겼으면 스누즈는 의미가 없다. 남아 있으면 사용자가 정한
      // 재연락 시점이 와도 스누즈에 막힌다.
      clearReconnectSnoozedUntil: true,
      updatedAt: now,
    );
  }

  /// "이번엔 넘김" — [snoozeDays]일 뒤에 다시 후보가 된다.
  static ContactModel applySnooze({
    required ContactModel contact,
    required DateTime now,
  }) {
    return contact.copyWith(
      reconnectSnoozedUntil: now.add(const Duration(days: snoozeDays)),
      updatedAt: now,
    );
  }
}
