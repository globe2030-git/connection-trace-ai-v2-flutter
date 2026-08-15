import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "명함 사진을 인식 기능 개선에 써도 된다"는 **별도 동의**를 보관한다.
///
/// ## 무엇에 대한 동의인가 — 범위를 좁게 잡는 것이 핵심이다
///
/// 명함 사진의 이용은 성격이 다른 둘로 나뉜다(2026-08-15 사용자 확정,
/// backlog 추가 218 · 개인정보처리방침 v2.2 2-1/2-2).
///
/// | 무엇 | 근거 | 동의 |
/// |---|---|---|
/// | 저장·조회·관리, 기기 변경 시 복원 | 계약의 이행 | 불필요 |
/// | **그 이용자 본인** 명함 정보의 확인·보정 | 계약의 이행 | 불필요 |
/// | **여러 이용자의 사진을 함께** 이용한 인식 알고리즘 개선 | 정보주체의 동의 | **필요 — 이 서비스** |
///
/// 가르는 기준은 "누구를 위한 처리인가"다. 앞의 셋은 그 이용자에게 제공하는
/// 서비스라 동의가 필요 없고, 마지막 하나는 다른 이용자의 사진까지 모아
/// 회사의 기능을 좋게 만드는 일이라 목적이 다르다. 리멤버도 사진을 보유하되
/// 방침에 "알고리즘 개선" 목적은 적지 않는다.
///
/// **그래서 이 동의를 끈 사용자도 명함 등록·복원·보정을 전부 그대로 쓴다.**
/// 이 값이 막는 것은 오직 "당신 사진을 개선용 표본에 포함해도 되는가" 하나다.
///
/// ## 왜 서버에도 쓰는가
///
/// 기기에만 두면 **누가 동의했는지 회사가 알 수 없다.** 개선용 표본을 고르는
/// 일은 서버 쪽 데이터(Storage의 사진)를 보고 하므로, 동의 여부도 같은 곳에
/// 있어야 "동의한 사람 것만"이 실제로 지켜진다. 동의는 증빙이 필요한
/// 기록이기도 하다.
///
/// 기기 저장은 화면을 즉시 그리기 위한 캐시다 — 서버 왕복을 기다리며 토글이
/// 늦게 켜지는 것을 막는다. **둘이 어긋나면 서버가 맞다**([sync] 참고).
///
/// ## 기본값은 꺼짐
///
/// 저장된 값이 없으면 `false`다. 동의는 명시적으로 켠 것만 동의다 —
/// "기본으로 켜 두고 끄게 하는" 방식은 이 앱의 가짜 데이터 금지 원칙과 같은
/// 이유로 쓰지 않는다.
class PhotoImprovementConsentService {
  // 아래 _db 게터가 이 필드를 감싸 기본 인스턴스를 지연 생성한다 — 테스트에서
  // Firebase 초기화 없이 이 클래스를 만들 수 있어야 해서 이 형태를 쓴다.
  // ignore: prefer_initializing_formals
  PhotoImprovementConsentService({FirebaseFirestore? db}) : _firestore = db;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// 개인정보가 아니라 설정값(불리언)이라 일반 `shared_preferences`에 둔다.
  /// 값 자체로는 누구의 무엇도 알 수 없다.
  static const String _prefsKey = 'photo_improvement_consent_v1';

  /// `users/{uid}`의 필드명. `firestore.rules`의 `clientWritableUserFields()`에
  /// 같은 이름이 있어야 쓰기가 통과한다 — 한쪽만 바꾸면 조용히 거부된다.
  ///
  /// ⚠️ **규칙을 배포하기 전까지 토글은 실제로 켜지지 않는다.** 규칙이 두 필드를
  /// 모르는 상태에서는 서버 쓰기가 거부되고, [setConsent]가 기기 값을 되돌린 뒤
  /// "저장하지 못했어요"를 띄운다. 이건 결함이 아니라 **의도한 실패**다 —
  /// 서버에 동의 기록이 없는데 화면만 켜져 있으면 동의 없는 이용이 된다.
  static const String _fieldConsent = 'photoImprovementConsent';
  static const String _fieldConsentAt = 'photoImprovementConsentAt';

  /// 기기에 캐시된 동의 여부. 저장된 적이 없으면 `false`.
  Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (e) {
      // 읽기 실패는 "동의 안 함"으로 떨어뜨린다. 반대로 하면 실패가 동의로
      // 둔갑한다.
      debugPrint('사진 개선 동의 조회 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// 동의를 바꾼다. 기기에 먼저 쓰고 서버에 반영한다.
  ///
  /// 서버 쓰기가 실패하면 **기기 값을 되돌린다.** 어긋난 채로 두면 사용자
  /// 화면에는 켜져 있는데 회사는 동의를 못 받은 상태가 되고, 그 상태로 사진을
  /// 표본에 넣으면 동의 없는 이용이 된다. 화면이 잠깐 틀리는 것보다 훨씬
  /// 나쁘다.
  ///
  /// 서버까지 성공하면 `true`.
  Future<bool> setConsent({required String uid, required bool consented}) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getBool(_prefsKey) ?? false;
    await prefs.setBool(_prefsKey, consented);
    try {
      await _db.collection('users').doc(uid).set({
        _fieldConsent: consented,
        // 언제 동의했는지가 증빙의 핵심이다. 철회하면 null로 지워 "지금은
        // 동의 상태가 아니다"를 분명히 한다.
        _fieldConsentAt: consented ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      await prefs.setBool(_prefsKey, previous);
      debugPrint('사진 개선 동의 서버 반영 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// 서버 값을 기기로 맞춘다. 로그인 직후·기기 변경 후에 부른다.
  ///
  /// 기기를 바꾸면 `shared_preferences`는 비어 있어 기본값 `false`가 되는데,
  /// 서버에는 동의가 남아 있다. 맞춰 주지 않으면 **이미 동의한 사용자에게
  /// 토글이 꺼진 것처럼 보인다.**
  ///
  /// 서버 조회에 실패하면 기기 값을 그대로 둔다(임의로 끄지 않는다).
  /// 반영된 값을 반환한다.
  Future<bool> sync(String uid) async {
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final remote = snap.data()?[_fieldConsent];
      if (remote is! bool) return load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, remote);
      return remote;
    } catch (e) {
      debugPrint('사진 개선 동의 동기화 실패: ${e.runtimeType}');
      return load();
    }
  }

  /// 로그아웃·계정 삭제 시 기기 캐시를 지운다. 다음 계정이 앞 사람의 동의를
  /// 물려받으면 안 된다.
  Future<void> clearLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('사진 개선 동의 초기화 실패: ${e.runtimeType}');
    }
  }
}
