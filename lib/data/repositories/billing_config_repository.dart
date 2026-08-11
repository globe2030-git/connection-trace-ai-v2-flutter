import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/billing_config_model.dart';

/// `config/billing` 문서 읽기 전용 저장소.
///
/// 작성은 관리자 콘솔(`docs/admin/admin.js`)에서만 하고, `firestore.rules`가
/// 로그인 사용자에게 읽기만 열어 둔 것을 그대로 따른다(규칙 변경 없음).
///
/// [AppUpdateService](../../core/services/app_update_service.dart)와 같은
/// 이유로 `fetchRaw`를 생성자에서 주입받을 수 있게 열어 둔다 — 실제 Firestore
/// 호출 없이 단위 테스트에서 원하는 Map을 바로 흘려보낼 수 있다.
class BillingConfigRepository {
  static const String _docPath = 'config/billing';

  final Future<Map<String, dynamic>?> Function() _fetchRaw;

  BillingConfigRepository({Future<Map<String, dynamic>?> Function()? fetchRaw})
    : _fetchRaw = fetchRaw ?? _readDoc;

  /// 문서를 읽어 [BillingConfig]로 파싱한다. 문서가 없으면 `null`.
  ///
  /// `active == true`이면서 `credits`가 1 이상인 티어만 남기고 가격
  /// 오름차순으로 정렬한다 — 관리자 콘솔이 "회수 미정" 티어를 판매 중으로
  /// 켜지 못하게 막아 두긴 했지만, 앱 쪽에서 한 번 더 방어한다.
  Future<BillingConfig?> fetchConfig() async {
    final raw = await _fetchRaw();
    if (raw == null) return null;

    final config = BillingConfig.fromMap(raw);
    final validTiers =
        config.tiers.where((t) => t.active && t.credits >= 1).toList()
          ..sort((a, b) => a.priceKrw.compareTo(b.priceKrw));

    return BillingConfig(freeCredits: config.freeCredits, tiers: validTiers);
  }

  static Future<Map<String, dynamic>?> _readDoc() async {
    final snap = await FirebaseFirestore.instance.doc(_docPath).get();
    return snap.exists ? snap.data() : null;
  }
}
