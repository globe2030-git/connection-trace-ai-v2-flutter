import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/sns_auth_provider.dart';

/// 광고성 정보 수신 동의를 보관한다(추가 472 · 방침 v2.4 시행 후 유효).
///
/// ⚠️ **여기에 시행일을 적지 않는다**(2026-08-26 결정). 날짜는 방침 문서
/// (`docs/legal/privacy-policy.html`) 한 곳에만 둔다.
///
/// ## 🚨 [PhotoImprovementConsentService]를 그대로 베끼면 안 된다
///
/// 두 서비스는 겉모습이 거의 같다 — 기기 캐시 + `users/{uid}` 필드, 서버 실패 시
/// 되돌리기. 그래서 **복사해서 고치기 쉬운 자리**인데, **두 곳이 반대여야 한다.**
///
/// | | 사진 개선 동의 | **광고 수신 동의(이 서비스)** |
/// |---|---|---|
/// | 철회하면 동의 시각을 | `null`로 **지운다** | 🚨 **지우지 않는다** |
/// | 읽기 실패는 | 언제나 "동의 안 함" | **쓰는 곳에 따라 다르다**(아래) |
///
/// ### ① 철회해도 [_fieldConsentAt]을 지우지 않는다
///
/// 지우면 셋이 함께 사라진다(법률 조사 추가 457).
///
/// 1. **입증자료** — 동의를 받은 사실과 그 시점은 **회사가 증명해야 한다**
/// 2. **2년 재확인 기산점** — 정보통신망법이 2년마다 수신동의 여부를 다시
///    확인하도록 하는데, 그 기준 날짜가 없어진다
/// 3. **처리결과 통지 증적** — 동의·철회 후 14일 내 통지 의무(§50⑦)를 지켰다는
///    기록이 없어진다
///
/// 사진 개선 동의에서 `null`로 지우는 것은 **그 서비스에서는 맞다** — 거기서는
/// 시각이 *"지금 동의 상태인가"*를 나타내는 값일 뿐이고 법정 입증 의무가 없다.
/// 여기서는 시각 자체가 증거다.
///
/// ### ② 읽기 실패를 두 갈래로 쓴다
///
/// 사진 개선 동의는 *"읽기 실패는 동의 안 함으로 떨어뜨린다"* 하나다. 발송을
/// 막는 방향이라 맞다. 그런데 **화면을 띄울지 정하는 데 그대로 쓰면 뒤집힌다.**
///
/// ```
/// 읽기 실패 → "동의 안 함" → 응답 기록 없음 → 동의 화면을 띄운다
///                                          ↑ 이미 답한 사람에게 또 묻는다
/// ```
///
/// 그래서 갈랐다.
///
/// | 무엇을 정하나 | 읽기 실패일 때 |
/// |---|---|
/// | **보내도 되나**([canSendEmail]·[canSendPush]) | **안 된다**로 본다 |
/// | **물어봐야 하나**([shouldAsk]) | **묻지 않는다** — 다음 로그인에 다시 기회가 온다 |
///
/// 뒤쪽은 `auth_gate`가 이미 같은 판단을 한다(*"마지막 uid를 못 읽으면 …
/// 다음 로그인에 다시 기회가 온다"*).
///
/// ## ⚠️ `firestore.rules`에 필드 이름이 없으면 조용히 거부된다
///
/// `clientWritableUserFields()`에 아래 다섯이 있어야 쓰기가 통과한다. 한쪽만
/// 바꾸면 **서버 쓰기가 거부되는데 화면은 켜진다.**
///
/// 그래서 [save]는 **실패하면 기기 값을 되돌리고 `false`를 반환한다.** 부르는
/// 쪽은 그 값을 보고 **화면 상태도 되돌려야 한다** — 서버는 거부했는데 체크가
/// 켜진 채면 이용자는 동의한 줄 알고, 그건 동의 없는 이용이 된다.
///
/// 📌 같은 파일에 선례가 있다 — `accountSwitches`가 목록에 없어서 계정 전환
/// 기록이 **조용히 실패하고 있었을 수 있다**는 주석이 붙어 있다. 호출부가
/// 실패를 삼키는 구조였기 때문이다. 이 서비스는 삼키지 않는다.
///
/// ## 범위 밖
///
/// 발송은 이 서비스가 하지 않는다. 발송 함수·"(광고)" 표기·야간(21~08시) 차단은
/// 별도 작업이다. **FCM 등록 토큰도 여기서 다루지 않는다** — 토큰 수집 시점이
/// P2-2(백그라운드 근접 푸시) 결정에 달려 있어, 지금 정하면 그때 다시 짜야 한다.
class AdConsentService {
  // 아래 _db 게터가 이 필드를 감싸 기본 인스턴스를 지연 생성한다 — 테스트에서
  // Firebase 초기화 없이 이 클래스를 만들 수 있어야 해서 이 형태를 쓴다.
  // ignore: prefer_initializing_formals
  AdConsentService({FirebaseFirestore? db}) : _firestore = db;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// 개인정보가 아니라 설정값(불리언)이라 일반 `shared_preferences`에 둔다.
  static const String _prefsEmail = 'ad_consent_email_v1';
  static const String _prefsPush = 'ad_consent_push_v1';

  /// **미룬 시각**(밀리초). 답하지 않고 화면을 빠져나간 시각을 적어 둔다.
  ///
  /// 🚨 **서버가 아니라 기기에 둔다.** 이것은 동의 증적이 아니라 **언제 다시
  /// 물을지**를 정하는 값이라, 서버에 올릴 이유가 없다. `firestore.rules` 의
  /// `clientWritableUserFields()` 를 건드리지 않아도 되므로 조용히 거부될
  /// 위험도 없다(위 주석 참고).
  ///
  /// ⚠️ 기기를 바꾸면 초기화된다 — **그게 맞다.** 새 기기에서는 한 번 묻는
  /// 편이 낫고, 개인정보도 아니다(시각 하나뿐).
  ///
  /// 🚨 **계정마다 따로 적는다.** 처음에는 키 하나로 뒀는데, 그러면 **로그아웃
  /// 하고 다른 계정으로 들어와도 안 묻는다** — 그 사람은 물어본 적이 없는데
  /// 미룬 것으로 취급된다. `uid` 를 키에 넣어 가른다.
  ///
  /// ⚠️ **uid 를 그대로 키에 쓴다.** 개인정보가 아니고(제공자가 준 식별자),
  /// 값도 시각 하나뿐이다 — 규약 4절이 금지하는 「개인정보 원문」이 아니다.
  static String _prefsSnoozedAt(String uid) => 'ad_consent_snoozed_at_v1_$uid';

  /// `users/{uid}`의 필드명. `firestore.rules`의 `clientWritableUserFields()`에
  /// **같은 이름이 있어야** 쓰기가 통과한다.
  static const String _fieldEmail = 'adConsentEmail';
  static const String _fieldPush = 'adConsentPush';

  /// 🚨 **철회해도 지우지 않는다.** 처음 답한 시각을 그대로 둔다 — 위 ① 참조.
  static const String _fieldConsentAt = 'adConsentAt';

  /// 마지막으로 바꾼 시각. 철회도 여기 남는다(동의·철회 **이력** 보관).
  static const String _fieldChangedAt = 'adConsentChangedAt';

  /// 처리결과를 통지한 시각. 동의·철회 후 14일 내 통지 의무(§50⑦)의 증적이다.
  static const String _fieldNotifiedAt = 'adConsentNotifiedAt';

  /// 서버에서 읽은 현재 상태. 읽기에 실패하면 `null`이다.
  ///
  /// ⚠️ **`null`과 "동의 안 함"을 같게 다루지 마라.** `null`은 *"모른다"*이고,
  /// [AdConsentState.none]은 *"물었고 둘 다 거부했다"*이다.
  Future<AdConsentState?> fetch(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data();
      if (data == null) return AdConsentState.unasked;
      final answeredAt = data[_fieldConsentAt];
      if (answeredAt == null) return AdConsentState.unasked;
      return AdConsentState(
        email: data[_fieldEmail] == true,
        push: data[_fieldPush] == true,
        answered: true,
      );
    } catch (e) {
      // 값이 아니라 실패를 돌려준다. 부르는 쪽이 "모른다"를 알아야
      // 화면 판정과 발송 판정을 다르게 할 수 있다.
      debugPrint('광고 수신 동의 조회 실패: ${e.runtimeType}');
      return null;
    }
  }

  /// 동의 화면을 띄워야 하는가.
  ///
  /// **읽기에 실패하면 띄우지 않는다.** 이미 답한 사람에게 또 묻는 것보다
  /// 한 번 건너뛰는 편이 낫다 — 다음 로그인에 다시 기회가 온다.
  Future<bool> shouldAsk(String uid) async {
    final state = await fetch(uid);
    if (state == null) return false;
    if (state.answered) return false;
    return !await _isSnoozed(uid);
  }

  /// **미루기로 한 기간이 아직 안 지났는가.**
  ///
  /// 🚨 **이 함수가 없을 때는 앱을 켤 때마다 동의 화면이 떴다**(2026-08-30,
  /// globe2030님 지시로 실측). *"다음 로그인에 다시 기회가 온다"* 고 적혀
  /// 있었는데, 실제로는 **답할 때까지 매번** 떴다 — 로그인이 유지돼 있어도
  /// `auth_gate` 가 앱을 켤 때마다 이 판정을 하기 때문이다.
  ///
  /// ⚠️ **그건 「자유로운 동의」에서 멀어진다.** 답할 때까지 계속 뜨면
  /// 이용자는 필수라고 느낀다 — 이 파일과 `auth_gate` 가 피하려던 바로 그
  /// 자리다(시행령 §17①1호).
  ///
  /// 📌 **읽기에 실패하면 미루지 않은 것으로 본다**(= 묻는다). 못 묻는 쪽보다
  /// 한 번 더 묻는 쪽이 낫다 — 동의 기회 자체가 사라지지는 않는다.
  Future<bool> _isSnoozed(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_prefsSnoozedAt(uid));
      if (at == null) return false;
      final elapsed = DateTime.now().millisecondsSinceEpoch - at;
      return elapsed >= 0 && elapsed < snoozeDuration.inMilliseconds;
    } catch (e) {
      debugPrint('광고 수신 동의 미루기 조회 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// **답하지 않고 넘어갔다**는 것을 적어 둔다.
  ///
  /// 답이 아니라 **미룸**이다. `adConsentAt`(서버) 은 건드리지 않으므로
  /// **「답한 적 있다」로 굳지 않고**, [snoozeDuration] 이 지나면 다시 묻는다.
  Future<void> snooze(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _prefsSnoozedAt(uid),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('광고 수신 동의 미루기 저장 실패: ${e.runtimeType}');
    }
  }

  /// 미룬 뒤 다시 묻기까지의 기간 (2026-08-30 globe2030님 확정: 30일).
  ///
  /// ⚠️ **줄이려면 근거를 함께 적어라.** 짧을수록 동의율은 오르지만 「필수처럼
  /// 느껴지는」 쪽으로 간다. 30일은 **거의 안 보이는 쪽**을 고른 값이다.
  @visibleForTesting
  static const Duration snoozeDuration = Duration(days: 30);

  /// 이메일로 광고를 보내도 되는가. **모르면 안 된다.**
  Future<bool> canSendEmail(String uid) async =>
      (await fetch(uid))?.email ?? false;

  /// 앱 알림으로 광고를 보내도 되는가. **모르면 안 된다.**
  ///
  /// ⚠️ 이 값이 `true`여도 지금은 보낼 수 없다 — 등록 토큰을 수집하지 않는다.
  Future<bool> canSendPush(String uid) async =>
      (await fetch(uid))?.push ?? false;

  /// 기기에 캐시된 값. 서버에 못 닿을 때 화면을 그리는 용도다.
  Future<AdConsentState> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AdConsentState(
        email: prefs.getBool(_prefsEmail) ?? false,
        push: prefs.getBool(_prefsPush) ?? false,
        answered: prefs.containsKey(_prefsEmail),
      );
    } catch (e) {
      debugPrint('광고 수신 동의 캐시 조회 실패: ${e.runtimeType}');
      return AdConsentState.unasked;
    }
  }

  /// 동의 상태를 저장한다. 최초 응답과 이후 변경(철회 포함)을 모두 이 하나로
  /// 처리한다.
  ///
  /// 기기에 먼저 쓰고 서버에 반영한다. **서버가 거부하면 기기 값을 되돌리고
  /// `false`를 돌려준다** — 부르는 쪽은 화면 상태도 함께 되돌려야 한다.
  ///
  /// [firstAnswer]가 `true`면 [_fieldConsentAt]을 처음으로 쓴다. 이후 변경에서는
  /// **건드리지 않는다** — 그 값이 곧 증거이기 때문이다.
  Future<bool> save({
    required String uid,
    required bool email,
    required bool push,
    required bool firstAnswer,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final prevEmail = prefs.getBool(_prefsEmail);
    final prevPush = prefs.getBool(_prefsPush);
    await prefs.setBool(_prefsEmail, email);
    await prefs.setBool(_prefsPush, push);
    try {
      await _db.collection('users').doc(uid).set({
        _fieldEmail: email,
        _fieldPush: push,
        // 최초 응답에만 쓴다. 철회에서도 덮지 않는다.
        if (firstAnswer) _fieldConsentAt: FieldValue.serverTimestamp(),
        _fieldChangedAt: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      // 되돌린다. 이전에 값이 없었으면 키 자체를 지워 "아직 안 물었다"로
      // 돌아가야 한다 — false로 덮으면 "물었고 거부했다"가 되어 버린다.
      if (prevEmail == null) {
        await prefs.remove(_prefsEmail);
      } else {
        await prefs.setBool(_prefsEmail, prevEmail);
      }
      if (prevPush == null) {
        await prefs.remove(_prefsPush);
      } else {
        await prefs.setBool(_prefsPush, prevPush);
      }
      debugPrint('광고 수신 동의 서버 반영 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// 처리결과를 통지했음을 남긴다(§50⑦·시행령 §62의2, 14일 내).
  ///
  /// 통지 자체는 화면이 하고, 이 함수는 **증적만** 남긴다. 실패해도 통지는 이미
  /// 이용자에게 보였으므로 화면을 되돌리지 않는다 — 실패를 삼키지 않고
  /// `false`를 돌려주되, 부르는 쪽이 재시도할지는 판단에 맡긴다.
  Future<bool> markNotified(String uid) async {
    try {
      await _db.collection('users').doc(uid).set({
        _fieldNotifiedAt: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('광고 수신 동의 통지 기록 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// ⑨(`SignupConsentView`)에서 미리 골라 둔 값을, 계정이 실제로 만들어진 뒤
  /// 적용한다(추가 632, `email-signup-unified-consent-2026-08-31.md` §4).
  ///
  /// 🚨 **이미 답한 계정이면 화면에서 고른 값을 버리고 아무것도 하지 않는다.**
  /// ⑨는 uid를 모르는 시점(로그인/가입 전)에 뜨므로, 로그아웃 뒤 다시
  /// 로그인한 **기존** 이용자도 이 화면을 다시 볼 수 있다 — 그때 예전 답을
  /// 실수로 덮으면 안 된다. `shouldAsk`와 같은 보수적 판단(모르면 안
  /// 건드린다)을 그대로 따른다.
  ///
  /// [emailChannelAvailable]은 호출 시점의 provider 기준으로 **부르는 쪽이**
  /// 넘긴다 — [adEmailChannelAvailable]과 같은 판정을 이 함수 안에서 다시
  /// 하지 않기 위해서다(그 함수는 provider를 몰라도 되게 만들어졌다).
  Future<void> applyFreshSignupChoice({
    required String uid,
    required bool email,
    required bool push,
    required bool emailChannelAvailable,
  }) async {
    final state = await fetch(uid);
    if (!shouldApplyFreshSignupChoice(state)) return;
    await save(
      uid: uid,
      email: email && emailChannelAvailable,
      push: push,
      firstAnswer: true,
    );
  }

  /// [applyFreshSignupChoice]의 핵심 판정만 뽑은 **순수 함수**(추가 632).
  ///
  /// 🚨 **"이미 답한 계정에게 ⑨를 다시 보여줘도 `adConsentAt`이 안 바뀐다"**는
  /// 이 저장소가 가장 중요하게 지키라고 한 회귀 방지 지점이다. `fetch`/`save`는
  /// Firestore 인스턴스가 있어야 해서 `flutter test`로 못 덮지만, **저장을
  /// 할지 말지 정하는 이 판정 자체는 순수 로직**이라 여기서 떼어내 테스트로
  /// 고정한다 — `state`를 안다고 가정하면 나머지는 입출력이 없다.
  @visibleForTesting
  static bool shouldApplyFreshSignupChoice(AdConsentState? state) {
    // state == null(읽기 실패)이거나 이미 답한 계정이면 손대지 않는다.
    return state != null && !state.answered;
  }

  /// 계정 삭제·로그아웃 시 기기 캐시를 지운다.
  ///
  /// 남으면 같은 기기에서 다음 계정이 **앞 사람의 동의를 물려받는다.**
  /// 사진 개선 동의에도 같은 정리가 있다(settings_view 1-1 주석).
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsEmail);
      await prefs.remove(_prefsPush);
    } catch (e) {
      debugPrint('광고 수신 동의 캐시 정리 실패: ${e.runtimeType}');
    }
  }
}

/// 광고 수신 동의의 현재 상태.
///
/// [answered]가 **"물어봤고 이용자가 답했다"**를 뜻한다. 이것이 `false`인 것과
/// [email]·[push]가 둘 다 `false`인 것은 **다르다** —
///
/// ```
/// answered == false            아직 안 물었다        → 동의 화면을 띄운다
/// answered == true, 둘 다 false  물었고 거부했다       → 띄우지 않는다
/// ```
///
/// 법적으로도 다르다. 앞은 동의를 받은 적이 없는 것이고, 뒤는 **거부 의사를
/// 받아 둔 것**이다.
@immutable
class AdConsentState {
  const AdConsentState({
    required this.email,
    required this.push,
    required this.answered,
  });

  /// 아직 묻지 않은 상태.
  static const AdConsentState unasked =
      AdConsentState(email: false, push: false, answered: false);

  /// 물었고 둘 다 거부한 상태.
  static const AdConsentState none =
      AdConsentState(email: false, push: false, answered: true);

  final bool email;
  final bool push;
  final bool answered;

  /// 하나라도 받겠다고 한 상태.
  bool get anyEnabled => email || push;

  @override
  bool operator ==(Object other) =>
      other is AdConsentState &&
      other.email == email &&
      other.push == push &&
      other.answered == answered;

  @override
  int get hashCode => Object.hash(email, push, answered);
}

/// 이 제공자로 로그인한 이용자에게 **이메일 채널을 보여도 되는가.**
///
/// ## 🚨 네이버는 안 된다 — 그 이메일은 남의 것일 수 있다
///
/// 네이버가 주는 값은 네이버 계정 이메일이 아니라 이용자가 등록한
/// **"연락처 이메일"**이다. 네이버 콘솔 안내 원문: *"계정별로 고유한 값이
/// 아니며, 네이버 메일 외 다른 도메인으로도 설정 가능합니다."* 즉 **계정별
/// 고유가 아니고 소유 확인도 제공되지 않는다.**
///
/// 그 주소로 광고를 보내면 둘이 한꺼번에 일어난다(법무 회신 추가 473 Q10-④6).
///
/// 1. **동의하지 않은 제3자에게 광고를 전송** — 정보통신망법 §50① 위반
/// 2. **그 사람에게 이용자의 가입 사실이 전달된다**
///
/// 2차 법무 회신(질문 8-④3항)이 이미 *"네이버 연락처 이메일로 메일을 발송하지
/// 말 것"*을 운영 규칙으로 권고했고, **광고 이메일에서 그 규칙이 처음 현실이
/// 된다.**
///
/// 📌 화면 문구 *"가입하신 이메일 주소로 보내드려요"*는 **네이버 이용자에게
/// 사실이 아니다.** 그래서 체크박스를 아예 보이지 않게 한다 — 문구만 고치면
/// *"동의는 받아 두고 못 보내는"* 상태가 남는다.
///
/// ## 모르면 보여주지 않는다
///
/// 제공자를 알 수 없으면(`null` — 게스트 QA 로그인 등) **보여주지 않는다.**
/// 보내도 되는지 모르는 상태에서 동의부터 받아 두면, 나중에 판단이 뒤집혔을 때
/// **이미 받은 동의를 되돌려야 한다.**
///
/// ## ⚠️ 애플은 보여주되, 발송 쪽에 숙제가 남는다
///
/// 애플 릴레이 주소(`@privaterelay.appleid.com`)는 **법적 문제는 아니다** —
/// 이용자 본인에게 닿는 주소가 맞다. 다만 발신 도메인을 Apple에 등록하지 않으면
/// **메일이 전달되지 않아** *"동의했는데 안 온다"*가 된다. 발송 장치를 만들 때
/// 확인할 항목이지 동의 화면에서 막을 일이 아니다.
bool adEmailChannelAvailable(SnsAuthProvider? provider) => switch (provider) {
      SnsAuthProvider.naver => false,
      null => false,
      SnsAuthProvider.google ||
      SnsAuthProvider.apple ||
      SnsAuthProvider.kakao =>
        true,
      // 이메일 가입은 이용자가 **직접 타이핑해 로그인에 쓰는 주소**라 —
      // 네이버의 "연락처 이메일"과 반대로, 소유 확인이 필요 없을 만큼
      // 확실하다(추가 632).
      SnsAuthProvider.email => true,
    };
