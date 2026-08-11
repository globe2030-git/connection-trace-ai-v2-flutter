import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ai_briefing_service.dart';

/// AI 브리핑을 오늘/이번 달 몇 번 더 쓸 수 있는지.
class AiUsage {
  final int dailyUsed;
  final int monthlyUsed;

  /// 관리자가 `grantBonusCredits`로 지급한 보너스 회차. 일/월 무료 한도를
  /// 다 쓴 뒤에만 소진되는 오버플로우라 만료가 없다(리셋 대상 아님).
  final int bonusCredits;

  const AiUsage({
    required this.dailyUsed,
    required this.monthlyUsed,
    this.bonusCredits = 0,
  });

  int get dailyRemaining =>
      (AiBriefingService.dailyLimit - dailyUsed).clamp(0, AiBriefingService.dailyLimit);
  int get monthlyRemaining =>
      (AiBriefingService.monthlyLimit - monthlyUsed).clamp(0, AiBriefingService.monthlyLimit);

  /// 오늘 한도와 이번 달 한도 중 **먼저 걸리는 쪽**(무료분만, 보너스 제외).
  /// 하위 호환을 위해 이름은 유지한다 — 다른 화면이 여전히 이 값을 쓴다.
  int get remaining =>
      dailyRemaining < monthlyRemaining ? dailyRemaining : monthlyRemaining;

  /// "앞으로 더 쓸 수 있는 진짜 총 횟수" = 무료 잔여 + 보너스.
  int get totalRemaining => remaining + bonusCredits;

  bool get isMonthlyBinding => monthlyRemaining < dailyRemaining;

  /// 무료분과 보너스를 모두 소진했을 때만 참이다 — 보너스가 남아 있으면
  /// 무료 한도를 다 썼어도 서버는 요청을 허용한다.
  bool get exhausted => totalRemaining <= 0;

  /// 잔여가 얼마 남지 않았음(0은 이미 [exhausted]가 커버).
  bool get lowBalance => totalRemaining > 0 && totalRemaining < 5;
}

/// 서버가 기록한 AI 호출량을 읽어 온다.
///
/// **왜 서버 값을 읽나**: 한도는 서버(`functions/src/index.ts`)가 Firestore
/// 트랜잭션으로 세고 판정한다. 앱이 따로 세면 기기를 바꾸거나 재설치했을 때
/// 실제와 어긋나고, 사용자는 "분명 남았는데 안 된다"를 겪는다. 유일한 진실은
/// 서버 카운터다.
///
/// 읽기는 `firestore.rules`에서 본인 문서에 허용돼 있다(`allow read: if
/// isOwner(uid)`). 쓰기는 막혀 있어 앱이 카운터를 조작할 수는 없다(P0-8).
class AiUsageService {
  /// 마지막으로 성공적으로 읽은 사용량. 여러 화면(홈·설정·AI 브리핑)의 잔여
  /// 횟수 칩이 이걸 구독한다 — 한 곳에서 AI를 써서 [fetch]로 다시 읽으면 모든
  /// 칩이 같이 갱신된다. 읽기 실패(null 반환) 시에는 마지막 값을 지우지 않고
  /// 그대로 둔다(깜빡임 방지).
  static final ValueNotifier<AiUsage?> latest = ValueNotifier<AiUsage?>(null);

  /// 실패하면 null. 사용량 표시는 부가 정보라, 못 읽었다고 해서 AI 사용
  /// 자체를 막지는 않는다 — 최종 판정은 어차피 서버가 한다.
  static Future<AiUsage?> fetch() async {
    try {
      // ⚠️ `FirebaseAuth.instance` 접근 자체가 던질 수 있다 — Firebase가
      // 초기화되지 않았으면 `[core/no-app]`이 나온다. 그래서 uid를 읽는 것부터
      // try 안에 둔다. 위젯 테스트에서 이 예외로 화면이 통째로 깨졌고(실제로
      // 겪음), 같은 일이 Firebase 초기화가 실패한 기기에서도 일어난다.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final usage = snap.data()?['aiUsage'] as Map<String, dynamic>?;
      final result = usage == null
          // 아직 한 번도 안 썼으면 문서에 필드가 없다 — 0회로 본다.
          ? const AiUsage(dailyUsed: 0, monthlyUsed: 0, bonusCredits: 0)
          : AiUsage(
              dailyUsed: _countIfNotExpired(usage, 'dailyCount', 'dailyResetAt'),
              monthlyUsed:
                  _countIfNotExpired(usage, 'monthlyCount', 'monthlyResetAt'),
              // 보너스는 리셋 로직 대상이 아니다 — 만료 없이 그대로 읽는다.
              bonusCredits: (usage['bonusCredits'] as num?)?.toInt() ?? 0,
            );
      latest.value = result; // 구독 중인 칩들에 방송.
      return result;
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('AI 사용량 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 서버는 리셋 시각이 지나도 카운터를 즉시 0으로 만들지 않는다 — 다음 호출
  /// 때 만료를 확인하고 0부터 다시 센다(`incrementAndCheckUsage` 참고).
  /// 그래서 화면도 같은 규칙으로 읽어야 "자정이 지났는데 0으로 안 돌아온다"는
  /// 오해가 생기지 않는다.
  static int _countIfNotExpired(
    Map<String, dynamic> usage,
    String countKey,
    String resetKey,
  ) {
    final resetAt = (usage[resetKey] as Timestamp?)?.toDate();
    if (resetAt == null || !resetAt.isAfter(DateTime.now())) return 0;
    return (usage[countKey] as num?)?.toInt() ?? 0;
  }
}
