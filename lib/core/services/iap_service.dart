import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// IAP(인앱결제) 기본 배선 — **U7 "뼈대만" 라운드 산출물이다.**
///
/// 이 서비스로는 실제 구매가 일어나지 않는다. [kIapEnabled]가 `false`로
/// 고정돼 있는 한:
/// - [queryProducts]는 스토어를 조회하지 않고 빈 응답을 반환한다.
/// - [buyConsumable]은 스토어 구매 시트를 열지 않고 즉시
///   [IapNotReadyException]을 던진다.
/// - 이 서비스를 호출하는 화면 쪽 진입점(`ai_charge_view.dart`)도 이번
///   라운드엔 아직 어디서도 [buyConsumable]을 부르지 않는다 — 즉 구매
///   버튼 자체가 계속 비활성 상태다.
///
/// **이중 안전장치**: 설령 나중에 실수로 `kIapEnabled`를 true로 바꾸고
/// 구매 버튼까지 열어도, 서버 `verifyAndGrantPurchase`
/// (`functions/src/index.ts`)가 아직 실제 영수증 검증을 구현하지 않아
/// 항상 `unimplemented`를 던지므로 크레딧이 지급되지 않는다. 클라이언트
/// 플래그 하나에만 기대지 않는다.
///
/// 설계 근거: docs/planning/monetization-referral-engineering-spec
/// -2026-08-14.md §2-4(결제 계층), §6(U7 착수 단위).
class IapService {
  /// 결제 기능 전체를 여는/닫는 단일 스위치. 스토어 상품ID 등록(P1-1,
  /// 사용자 게이트)과 서버 영수증 검증 구현이 모두 끝난 뒤에만 `true`로
  /// 바꾼다 — 그 전에 바꾸면 스토어 구매 시트는 열리는데 서버가
  /// `unimplemented`로 거부해 "결제했는데 크레딧이 안 들어왔다"는 사고로
  /// 이어진다.
  static const bool kIapEnabled = false;

  static const String _region = 'asia-northeast3';

  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  IapService({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  /// 구매 스트림 구독을 시작한다. `kIapEnabled`가 false인 동안에도 구독
  /// 배선 자체는 걸어 둔다(앱 시작 중 스토어가 미완료 트랜잭션을 재전달할
  /// 수 있기 때문 — 표준 in_app_purchase 초기화 패턴). 다만 구매 버튼이
  /// 열려 있지 않으므로 실제로는 이벤트가 들어올 일이 없다.
  void start() {
    _subscription?.cancel();
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdate,
      onError: (Object e) {
        debugPrint('IAP purchaseStream 오류: ${e.runtimeType}');
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// 스토어 상품 정보를 조회한다.
  ///
  /// [productIds]는 이 서비스가 하드코딩하지 않는다 — 호출부가
  /// `config/billing.tiers`(관리자 콘솔이 관리)에서 읽은 실제 productId
  /// 목록을 넘겨야 한다. 스토어 등록 전에는 그 목록이 비어 있거나
  /// placeholder뿐이므로, 실제로 스토어에 조회가 나가도 상품을 찾지
  /// 못하는 게 정상이다.
  ///
  /// `kIapEnabled`가 false면 스토어에 아예 요청을 보내지 않고 빈 응답을
  /// 반환한다.
  Future<ProductDetailsResponse> queryProducts(Set<String> productIds) async {
    if (!kIapEnabled || productIds.isEmpty) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: productIds.toList(),
      );
    }
    return _iap.queryProductDetails(productIds);
  }

  /// 소모성(consumable) 상품 구매를 시도한다.
  ///
  /// `kIapEnabled`가 true가 되기 전까지는 스토어 구매 시트를 절대 열지
  /// 않는다 — 조용히 아무 일도 안 하는 대신 명시적 예외를 던져서, 혹시
  /// 나중에 실수로 이 메서드를 호출하는 코드가 생겨도 "반응 없음"이
  /// 아니라 "왜 안 되는지"가 바로 드러나게 한다.
  Future<void> buyConsumable(ProductDetails product) async {
    if (!kIapEnabled) {
      throw const IapNotReadyException();
    }
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  /// 구매 갱신 콜백. 실제로는 [start]로 건 구독에서만 불리는데, 구매
  /// 버튼이 열려 있지 않은 이번 라운드엔 스토어가 이 스트림으로 새 구매
  /// 이벤트를 보낼 일이 없다 — 그래도 콜백 자체는 미리 만들어 둔다.
  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyAndGrant(purchase);
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// 서버 `verifyAndGrantPurchase` 콜러블(`functions/src/index.ts`)을
  /// 호출하는 자리까지만 만든다. 서버가 아직 실제 영수증 검증을
  /// 구현하지 않아 이 호출은 지금 항상 `unimplemented` 에러로 끝난다 —
  /// 그래도 배선(요청 형태, 필드명)은 미리 맞춰 둔다.
  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: _region,
      ).httpsCallable('verifyAndGrantPurchase');
      await callable.call<Map<String, dynamic>>({
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
        'productId': purchase.productID,
        'transactionId': purchase.purchaseID ?? '',
        'receiptData': purchase.verificationData.serverVerificationData,
      });
    } catch (e) {
      // 개인정보가 섞이지 않도록 예외 타입만 남긴다(다른 서비스와 동일
      // 원칙, CLAUDE.md 4절). 지금은 항상 unimplemented로 실패하는 게
      // 정상이라 여기서 사용자에게 별도 안내는 하지 않는다 — 애초에 이
      // 경로를 탈 구매 버튼이 없다.
      debugPrint('verifyAndGrantPurchase 호출 실패: ${e.runtimeType}');
    }
  }
}

/// [IapService.kIapEnabled]가 `false`일 때 [IapService.buyConsumable]을
/// 호출하면 던지는 예외. 사용자에게 보여줄 일반 문구를 겸한다.
class IapNotReadyException implements Exception {
  const IapNotReadyException();

  @override
  String toString() => '결제 기능은 아직 준비 중이에요.';
}

/// 스토어에 아직 등록되지 않은 상품ID 자리를 문서화하는 placeholder들.
///
/// ⚠️ **실제 스토어 상품ID가 아니다.** App Store Connect/Play Console에
/// 소모성 상품을 실제로 등록하기 전까지(P1-1, 사용자만 할 수 있는 작업)는
/// 이 이름을 어디에도 실제 조회·구매 요청에 쓰지 않는다 — 관리자 콘솔
/// (`docs/admin/admin.js`)의 "충전 상품 설정" 폼이 `config/billing.tiers`에
/// 저장하는 `productId` 필드가 실제 값을 갖게 되면 앱은 그 값을 읽어서만
/// 쓴다(하드코딩 금지). 이 클래스는 명명 규칙을 문서로 남겨 두는 용도일
/// 뿐이며, 실제 상품ID가 등록되면 지워도 된다.
class IapPlaceholderProductIds {
  const IapPlaceholderProductIds._();

  static const String tier1000 = 'credit_1000_placeholder';
  static const String tier3000 = 'credit_3000_placeholder';
  static const String tier5000 = 'credit_5000_placeholder';
  static const String tier10000 = 'credit_10000_placeholder';
}
