/// AI 충전 상품 설정 — 관리자 콘솔(`docs/admin/admin.js`)에서 편집하고
/// Firestore `config/billing` 문서로 저장한다(스키마는 관리자 콘솔이 이미
/// 확정해 둔 것을 그대로 읽기만 한다 — 앱에서 새 필드를 만들지 않는다).
///
/// [AppUpdateStatus](../../core/services/app_update_service.dart)와 같은
/// 패턴: 불변 데이터 클래스 + `fromMap`에서 안전한 형변환(누락·오타입은
/// 조용히 0/false로 폴백, 예외를 던지지 않는다).
class BillingTier {
  /// 원화 가격. 어떤 가격 단계가 존재하는지는 관리자 콘솔 `TIER_PRICES`가
  /// 정하고(2026-08-11 현재 1천~10만원 7단계), 앱은 Firestore에 저장된
  /// 티어를 그대로 읽어 그린다 — 단계가 바뀌어도 앱 수정이 필요 없다.
  final int priceKrw;

  /// 이 가격에 제공되는 AI 사용 횟수. 관리자가 "회수 미정" 상태로 두면
  /// Firestore에는 `credits: null`로 저장된다 — 그 경우 여기선 0으로
  /// 폴백하되, [BillingConfigRepository]가 그런 티어는 애초에 걸러낸다.
  final int credits;

  /// 관리자 콘솔에서 판매 중으로 켠 티어인지.
  final bool active;

  const BillingTier({
    required this.priceKrw,
    required this.credits,
    required this.active,
  });

  factory BillingTier.fromMap(Map<String, dynamic> map) {
    return BillingTier(
      priceKrw: (map['priceKrw'] as num?)?.toInt() ?? 0,
      credits: (map['credits'] as num?)?.toInt() ?? 0,
      active: (map['active'] as bool?) ?? false,
    );
  }
}

/// `config/billing.model`이 가질 수 있는 값. 서버(`functions/src/
/// walletCredits.ts`의 `resolveBillingModel`)와 이름·기본값을 맞춘다 —
/// 문서가 없거나 값이 알 수 없으면 항상 [reset]으로 폴백한다(안전한 쪽,
/// wallet로 잘못 폴백하면 조용히 무제한 과금 모델이 될 위험이 있다).
enum BillingModel {
  /// 지금까지의 일/월 한도 + 리셋 방식(기본값).
  reset,

  /// 2026-08-14 도입, 무료체험 잔액 + 충전 잔액을 합산해 소진하는 방식.
  /// 리셋 개념이 없다.
  wallet;

  static BillingModel fromRaw(dynamic raw) {
    return raw == 'wallet' ? BillingModel.wallet : BillingModel.reset;
  }
}

/// `config/billing` 문서 전체.
class BillingConfig {
  /// 신규 가입 시 무료로 제공하는 AI 사용 횟수.
  final int freeCredits;

  /// 판매 중인 충전 티어 목록. [BillingConfigRepository]가 이미
  /// active·credits 유효성으로 걸러 가격 오름차순으로 정렬해 돌려준다.
  final List<BillingTier> tiers;

  /// 서버가 사용량을 판정하는 방식. 앱은 이 값으로 사용량 표시 화면을
  /// 분기한다([AiUsage] 참고) — 아직 어떤 계정도 실제로 wallet이 아니므로
  /// (2026-08-14 기준) 대부분의 환경에서는 [BillingModel.reset]이다.
  final BillingModel model;

  const BillingConfig({
    required this.freeCredits,
    required this.tiers,
    this.model = BillingModel.reset,
  });

  factory BillingConfig.fromMap(Map<String, dynamic> map) {
    final rawTiers = map['tiers'];
    final tiers = <BillingTier>[];
    if (rawTiers is List) {
      for (final entry in rawTiers) {
        if (entry is Map) {
          tiers.add(BillingTier.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    }
    return BillingConfig(
      freeCredits: (map['freeCredits'] as num?)?.toInt() ?? 0,
      tiers: tiers,
      model: BillingModel.fromRaw(map['model']),
    );
  }
}
