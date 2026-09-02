import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 약관·개인정보처리방침·만 14세 확인에 **동의한 사실**을 서버에 남긴다(P1-17).
///
/// ## 왜 필요한가
///
/// 광고 수신 동의는 이미 서버에 남는데(`adConsentAt` 등), **필수 동의 3종은
/// 아무 데도 안 남았다.** 그래서 *"이 사람이 어느 문구에 동의했는가"* 를
/// 회사가 답할 수 없었다. 방침이 개정될 때마다 그 질문이 생긴다.
///
/// ## 🚨 버전을 코드에 박지 않는다 (2026-09-02 globe2030님 결정)
///
/// 남기는 것은 **동의 시각과 항목뿐**이다. 「어느 버전이었나」는
/// `docs/legal/privacy-policy.html` 의 **개정 이력 표**(버전·공고일·시행일)로
/// 역추적한다.
///
/// ⚠️ **버전 상수를 두는 쪽이 더 위험하다.** 방침은 웹에서 바뀌고(앱 업데이트
/// 없이) 앱 상수는 스토어 업데이트로만 바뀐다 — **구조적으로 어긋난다.**
/// 어긋나면 *"v2.8 에 동의한 사람이 v2.7 로 기록"* 되는데, 이건 기록이 없는
/// 것보다 나쁘다. 없으면 「기록이 없다」이지만 틀리면 **「거짓으로 기록했다」**가
/// 된다.
///
/// 📌 같은 이유가 `legal_document_view.dart` 에 이미 적혀 있다 — *"앱에 문안을
/// 복사해 두지 않는 이유: 두 벌을 관리하면 개정할 때 어긋나고, 문서 불일치
/// 자체가 법적 리스크"*. **버전 숫자도 문안의 일부다.**
///
/// ## 🚨 그래서 시각이 정확해야 한다 — 서버 시각을 쓴다
///
/// 시각으로 버전을 역추적하는 방식이므로, **시각이 틀리면 버전도 틀린다.**
/// 기기 시계는 사용자가 바꿀 수 있어 믿을 수 없다. 그래서
/// [FieldValue.serverTimestamp]를 쓴다 — 이 선택은 위 결정에 딸려 오는 것이라
/// 함께 적어 둔다.
///
/// ## ⚠️ 규칙이 배포되기 전에는 저장이 **거부된다**
///
/// `firestore.rules` 의 `clientWritableUserFields()` 에 아래 두 필드를 넣어야
/// 쓰기가 통과한다. 그 변경은 **이번 범위가 아니다**(globe2030님 결정 —
/// 코드와 규칙을 갈라 올린다).
///
/// ```
/// 'termsConsentAt'      동의 시각(서버 시각)
/// 'termsConsentItems'   무엇에 동의했나
/// ```
///
/// 🚨 **그동안 가입한 사람의 동의가 영영 안 남으면 안 된다.** 그래서 실패를
/// 삼키지 않고 **기기에 「아직 못 남겼다」 표시를 남겨 다음 실행에서 다시
/// 시도**한다([retryPendingIfAny]). 이 저장소에는 *"호출부가 실패를 삼키고
/// `debugPrint` 만 남겨 화면에 안 드러난"* 사고 전례가 있다.
class TermsConsentService {
  TermsConsentService({FirebaseFirestore? db}) : _firestore = db;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// `users/{uid}` 의 필드명. `firestore.rules` 의 `clientWritableUserFields()`
  /// 와 **반드시 같아야** 한다 — 빠지면 쓰기가 조용히 거부된다.
  static const String fieldConsentAt = 'termsConsentAt';
  static const String fieldConsentItems = 'termsConsentItems';

  /// 무엇에 동의했는지. **화면에 있는 필수 항목과 같은 수여야 한다.**
  ///
  /// 📌 값은 사람 이름이 아니라 고정 키다 — 문구가 바뀌어도 이 키는 안 바뀌고,
  /// 「어떤 문구였나」는 시각으로 역추적한다.
  static const List<String> requiredItems = [
    'termsOfService', // 이용약관
    'privacyPolicy', // 개인정보처리방침
    'age14', // 만 14세 이상
  ];

  /// 재시도용 표시. **uid 만 담는다** — 개인정보가 아니라서 일반
  /// `shared_preferences` 로 충분하다.
  static const String _prefsPendingUid = 'terms_consent_pending_uid_v1';

  /// 가입 직후 필수 동의를 기록한다. 성공하면 `true`.
  ///
  /// 🚨 **이미 기록된 계정은 덮어쓰지 않는다.** 동의 시각은 **처음 동의한
  /// 때**여야 한다 — 로그인할 때마다 갱신되면 *"언제 동의했나"* 의 답이
  /// 계속 바뀌어 입증 자료가 못 된다. 광고 동의의 `adConsentAt` 이 같은
  /// 이유로 재가입 전까지 안 바뀐다.
  Future<bool> recordSignupConsent(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final doc = _db.collection('users').doc(uid);
      final snap = await doc.get();
      if (snap.data()?[fieldConsentAt] != null) {
        await _clearPending();
        return true; // 이미 있다 — 성공으로 본다. 덮어쓰지 않는다.
      }
      await doc.set({
        fieldConsentAt: FieldValue.serverTimestamp(),
        fieldConsentItems: requiredItems,
      }, SetOptions(merge: true));
      await _clearPending();
      return true;
    } catch (e) {
      // ⚠️ 규칙이 아직 배포되지 않았으면 여기로 온다(permission-denied).
      // 삼키지 않고 표시를 남겨 다음 실행에서 다시 시도한다.
      debugPrint('필수 동의 기록 실패 — 다음 실행에서 재시도한다: ${e.runtimeType}');
      await _markPending(uid);
      return false;
    }
  }

  /// 앱이 뜰 때 한 번 부른다. 못 남긴 동의가 있으면 다시 시도한다.
  ///
  /// 📌 **조용히 성공하는 것이 정상이다.** 사용자에게 보일 것이 없다 — 이미
  /// 동의는 받았고, 못 남긴 것은 우리 쪽 사정이다.
  Future<void> retryPendingIfAny(String currentUid) async {
    final pending = await pendingUid();
    if (pending == null) return;
    // 다른 계정으로 로그인했으면 남의 문서에 쓰지 않는다. 표시만 지운다.
    if (pending != currentUid) {
      await _clearPending();
      return;
    }
    await recordSignupConsent(pending);
  }

  /// 아직 못 남긴 uid. 없으면 `null`.
  Future<String?> pendingUid() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefsPendingUid);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _markPending(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPendingUid, uid);
  }

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsPendingUid);
  }
}
