import 'package:cloud_firestore/cloud_firestore.dart';

/// 한 사람의 데이터가 **Firestore 어디에 사는지**를 한 군데로 모은 곳.
///
/// ## 왜 굳이 감싸나 — 곧 옮겨가기 때문이다
///
/// 지금 모든 데이터는 `users/{uid}` 밑에 있다. 그런데 계정 식별 C안이
/// 들어오면 **사람과 계정이 갈라진다** — 한 사람이 로그인 수단을 더하거나
/// 번호로 이으면 uid 가 여럿이 되고, 명함첩은 **사람**에 붙어야 한다.
///
/// ```
/// 지금        users/{uid}/contacts/{id}
/// C안 뒤      people/{personId}/contacts/{id}     ← 명함은 사람 밑으로
///             users/{uid}.personId                 ← 계정은 역참조만
///             users/{uid}.encryptionKeyB64         ← 키는 계정마다 그대로
/// ```
///
/// 자세한 것은 `docs/planning/data-schema.md` 「사람 레이어」 절에 있다.
///
/// 📌 **그날 고칠 곳이 열몇 군데면 그중 하나는 빠뜨린다.** 그래서 옮기기
/// 전에 **부르는 자리를 먼저 한 군데로 모은다.** 이 파일이 그 한 군데다.
///
/// ## ⚠️ 이 단계에서는 동작이 하나도 안 바뀐다
///
/// 여기 있는 함수들은 전부 예전과 **똑같은 경로**를 돌려준다. 바뀌는 것은
/// **부르는 쪽의 모양**뿐이다. 그래서 이 변경만으로는 테스트가 늘지도
/// 줄지도 않아야 맞다.
///
/// 🚨 **경로를 실제로 옮기는 것은 이 파일을 고치는 일이 된다** — 부르는 쪽
/// 열몇 군데가 아니라. 그것이 이 파일이 있는 이유다.
///
/// ## 🚨 uid 를 그대로 넘기지 말아야 할 날이 온다
///
/// C안 뒤에는 `uid` 가 아니라 `personId` 로 찾아야 하는 자리가 생긴다.
/// 그때 **이 함수들의 인자가 바뀐다.** 지금 `uid` 를 받는 것은 오늘의
/// 사실이지 영원한 것이 아니다 — 부르는 쪽에서 `users/` 문자열을 다시
/// 조립하지 말 것.
class AccountPaths {
  const AccountPaths._();

  /// 계정 문서 — 지금은 `users/{uid}`.
  ///
  /// 암호화 키(`encryptionKeyB64`)·동의 기록·AI 사용량처럼 **계정에 붙는
  /// 것**이 여기 있다. C안 뒤에도 이 문서는 남는다(사람으로 옮겨가는 것은
  /// 명함첩 쪽이다).
  static DocumentReference<Map<String, dynamic>> account(
    FirebaseFirestore db,
    String uid,
  ) => db.collection('users').doc(uid);

  /// 명함첩 — 지금은 `users/{uid}/contacts`.
  ///
  /// ⚠️ C안 뒤 `people/{personId}/contacts` 로 **옮겨간다.**
  static CollectionReference<Map<String, dynamic>> contacts(
    FirebaseFirestore db,
    String uid,
  ) => account(db, uid).collection('contacts');

  /// 명함 원본 출처 — 지금은 `users/{uid}/cardSources`.
  ///
  /// ⚠️ 명함첩과 **함께** 옮겨간다.
  static CollectionReference<Map<String, dynamic>> cardSources(
    FirebaseFirestore db,
    String uid,
  ) => account(db, uid).collection('cardSources');

  /// 지운 명함의 묘비 — 지금은 `users/{uid}/deletedContacts`.
  ///
  /// ⚠️ 명함첩과 **함께** 옮겨간다. 이것이 안 따라가면 **다른 기기에서
  /// 지운 명함이 되살아난다.**
  static CollectionReference<Map<String, dynamic>> deletedContacts(
    FirebaseFirestore db,
    String uid,
  ) => account(db, uid).collection('deletedContacts');
}
