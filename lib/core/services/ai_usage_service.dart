import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/billing_config_model.dart';
import '../../data/repositories/billing_config_repository.dart';
import 'ai_briefing_service.dart';

/// AI 브리핑을 오늘/이번 달 몇 번 더 쓸 수 있는지.
///
/// **모드가 둘 있다**(2026-08-14, wallet 전환 U4, ai-credit-wallet-spec.md
/// §5): `config/billing.model`이 `'wallet'`이면 [isWalletMode]가 참이 되고,
/// 잔여 계산이 일/월 리셋이 아니라 `freeBalance + paidBalance` 합산으로
/// 바뀐다. 아직 어떤 계정도 실제로 wallet이 아니므로(2026-08-14 기준) 지금
/// 실사용 경로는 전부 reset 모드다 — **reset 모드 계산식은 한 글자도
/// 바뀌지 않았다.** 공개 API(`totalRemaining`/`exhausted`/`lowBalance`)
/// 이름은 두 모드에서 동일하게 유지해 화면 위젯 수정을 최소화한다.
class AiUsage {
  final int dailyUsed;
  final int monthlyUsed;

  /// 관리자가 `grantSupportCredits`로 지급한 보너스 회차. 일/월 무료 한도를
  /// 다 쓴 뒤에만 소진되는 오버플로우라 만료가 없다(리셋 대상 아님).
  /// reset 모드에서만 의미가 있다.
  final int bonusCredits;

  /// wallet 모드에서 남은 무료체험 잔액. reset 모드에서는 0(미사용).
  final int freeBalance;

  /// wallet 모드에서 남은 충전 잔액. reset 모드에서는 0(미사용).
  final int paidBalance;

  /// `config/billing.model == 'wallet'`이면 참. [BillingConfigRepository]가
  /// 이미 문서 없음/알 수 없는 값을 `reset`으로 폴백하므로 이 필드도 같은
  /// 규칙을 따른다(기본값 false = reset).
  final bool isWalletMode;

  const AiUsage({
    required this.dailyUsed,
    required this.monthlyUsed,
    this.bonusCredits = 0,
    this.freeBalance = 0,
    this.paidBalance = 0,
    this.isWalletMode = false,
  });

  int get dailyRemaining =>
      (AiBriefingService.dailyLimit - dailyUsed).clamp(0, AiBriefingService.dailyLimit);
  int get monthlyRemaining =>
      (AiBriefingService.monthlyLimit - monthlyUsed).clamp(0, AiBriefingService.monthlyLimit);

  /// 오늘 한도와 이번 달 한도 중 **먼저 걸리는 쪽**(무료분만, 보너스 제외).
  /// reset 모드 전용 값이다 — wallet 모드에는 일/월 한도 개념이 없어서
  /// 이 값을 그대로 두되(하위 호환), [totalRemaining]에는 쓰지 않는다.
  int get remaining =>
      dailyRemaining < monthlyRemaining ? dailyRemaining : monthlyRemaining;

  /// wallet 모드: 무료체험 잔액 + 충전 잔액(합산, 두 버킷을 화면에 분리
  /// 노출하지 않는다 — 스펙 §5).
  /// reset 모드: 무료 잔여 + 보너스(기존 로직 그대로).
  int get totalRemaining =>
      isWalletMode ? freeBalance + paidBalance : remaining + bonusCredits;

  bool get isMonthlyBinding => monthlyRemaining < dailyRemaining;

  /// wallet 모드: 합산 잔액이 0 이하.
  /// reset 모드: 무료분과 보너스를 모두 소진했을 때만 참이다 — 보너스가
  /// 남아 있으면 무료 한도를 다 썼어도 서버는 요청을 허용한다.
  bool get exhausted => totalRemaining <= 0;

  /// 잔여가 얼마 남지 않았음(0은 이미 [exhausted]가 커버). 두 모드 모두
  /// 같은 기준(5회 미만, 확정 파라미터)을 쓴다.
  bool get lowBalance => totalRemaining > 0 && totalRemaining < 5;
}

/// 관리자가 **다른 사용자**의 사용량을 조회한 결과(`getUserUsage` 응답).
///
/// 본인용 [AiUsage]와 따로 두는 이유: 한도(`dailyLimit`)를 앱 상수가 아니라
/// **서버가 준 값**으로 보여줘야 한다. 앱 상수는 배포 시점에 굳어서, 서버에서
/// 한도를 바꾸면 관리자 화면만 옛 숫자를 말하게 된다.
class AdminUserUsage {
  final String uid;
  final String? email;
  final int dailyCount;
  final int dailyLimit;
  final int monthlyCount;
  final int monthlyLimit;
  final int bonusCredits;

  const AdminUserUsage({
    required this.uid,
    required this.email,
    required this.dailyCount,
    required this.dailyLimit,
    required this.monthlyCount,
    required this.monthlyLimit,
    required this.bonusCredits,
  });
}

/// 관리자 조회가 실패한 이유. 화면이 "0회"와 "못 읽었음"을 구분해서 보여줘야
/// 하기 때문에 남긴다 — 예전 구현은 실패를 삼키고 0을 그렸고, 그래서 관리자가
/// "이 고객은 크레딧이 0"이라고 오해할 수 있었다(backlog 추가 178).
enum AdminUsageError {
  /// 관리자 계정이 아니다(서버가 거부).
  notAdmin,

  /// 그 이메일로 가입한 계정이 없다 — 탈퇴했거나, SNS 이메일이 문의 당시와
  /// 다른 경우다(애플 "이메일 가리기"가 대표적).
  accountNotFound,

  /// 문의에 이메일이 없다. 조회 키가 없으니 시도조차 못 한다.
  noEmail,

  /// 지급 회차·사유가 서버 검사에 걸렸다. **관리자가 고쳐서 다시 할 수 있는**
  /// 종류라 다른 실패와 갈라 둔다(한도 초과, 사유 누락 등).
  invalidGrant,

  /// 네트워크·서버 오류 등 그 밖의 실패.
  unknown,
}

class AdminUsageException implements Exception {
  final AdminUsageError reason;

  /// 서버가 준 문구. **회차 지급이 검사에 걸렸을 때만** 채운다 — 한도·사유
  /// 같은 것은 서버가 이유를 정확히 아는데, 앱이 다시 쓰면 **두 벌이 되어
  /// 어긋난다**(서버 한도를 바꿔도 앱 문구는 그대로 남는다).
  final String? serverMessage;

  const AdminUsageException(this.reason, {String? message})
    : serverMessage = message;

  /// 관리자에게 그대로 보여줄 안내. 개인정보는 담지 않는다.
  String get message => switch (reason) {
    AdminUsageError.notAdmin => '관리자 계정에서만 조회할 수 있습니다.',
    AdminUsageError.accountNotFound => '가입된 계정을 찾을 수 없습니다(탈퇴했거나 로그인 이메일이 다릅니다).',
    AdminUsageError.noEmail => '문의에 이메일이 없어 조회할 수 없습니다.',
    AdminUsageError.invalidGrant =>
      serverMessage ?? '지급할 회차나 사유를 다시 확인해 주세요.',
    AdminUsageError.unknown => '사용량을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
  };
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
      final isWalletMode = await _fetchIsWalletMode();
      final usage = snap.data()?['aiUsage'] as Map<String, dynamic>?;
      final result = usage == null
          // 아직 한 번도 안 썼으면 문서에 필드가 없다 — 0회로 본다.
          ? AiUsage(dailyUsed: 0, monthlyUsed: 0, isWalletMode: isWalletMode)
          : AiUsage(
              dailyUsed: _countIfNotExpired(usage, 'dailyCount', 'dailyResetAt'),
              monthlyUsed:
                  _countIfNotExpired(usage, 'monthlyCount', 'monthlyResetAt'),
              // 보너스는 리셋 로직 대상이 아니다 — 만료 없이 그대로 읽는다.
              bonusCredits: (usage['bonusCredits'] as num?)?.toInt() ?? 0,
              // wallet 모드 잔액도 만료가 없다 — 그대로 읽는다(reset 모드
              // 계정에는 이 필드가 아예 없으므로 0으로 폴백해도 무해하다).
              freeBalance: (usage['freeBalance'] as num?)?.toInt() ?? 0,
              paidBalance: (usage['paidBalance'] as num?)?.toInt() ?? 0,
              isWalletMode: isWalletMode,
            );
      latest.value = result; // 구독 중인 칩들에 방송.
      return result;
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('AI 사용량 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 관리자가 **다른 사용자**의 사용량을 이메일로 조회한다(1:1 문의 응대용).
  ///
  /// **왜 서버 함수를 부르나**: `users/{uid}` 문서는 `firestore.rules`에서
  /// 본인만 읽을 수 있다(`allow read: if isOwner(uid)`). 관리자에게 이 문서를
  /// 열어 주면 안 되는데, 같은 문서에 **명함 복호화용 키(`encryptionKeyB64`)**가
  /// 들어 있어서 관리자가 모든 고객의 명함을 복호화할 수 있게 되기 때문이다.
  /// 그래서 서버(`getUserUsage`)가 Admin SDK로 읽어 **사용량만** 돌려준다.
  ///
  /// 실패는 [AdminUsageException]으로 던진다 — 화면이 "0회"와 "못 읽었음"을
  /// 반드시 구분해야 하기 때문이다(backlog 추가 178).
  static Future<AdminUserUsage> fetchForAdmin(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const AdminUsageException(AdminUsageError.noEmail);
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: AiBriefingService.region,
      ).httpsCallable('getUserUsage');
      final result = await callable.call<Map<String, dynamic>>({
        'email': trimmed,
      });
      final d = result.data;
      return AdminUserUsage(
        uid: (d['uid'] as String?) ?? '',
        email: d['email'] as String?,
        dailyCount: (d['dailyCount'] as num?)?.toInt() ?? 0,
        dailyLimit: (d['dailyLimit'] as num?)?.toInt() ?? 0,
        monthlyCount: (d['monthlyCount'] as num?)?.toInt() ?? 0,
        monthlyLimit: (d['monthlyLimit'] as num?)?.toInt() ?? 0,
        bonusCredits: (d['bonusCredits'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      // 서버가 주는 코드별로 관리자가 할 수 있는 일이 다르다. 뭉뚱그리면
      // "탈퇴한 계정"과 "권한 없음"이 같은 문구로 보여 응대가 막힌다.
      throw AdminUsageException(switch (e.code) {
        'permission-denied' => AdminUsageError.notAdmin,
        'not-found' => AdminUsageError.accountNotFound,
        'invalid-argument' => AdminUsageError.noEmail,
        _ => AdminUsageError.unknown,
      });
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('관리자 사용량 조회 실패: ${e.runtimeType}');
      throw const AdminUsageException(AdminUsageError.unknown);
    }
  }

  /// 관리자가 **보너스 회차를 지급(또는 회수)한다**(추가 338).
  ///
  /// ## 왜 앱에서 부르나
  ///
  /// 서버 함수(`grantSupportCredits`)는 예전부터 있었는데 **부르는 쪽이
  /// 없었다.** 그래서 문의에 답하다 보상을 주려면 Firebase 콘솔을 직접 열어야
  /// 했다. 이 저장소가 이미 겪은 모양이다 — *"재시도 로직이 죽어 있음 / 서비스는
  /// 정상, 부르는 쪽이 없음"*(CLAUDE.md 4절 표).
  ///
  /// ## ⚠️ [operationId]는 **호출부가 만들어 붙든다**
  ///
  /// 서버가 이 값으로 **멱등성**을 지킨다 — 같은 값으로 두 번 오면 다시
  /// 적용하지 않고 그때 잔액을 돌려준다. 그러므로 **재시도할 때는 같은 값**을,
  /// 새 지급이면 **새 값**을 보내야 한다. 여기서 만들면 재시도마다 새 값이
  /// 생겨 **중복 지급**이 된다.
  ///
  /// ## 서버가 막는 것
  ///
  /// ```
  /// 1회 지급/회수   ±100회 이내
  /// 지급 후 잔액    100,000회 이내
  /// 사유(reason)    비울 수 없다 — 감사 기록에 남는다
  /// ```
  ///
  /// 음수를 보내면 **회수**다. 잔액은 서버가 0 미만으로 안 내려가게 막는다.
  ///
  /// 성공하면 **지급 후 잔액**을 돌려준다.
  static Future<int> grantBonusCredits({
    required String email,
    required int amount,
    required String reason,
    required String operationId,
  }) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const AdminUsageException(AdminUsageError.noEmail);
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: AiBriefingService.region,
      ).httpsCallable('grantSupportCredits');
      final result = await callable.call<Map<String, dynamic>>({
        'email': trimmed,
        'amount': amount,
        'reason': reason.trim(),
        'operationId': operationId,
      });
      return (result.data['bonusCredits'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (e) {
      // 조회와 **같은 갈래**를 쓴다 — 화면이 두 벌의 문구를 갖지 않도록.
      throw AdminUsageException(switch (e.code) {
        'permission-denied' => AdminUsageError.notAdmin,
        'not-found' => AdminUsageError.accountNotFound,
        // 서버가 사유·회차 한도를 여기로 돌려준다. 관리자가 고쳐서 다시 할 수
        // 있는 종류라, 서버 문구를 그대로 보여 주는 것이 낫다.
        'invalid-argument' => AdminUsageError.invalidGrant,
        _ => AdminUsageError.unknown,
      }, message: e.message);
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다.
      debugPrint('관리자 회차 지급 실패: ${e.runtimeType}');
      throw const AdminUsageException(AdminUsageError.unknown);
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

  /// `config/billing.model`을 읽어 wallet 모드인지 판정한다. 서버의
  /// `resolveBillingModel`과 같은 안전 규칙을 따른다 — 문서가 없거나 읽기
  /// 자체가 실패해도 항상 reset(false)으로 폴백한다. 이 실패가 [fetch]
  /// 전체를 막지 않도록 별도 try/catch로 감싼다.
  static Future<bool> _fetchIsWalletMode() async {
    try {
      final config = await BillingConfigRepository().fetchConfig();
      return config?.model == BillingModel.wallet;
    } catch (e) {
      debugPrint('billing 모델 조회 실패: ${e.runtimeType}');
      return false;
    }
  }
}
