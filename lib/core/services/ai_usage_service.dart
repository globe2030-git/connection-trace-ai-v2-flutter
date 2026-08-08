import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'ai_briefing_service.dart';

/// AI 브리핑을 오늘/이번 달 몇 번 더 쓸 수 있는지.
class AiUsage {
  final int dailyUsed;
  final int monthlyUsed;

  const AiUsage({required this.dailyUsed, required this.monthlyUsed});

  int get dailyRemaining =>
      (AiBriefingService.dailyLimit - dailyUsed).clamp(0, AiBriefingService.dailyLimit);
  int get monthlyRemaining =>
      (AiBriefingService.monthlyLimit - monthlyUsed).clamp(0, AiBriefingService.monthlyLimit);

  /// 오늘 한도와 이번 달 한도 중 **먼저 걸리는 쪽**. 사용자에게는 "몇 번 더
  /// 쓸 수 있는가" 하나만 보여주는 게 이해하기 쉽다.
  int get remaining =>
      dailyRemaining < monthlyRemaining ? dailyRemaining : monthlyRemaining;

  bool get isMonthlyBinding => monthlyRemaining < dailyRemaining;
  bool get exhausted => remaining <= 0;
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
      if (usage == null) {
        // 아직 한 번도 안 썼으면 문서에 필드가 없다 — 0회로 본다.
        return const AiUsage(dailyUsed: 0, monthlyUsed: 0);
      }
      return AiUsage(
        dailyUsed: _countIfNotExpired(usage, 'dailyCount', 'dailyResetAt'),
        monthlyUsed: _countIfNotExpired(usage, 'monthlyCount', 'monthlyResetAt'),
      );
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
