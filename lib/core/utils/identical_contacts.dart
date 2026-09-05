/// **완전히 같은 명함**을 가려낸다 — 두 기기가 같은 사람을 각각 등록한 경우
/// (2026-08-29, 추가 572).
///
/// ## 무엇이 문제였나
///
/// 같은 계정이라도 **기기가 둘이면 같은 사람이 두 장이 된다.** 동기화가 명함을
/// **id로만** 맞추는데, 기기마다 등록하면 id가 달라 **둘 다 살아남는다.**
/// 삭제 전파(tombstone)는 제대로 있는데 **중복 합치기가 없다.**
///
/// 📌 **사고가 아니라 정상 경로다** — 폰과 태블릿을 같이 쓰면 그냥 일어난다.
///
/// ## 🚨 그런데 자동으로 합치지 않는다
///
/// 2026-08-28 하루에 합치기에서 **세 번 데었다** — 사진을 버렸고(추가 552),
/// 이력을 버렸고(추가 553), 빈 값으로 덮었다. **셋 다 사람이 확인창을 보는
/// 경로였는데도** 그랬다. **동기화는 아무도 안 보는 자리다** — 거기서 자동으로
/// 합치면 **잃어도 모른다.**
///
/// ⭐ 그래서 자동으로 정리하는 것은 **잃을 것이 정의상 없는 경우 하나뿐**이다.
///
/// ```
/// 사람이 읽는 칸이 전부 같다        →  어느 매칭 규칙으로 봐도 같은 사람이다
/// 그 밖의 값이 서로 부딪히지 않는다  →  합쳐도 없어지는 값이 없다
/// ```
///
/// 📌 **이 판정은 매칭 규칙(이름+휴대폰이냐, 더 넓은 그물이냐)의 아래쪽에
/// 있다.** 규칙이 무엇으로 정해지든 이 조건을 통과한 쌍은 같은 사람이다 —
/// 그래서 **규칙 통일을 기다리지 않아도 된다.**
///
/// ⚠️ **여기서 하는 일은 판정뿐이다. 아무것도 바꾸지 않는다.**
library;

import '../../data/models/contact_model.dart';
import 'geo_utils.dart';

/// 사람이 명함에서 읽는 칸들. **이것이 다르면 같은 명함이 아니다.**
///
/// ⚠️ 이름을 포함한다 — [diffContacts]는 이름을 빼지만(같아야 그 화면까지
/// 온다) 여기서는 **두 기기가 각자 읽은 결과를 맞춰 보는 것**이라 이름도 다를
/// 수 있다.
List<String> _printed(ContactModel c) => [
  c.name,
  c.company,
  c.title,
  c.department ?? '',
  c.phone,
  c.officePhone ?? '',
  c.directPhone ?? '',
  c.fax ?? '',
  c.email,
  c.website ?? '',
  c.address ?? '',
  c.addressDetail ?? '',
  c.postalCode ?? '',
].map((v) => v.trim()).toList();

/// **두 값이 부딪히나** — 둘 다 있는데 서로 다르면 부딪힌다.
///
/// 한쪽만 있는 것은 부딪히는 것이 아니다. 합칠 때 **있는 쪽을 살리면** 되고,
/// 그래서 잃는 것이 없다.
bool _clashes(String? a, String? b) {
  final x = (a ?? '').trim();
  final y = (b ?? '').trim();
  if (x.isEmpty || y.isEmpty) return false;
  return x != y;
}

/// 잃을 것 없이 **자동으로 합쳐도 되는 쌍인가.**
///
/// ## 판정
///
/// ```
/// ① 사람이 읽는 칸이 **전부** 같다        (위 [_printed])
/// ② 메모가 부딪히지 않는다                 한쪽만 있으면 살리면 된다
/// ③ 태그·그룹·관심사·대화거리가 부딪히지 않는다
/// ④ 좌표가 부딪히지 않는다
/// ```
///
/// 🚨 **사진(`cardImagePath`)과 「대표 이미지로 사용」은 보지 않는다.**
/// 기기마다 다른 **로컬 값**이라 여기 넣으면 *"두 기기에서 찍었으니 합칠 수
/// 없다"*는 엉뚱한 결론이 난다. 합칠 때 **한쪽에만 있으면 그것을 쓴다**
/// (추가 552에서 사진을 버렸던 그 자리다).
///
/// ⚠️ 시각(`updatedAt`)도 보지 않는다 — 기기마다 다른 것이 당연하다.
///
/// 📌 **한쪽에만 있는 값이 있어도 「같다」로 본다.** 그 값들은 합칠 때 살려야
/// 하고, 살리는 것은 [oneSidedFields]가 알려 준다.
bool isSafeToMergeAutomatically(ContactModel a, ContactModel b) {
  if (a.id == b.id) return false; // 같은 명함이다 — 합칠 것이 없다
  final pa = _printed(a);
  final pb = _printed(b);
  for (var i = 0; i < pa.length; i++) {
    if (pa[i] != pb[i]) return false;
  }
  if (_clashes(a.memo, b.memo)) return false;
  if (_clashesList(a.tags, b.tags)) return false;
  if (_clashesList(a.groupIds, b.groupIds)) return false;
  if (_clashesList(a.interests, b.interests)) return false;
  if (_clashesList(a.talkingPoints, b.talkingPoints)) return false;
  if (_clashesLogs(a.commLogs, b.commLogs)) return false;
  if (_geoClashes(a.geo, b.geo)) return false;
  return true;
}

/// 🚨 **소통 기록은 이 판정에 원래 빠져 있었다** (2026-09-04에 찾음).
///
/// 위 목록이 메모·태그·그룹·관심사·대화거리는 보는데 `commLogs`만 안 봤다.
/// 그런데 **두 기기에서 각자 연락을 기록하면 서로 다른 기록이 쌓인다** —
/// 그 상태로 합치면 한쪽 이력이 사라진다.
///
/// 📌 **이 파일 머리말이 경고한 바로 그 자리다** — *"이력을 버렸다(추가 553)"*.
/// 판정에 넣지 않으면 그 사고가 **동기화라는 아무도 안 보는 자리**에서 난다.
///
/// ⚠️ **합집합으로 섞지 않는다.** 목록 규칙([_clashesList])과 같은 판단이다 —
/// 섞으면 이용자가 만든 적 없는 이력이 된다. 둘 다 값이 있으면 **합치지
/// 않고 사람에게 남긴다.**
bool _clashesLogs(
  List<CommunicationLogModel> a,
  List<CommunicationLogModel> b,
) {
  if (a.isEmpty || b.isEmpty) return false;
  // 기기가 달라도 같은 기록이면 id가 같다(서버에서 내려온 같은 원본).
  final ida = a.map((e) => e.id).toSet();
  final idb = b.map((e) => e.id).toSet();
  return ida.length != idb.length || !ida.containsAll(idb);
}

/// 좌표는 **값으로** 비교한다.
///
/// 🚨 처음 만들 때 [GeoPosition]에 `==`가 없었다 — **값이 같아도 다른 객체면
/// 다르다**고 나왔다. 그대로 뒀으면 **두 기기가 같은 주소를 각자 계산한 흔한
/// 경우**가 「부딪힌다」로 읽혀 **영영 안 합쳐졌다** — 이 함수가 막으려는 것과
/// 정반대다.
///
/// 📌 그때는 `lat`·`lng`를 직접 비교해 피했고, **그 뒤 [GeoPosition]에 `==`를
/// 넣었다**(추가 578). 지금은 `!=` 하나로 충분하지만 **여기서 한 번 데었다는
/// 것**은 남겨 둔다.
bool _geoClashes(GeoPosition? a, GeoPosition? b) {
  if (a == null || b == null) return false;
  return a != b;
}

/// 목록은 **한쪽이 비었으면** 부딪히지 않는다. 둘 다 값이 있으면 **같아야**
/// 한다 — 합치면서 항목을 섞으면 이용자가 만든 적 없는 목록이 된다.
bool _clashesList(List<dynamic> a, List<dynamic> b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

/// 합칠 때 **살려야 하는 값**의 이름들 — 한쪽에만 있는 것.
///
/// 🚨 이것을 안 보고 합치면 **오늘 세 번 데인 그 자리**를 또 밟는다. 부르는
/// 쪽이 무엇을 살려야 하는지 잊지 않도록 판정과 함께 돌려준다.
List<String> oneSidedFields(ContactModel a, ContactModel b) {
  final out = <String>[];
  void chk(String label, Object? x, Object? y) {
    final ex = x == null || (x is String && x.trim().isEmpty) || (x is List && x.isEmpty);
    final ey = y == null || (y is String && y.trim().isEmpty) || (y is List && y.isEmpty);
    if (ex != ey) out.add(label);
  }

  chk('명함 사진', a.cardImagePath, b.cardImagePath);
  chk('메모', a.memo, b.memo);
  chk('좌표', a.geo, b.geo);
  chk('태그', a.tags, b.tags);
  chk('그룹', a.groupIds, b.groupIds);
  chk('관심사', a.interests, b.interests);
  chk('대화거리', a.talkingPoints, b.talkingPoints);
  chk('소통 기록', a.commLogs, b.commLogs);
  return out;
}

/// [isSafeToMergeAutomatically]가 참인 두 명함을 **하나로 접는다.**
///
/// ## 🚨 이 함수가 없어서 판정기가 놀고 있었다
///
/// 판정기는 2026-08-29에 만들어졌는데(추가 572), **`lib/` 안에서 부르는 곳이
/// 0건**이었다(2026-09-04 실측 — 테스트만 불렀다). 판정만 있고 **합치는 손이
/// 없었다.** 이 저장소가 반복해서 겪은 모양이다(추가 79 — 서비스는 정상,
/// 부르는 쪽이 없음).
///
/// ## 어느 쪽을 남기나 — **id 사전순으로 작은 쪽**
///
/// 🚨 **기기마다 같은 답이 나와야 한다.** 「최신 것」으로 정하면 기기마다
/// `updatedAt`이 달라 **폰과 태블릿이 서로 다른 쪽을 남긴다** — 그러면 접어도
/// 중복이 안 없어진다. 사전순은 어디서 재도 같다.
///
/// 📌 **어느 쪽을 남겨도 내용은 같다** — 판정기가 *"사람이 읽는 칸이 전부
/// 같다"*를 이미 보장한다. 다른 것은 **한쪽에만 있는 값**뿐이고, 그것을 여기서
/// 살린다.
///
/// ⚠️ **`??`가 아니라 「빈 값이면 채운다」로 판단한다** — 빈 문자열은 `null`이
/// 아니라서 `??`로는 안 걸린다.
ContactModel mergeIdentical(ContactModel a, ContactModel b) {
  final (keep, drop) = a.id.compareTo(b.id) <= 0 ? (a, b) : (b, a);

  bool blank(Object? v) =>
      v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

  return keep.copyWith(
    cardImagePath:
        blank(keep.cardImagePath) ? drop.cardImagePath : keep.cardImagePath,
    memo: blank(keep.memo) ? drop.memo : keep.memo,
    geo: keep.geo ?? drop.geo,
    tags: blank(keep.tags) ? drop.tags : keep.tags,
    groupIds: blank(keep.groupIds) ? drop.groupIds : keep.groupIds,
    interests: blank(keep.interests) ? drop.interests : keep.interests,
    talkingPoints:
        blank(keep.talkingPoints) ? drop.talkingPoints : keep.talkingPoints,
    commLogs: blank(keep.commLogs) ? drop.commLogs : keep.commLogs,
    // 내용이 같으므로 시각은 **더 최신**을 쓴다 — 다음 병합에서 이 결과가
    // 옛것으로 밀리지 않게 한다.
    //
    // ⚠️ `updatedAt`은 nullable이다. 한쪽만 있으면 그것을 쓰고, 둘 다 없으면
    // 그대로 둔다 — 없는 것을 지어내지 않는다.
    updatedAt: _laterOf(keep.updatedAt, drop.updatedAt),
  );
}

DateTime? _laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
