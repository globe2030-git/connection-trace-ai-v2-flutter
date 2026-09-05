import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/account_paths.dart';

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
/// ## 🚨 그래서 시각이 정확해야 한다 — 그런데 시각이 둘이다
///
/// 시각으로 버전을 역추적하는 방식이므로 **시각이 틀리면 버전도 틀린다.**
/// 기기 시계는 사용자가 바꿀 수 있어 믿을 수 없어서 서버 시각을 쓰는데,
/// **서버 시각만 쓰면 재시도가 거짓말을 한다.**
///
/// ```
/// 사용자가 동의한 때        9월 2일
/// 규칙이 배포돼 기록된 때    9월 5일   ← serverTimestamp 는 이 값을 남긴다
/// ```
///
/// ⚠️ *"동의 시각은 처음 동의한 때여야 입증이 된다"* 는 이 파일의 원칙과
/// **정면으로 부딪힌다.** 그래서 **두 칸으로 나눈다.**
///
/// ```
/// termsConsentAt         서버가 받은 때   신뢰값 — 사용자가 못 바꾼다
/// termsConsentedAtDevice 사용자가 답한 때  참고값 — 기기 시계라 바뀔 수 있다
/// ```
///
/// ⭐ **둘이 크게 벌어져 있으면 「재시도로 늦게 들어온 것」임을 나중에 알 수
/// 있다.** 한 칸으로 뭉치면 그 사실이 사라진다.
///
/// ## ⚠️ 「시각 → 버전」은 지금 1:1이 아니다
///
/// 이 방식은 **시행일이 한 줄로 늘어설 때만** 버전을 하나로 특정한다. 그런데
/// 게시본의 개정 이력은 그렇지 않다(2026-09-02 실측).
///
/// ```
/// 2.6  공고 8/31  시행 9/2
/// 2.5  공고 8/31  시행 9/9   ← 2.6 보다 나중에 시행된다
/// 2.4 · 2.3 · 2.2 · 2.1      시행 전부 9/2
/// ```
///
/// 🚨 **9/2~9/8 에 동의한 사람은 「2.1·2.2·2.3·2.4·2.6 이 시행 중이고 2.5 는
/// 아직」인 상태에 동의한 것**이다. 시각 하나로 버전 하나를 못 짚는다.
///
/// 📌 **이것은 이 코드의 결함이 아니라 방침 문서 쪽 사정이다.** 다만 적어
/// 두지 않으면 나중에 *"시각 있으면 되잖아"* 로 넘어갔다가 못 답한다.
/// **역추적할 때는 개정 이력 표에서 「그 시각에 시행 중이던 버전 전부」를
/// 봐야 한다.** 필드를 하나 더 두는 쪽은 택하지 않았다 — 그 필드도 낡는다.
///
/// ## ⚠️ 규칙이 배포되기 전에는 저장이 **거부된다**
///
/// `firestore.rules` 의 `clientWritableUserFields()` 에 아래 **세 필드**를
/// 넣어야 쓰기가 통과한다. 그 변경은 **이번 범위가 아니다**(globe2030님 결정 —
/// 코드와 규칙을 갈라 올린다).
///
/// ```
/// 'termsConsentAt'          서버가 받은 때
/// 'termsConsentedAtDevice'  사용자가 답한 때
/// 'termsConsentItems'       무엇에 동의했나
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
  static const String fieldConsentedAtDevice = 'termsConsentedAtDevice';

  /// 무엇에 동의했는지. **화면에 있는 필수 항목과 같은 수여야 한다.**
  ///
  /// 📌 값은 사람 이름이 아니라 고정 키다 — 문구가 바뀌어도 이 키는 안 바뀌고,
  /// 「어떤 문구였나」는 시각으로 역추적한다.
  static const List<String> requiredItems = [
    'termsOfService', // 이용약관
    'privacyPolicy', // 개인정보처리방침
    'age14', // 만 14세 이상
  ];

  /// 재시도용 표시. `{uid: 동의한 기기 시각(ISO)}` 을 담는다.
  ///
  /// 🚨 **uid 만 담으면 안 된다.** 재시도가 성공하는 시점의 시각을 쓰면
  /// *"동의 시각은 처음 동의한 때"* 라는 원칙이 깨진다. **그때의 시각을 함께
  /// 들고 있어야** 나중에 그 값을 남길 수 있다.
  ///
  /// ⚠️ **계정마다 따로 담는다.** 계정을 바꿨다고 표시를 지우면, **그 계정으로
  /// 돌아와도 다시 못 쓴다** — 그 사람의 동의가 영영 안 남는다.
  ///
  /// 개인정보가 아니라(uid 와 시각뿐) 일반 `shared_preferences` 로 충분하다.
  static const String _prefsPending = 'terms_consent_pending_v2';

  /// 가입 직후 필수 동의를 기록한다. 성공하면 `true`.
  ///
  /// 🚨 **이미 기록된 계정은 덮어쓰지 않는다.** 동의 시각은 **처음 동의한
  /// 때**여야 한다 — 로그인할 때마다 갱신되면 *"언제 동의했나"* 의 답이
  /// 계속 바뀌어 입증 자료가 못 된다. 광고 동의의 `adConsentAt` 이 같은
  /// 이유로 재가입 전까지 안 바뀐다.
  Future<bool> recordSignupConsent(String uid, {DateTime? consentedAtDevice}) async {
    if (uid.isEmpty) return false;
    try {
      final doc = AccountPaths.account(_db, uid);
      final snap = await doc.get();
      if (snap.data()?[fieldConsentAt] != null) {
        await _clearPending(uid);
        return true; // 이미 있다 — 성공으로 본다. 덮어쓰지 않는다.
      }
      await doc.set({
        fieldConsentAt: FieldValue.serverTimestamp(),
        fieldConsentedAtDevice: (consentedAtDevice ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        fieldConsentItems: requiredItems,
      }, SetOptions(merge: true));
      await _clearPending(uid);
      return true;
    } catch (e) {
      // ⚠️ 규칙이 아직 배포되지 않았으면 여기로 온다(permission-denied).
      // 삼키지 않고 표시를 남겨 다음 실행에서 다시 시도한다.
      debugPrint('필수 동의 기록 실패 — 다음 실행에서 재시도한다: ${e.runtimeType}');
      await _markPending(uid, consentedAtDevice ?? DateTime.now());
      return false;
    }
  }

  /// 앱이 뜰 때 한 번 부른다. 못 남긴 동의가 있으면 다시 시도한다.
  ///
  /// 📌 **조용히 성공하는 것이 정상이다.** 사용자에게 보일 것이 없다 — 이미
  /// 동의는 받았고, 못 남긴 것은 우리 쪽 사정이다.
  Future<void> retryPendingIfAny(String currentUid) async {
    final at = await pendingConsentedAt(currentUid);
    // 지금 로그인한 계정의 몫이 없으면 아무것도 하지 않는다.
    // ⚠️ 다른 계정 몫이 남아 있어도 **지우지 않는다** — 그 계정으로 돌아오면
    // 그때 쓴다. 지우면 그 사람의 동의가 영영 안 남는다.
    if (at == null) return;
    await recordSignupConsent(currentUid, consentedAtDevice: at);
  }

  /// [uid] 가 못 남긴 동의의 **기기 시각**. 없으면 `null`.
  Future<DateTime?> pendingConsentedAt(String uid) async {
    final map = await _readPending();
    final v = map[uid];
    return v == null ? null : DateTime.tryParse(v);
  }

  /// 아직 못 남긴 계정이 몇이나 되나(진단용).
  Future<int> pendingCount() async => (await _readPending()).length;

  Future<Map<String, String>> _readPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsPending);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      // 형식이 깨졌으면 버린다. 여기서 막으면 로그인 자체가 막힌다.
      return {};
    }
  }

  Future<void> _markPending(String uid, DateTime consentedAtDevice) async {
    final map = await _readPending();
    // 이미 있으면 덮어쓰지 않는다 — 처음 동의한 때를 지켜야 한다.
    if (map.containsKey(uid)) return;
    map[uid] = consentedAtDevice.toUtc().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPending, jsonEncode(map));
  }

  Future<void> _clearPending(String uid) async {
    final map = await _readPending();
    if (map.remove(uid) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPending, jsonEncode(map));
  }
}
