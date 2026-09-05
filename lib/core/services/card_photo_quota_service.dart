import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/card_photo_quota.dart';
import '../utils/account_paths.dart';

/// 이 이용자의 **명함 사진 서버 백업 한도**를 읽어 온다(2026-08-16).
///
/// ## 왜 서버에 두나
///
/// **컴파일 상수로 박으면 한도를 올릴 때마다 앱을 새로 배포**해야 한다.
/// 한도는 *"낮게 시작해 필요하면 올린다"*는 전제 위에 정해졌으므로(무료
/// 2,000장) **올릴 일이 온다.** 그때 서버 값 하나만 바꾸면 되게 한다.
///
/// ⚠️ **`users/{uid}.cardPhotoQuota`는 서버 전용이다.**
/// `firestore.rules`의 `clientWritableUserFields()`가 **허용 목록**이라, 거기
/// 없는 이 필드는 **클라이언트가 쓸 수 없다.** 그 목록에 넣으면 **이용자가
/// 자기 한도를 늘려** 한도가 무의미해진다(AI 잔여 회차와 같은 원칙).
///
/// ## 왜 캐시하나
///
/// 명함을 저장할 때마다 한도를 물으면 **저장 경로에 네트워크 왕복이 붙는다.**
/// 한도는 거의 안 바뀌므로 마지막 값을 기기에 두고, 조회에 실패하면 그것을
/// 쓴다. 그것도 없으면 기본값이다.
///
/// ⚠️ **캐시 값이 실제보다 클 수 있다**(서버에서 내렸는데 아직 못 읽은 경우).
/// 그래도 조용히 막는 것보다 낫다 — 한도를 내리는 일 자체가 드물고, 잘못
/// 막으면 사용자는 이유를 알 수 없다.
class CardPhotoQuotaService {
  CardPhotoQuotaService({FirebaseFirestore? db}) : _injected = db;

  /// ⚠️ **생성자에서 `FirebaseFirestore.instance`를 잡지 않는다.**
  /// 이 서비스는 `ContactImageService`가 기본값으로 만들어 두는데, 그 객체는
  /// 위젯 테스트에서도 생성된다. 생성자에서 인스턴스를 잡으면 Firebase가
  /// 초기화되지 않은 테스트가 통째로 죽는다(`[core/no-app]`). **실제로 25건이
  /// 깨졌다**(2026-08-16).
  final FirebaseFirestore? _injected;

  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  static const String _fieldQuota = 'cardPhotoQuota';
  static const String _prefsKey = 'card_photo_quota_cached_v1';

  /// 서버에서 읽고 기기에 갈무리한다. 실패하면 갈무리해 둔 값, 그것도 없으면
  /// 기본값([kCardPhotoQuota]).
  Future<int> fetch(String uid) async {
    try {
      final snap = await AccountPaths.account(_db, uid).get();
      final raw = snap.data()?[_fieldQuota];
      if (raw is int) {
        final quota = resolveQuota(raw);
        await _cache(quota);
        return quota;
      }
      // 필드가 아직 없는 계정이 정상이다 — 기본값으로 시작한다.
      return await cachedOrDefault();
    } catch (e) {
      debugPrint('사진 한도 조회 실패: ${e.runtimeType}');
      return cachedOrDefault();
    }
  }

  /// 네트워크 없이 즉시 답한다. 목록 화면처럼 **기다릴 수 없는 자리**에서 쓴다.
  Future<int> cachedOrDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return resolveQuota(prefs.getInt(_prefsKey));
    } catch (_) {
      return kCardPhotoQuota;
    }
  }

  Future<void> _cache(int quota) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, quota);
    } catch (_) {
      // 갈무리 실패는 무시한다. 다음에 다시 읽으면 된다.
    }
  }

  /// 계정을 갈아탈 때 비운다. 앞 사람의 한도가 뒷사람에게 적용되면 안 된다.
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
