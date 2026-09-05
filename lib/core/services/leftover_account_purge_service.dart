import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_image_service.dart';
import 'encryption_key_service.dart';

/// 계정을 바꿨을 때 이 기기에 남는 **이전 계정의 명함 사진**을 30일 뒤에
/// 지운다(추가 522, globe2030님 결정 2026-08-27).
///
/// > *"계정 전환 시 기존 명함이 삭제 된다고 안내를 하고 삭제하는 것으로 진행.
/// > 다만, 사용자 실수를 염두하고 있어야 하니까. 30일 뒤에 삭제하는 것으로
/// > 한다."*
///
/// 설계 문서: `docs/planning/specs/account-switch-card-deletion-2026-08-27.md`
/// 법무 검토: `docs/legal-drafts/reviews/account-switch-30day-deletion-2026-08-27.md`
///
/// ## 🚨 30일은 「삭제를 미루는 기간」이 아니라 「복구 경로」다
///
/// 이 유예의 핵심은 지연이 아니다. **30일 안에 원래 계정으로 다시 로그인하면
/// 예약이 취소되고 사진이 그대로 살아난다** — 계정을 잘못 바꾼 사람이 명함을
/// 통째로 잃지 않게 하는 장치다. 그래서 [cancelFor]가 이 서비스의 절반이다.
///
/// ⚠️ **30일이 복구 가능 기간의 한계가 아니다.** 이전 계정의 서버 백업
/// (Firestore 텍스트 · Cloud Storage 사진)은 **이 서비스가 절대 건드리지
/// 않는다.** 몇 년 뒤에 그 계정으로 로그인해도 복원된다. 30일이 지나 지워지는
/// 것은 **이 기기에 남은 사본**뿐이고, 그 사이에 돌아오면 네트워크 없이도
/// 즉시 붙는다(`relinkMissingCardImagePaths`).
///
/// ## 무엇을 지우나 — 이 기기의 것만
///
/// | 지운다 | 안 지운다 |
/// |---|---|
/// | `contact_card_<id>.enc` (앱 문서 폴더) | Firestore `users/{uid}/contacts` |
/// | `enc_key_v1_<uid>` (secure storage) | Cloud Storage `users/{uid}/cards` |
///
/// 🚨 **서버를 지우면 「기기 정리」가 아니라 「A 몰래 A의 계정을 건드리는 일」이
/// 된다.** A가 다른 기기에서 멀쩡히 쓰고 있을 수 있다. 그래서
/// [ContactImageService.deleteCardImage]를 **uid 없이** 부른다 — uid를 넘기면
/// 그 함수가 서버 객체와 백업 장부까지 지운다.
///
/// ## ⚠️ 내 프로필 사진(`_my_profile_card`)은 대상이 아니다
///
/// 내 명함 사진은 **계정과 무관한 고정 파일명**을 쓴다
/// (`ContactImageService.myProfileCardId`). A와 B가 **같은 파일을 공유**하므로,
/// 이것을 예약에 넣으면 **B가 그 사이에 저장한 자기 프로필 사진을 30일 뒤에
/// 지워버린다.** [schedule]과 [_purgeOne] 양쪽에서 막는다 — 한쪽이 뚫려도
/// 다른 쪽이 잡게 이중으로 둔다.

class LeftoverAccountPurgeService {
  LeftoverAccountPurgeService({
    ContactImageService? imageService,
    EncryptionKeyService? keyService,
  }) : _imageService = imageService ?? ContactImageService(),
       _keyService = keyService ?? EncryptionKeyService();

  final ContactImageService _imageService;
  final EncryptionKeyService _keyService;

  /// 예약 장부를 담는 키.
  ///
  /// 값은 `{uid: {"contactIds": [...], "scheduledAt": ISO8601}}` 꼴이다.
  /// **uid와 명함 id(UUID)뿐이라 명함 주인의 개인정보가 들어가지 않는다** —
  /// 이름·전화·주소는 한 글자도 담지 않으므로 평문 `shared_preferences`에
  /// 둬도 규약 4절(개인정보를 평문 저장소에 넣지 않는다)에 걸리지 않는다.
  static const String prefsKey = 'pending_leftover_card_photo_purge_v1';

  /// 유예 기간. 사용자 결정값이며 법정 기한이 아니다.
  static const Duration delay = Duration(days: 30);

  static const String _fieldContactIds = 'contactIds';
  static const String _fieldScheduledAt = 'scheduledAt';

  /// 이전 계정([uid])의 사진을 [delay] 뒤에 지우도록 예약한다.
  ///
  /// [contactIds]는 **로컬을 비우기 직전에** 캡처한 명함 id 집합이다 —
  /// 비운 뒤에 부르면 목록이 이미 비어 있어 아무것도 예약되지 않는다.
  ///
  /// 같은 uid로 다시 예약하면 **덮어쓴다.** A→B→A→C처럼 여러 번 전환해도
  /// 장부가 무한히 자라지 않고, 마지막 전환 시점 기준으로 30일이 다시 잡힌다.
  Future<void> schedule({
    required String uid,
    required List<String> contactIds,
    DateTime? now,
  }) async {
    final targets = contactIds
        .where((id) => id.isNotEmpty && id != ContactImageService.myProfileCardId)
        .toSet()
        .toList();
    if (uid.isEmpty || targets.isEmpty) return;

    final at = (now ?? DateTime.now()).toUtc().add(delay);
    final book = await _load();
    book[uid] = {
      _fieldContactIds: targets,
      _fieldScheduledAt: at.toIso8601String(),
    };
    await _save(book);
  }

  /// [uid]의 예약을 취소한다 — **로그인 자체가 취소 행위다.**
  ///
  /// 원래 계정으로 돌아온 사람에게 "취소" 버튼을 따로 누르게 하지 않는다.
  /// 실수로 계정을 바꿨어도 다시 로그인만 하면 아무 일도 없었던 것이 된다.
  Future<bool> cancelFor(String uid) async {
    if (uid.isEmpty) return false;
    final book = await _load();
    if (book.remove(uid) == null) return false;
    await _save(book);
    return true;
  }

  /// 유예를 기다리지 않고 **지금** 지운다.
  ///
  /// 법무 검토 ③ 요소 6(*"지금 바로 지우는 길"*)이다 — 개인정보 보호법
  /// §36(삭제 요구)의 실질적 통로가 없으면 *"왜 30일이나 붙잡느냐"*에 답할
  /// 수단이 없다.
  ///
  /// 🚨 **되돌릴 수 없다.** 부르는 쪽에서 한 번 더 확인을 받을 것.
  Future<void> purgeNow({
    required String uid,
    required List<String> contactIds,
  }) async {
    if (uid.isEmpty) return;
    await _purgeOne(uid, contactIds);
    await cancelFor(uid);
  }

  /// 대기 중인 예약 전부. 설정 화면이 「이전 계정 데이터」 행을 그릴 때 쓴다
  /// (법무 검토 ③-(나): **다이얼로그는 한 번 지나가면 다시 볼 수 없으므로**,
  /// 유예 중임을 계속 볼 수 있는 자리가 있어야 한다).
  ///
  /// 📌 **장수까지 돌려준다** — 법무 검토 ③ 요소 2 가 *"무엇이 지워지는지
  /// (이 기기의 명함 N장·사진 M장)"* 를 요구한다. 「데이터가 있습니다」로는
  /// 이용자가 무엇을 잃는지 가늠할 수 없다.
  Future<List<PendingLeftoverPurge>> pending() async {
    final book = await _load();
    final out = <PendingLeftoverPurge>[];
    book.forEach((uid, entry) {
      final at = _readScheduledAt(entry);
      if (at == null) return;
      out.add(
        PendingLeftoverPurge(
          uid: uid,
          scheduledAt: at,
          contactIds: _readContactIds(entry),
        ),
      );
    });
    out.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return out;
  }

  /// 예약된 uid 와 각 예정 시각만 필요한 곳을 위한 얇은 겉면.
  Future<Map<String, DateTime>> pendingSchedules() async => {
    for (final p in await pending()) p.uid: p.scheduledAt,
  };

  /// 만기가 지난 예약을 실행한다. 지운 계정 수를 돌려준다.
  ///
  /// 🚨 [currentUid]는 **절대 지우지 않는다.** 지금 로그인한 계정의 사진을
  /// 실수로 지우면 이 기능 전체의 신뢰가 깨진다. 그래서 [runDue]가 시작할 때
  /// 그 uid의 예약을 **먼저 취소**하고(돌아온 사람이므로 취소가 맞다),
  /// 삭제 루프에서도 한 번 더 건너뛴다.
  ///
  /// ⚠️ **정확히 30일에 도는 것이 아니라 「30일이 지난 뒤 다음 실행 시점」에
  /// 돈다.** 앱을 안 켜면 그만큼 늦다. 백그라운드 작업을 붙이면 정확해지지만
  /// 새 의존성이 필요해 범위 밖으로 뒀다(설계 문서 3절).
  ///
  /// ## 🚨 「계정 잇기」를 만들 때 **여기가 갈림길이다**
  ///
  /// 지금 [currentUid]는 **uid 하나**다. 이 서비스 전체가 *"uid 가 다르면
  /// 남남"*이라는 전제 위에 서 있기 때문이다(2026-09-04 결정 — 계정마다
  /// 데이터가 유일하다).
  ///
  /// ⚠️ **「한 사람 = 한 계정 + 휴대폰」**(추가 557 결정 ①, 검토 중)이 켜져
  /// 두 계정을 한 사람으로 잇게 되면 그 전제가 무너진다. 그때 이 한 줄을
  /// 안 고치면 **이어 놓은 계정의 사진이 30일 뒤에 조용히 사라진다** —
  /// 예약은 이미 잡혀 있고, 잇기는 그것을 모른다.
  ///
  /// 📌 그때 [currentUid]는 **「같은 사람의 uid 집합」**이 되어야 한다.
  ///
  /// ## 🚨 그런데 여기만 고치면 안 된다 (2026-09-05 정정)
  ///
  /// C안(사람 레이어)이 확정되면서 고칠 곳이 **셋**으로 늘었다. 이 주석은
  /// 원래 여기 한 곳만 지목했는데, **그것만 고치면 예약 취소는 되지만 로컬은
  /// 여전히 매번 비워진다** — 잇기의 본래 목적이 실패한다.
  ///
  /// ```
  /// ① auth_gate.dart:171   lastUid != uid  →  lastPersonId != personId
  ///                        🚨 진짜 판정 자리다. 여기와 runDue 는 별개 함수다
  /// ② runDue(currentUid:)  uid 하나 → 그 사람의 uid 집합
  /// ③ 잇는 시점            그 personId 의 uid 전부의 기존 예약을 취소
  /// ```
  ///
  /// ⚠️ **③이 왜 필요한가**: 두 계정이 **잇기 전에 각자 계정 전환을 겪어**
  /// 예약이 이미 걸려 있을 수 있다. 그 상태로 한 사람이 되면 **지금 로그인하지
  /// 않은 쪽 uid 의 예약은 살아남는다** — [runDue]는 로그인 중인 uid 하나만
  /// 취소하기 때문이다(아래 `book.remove(currentUid)`).
  ///
  /// ⭐ **3단계(잇기 동작)와 이 정정을 같은 PR 로 묶어야 한다.** 3단계가
  /// 배포된 순간부터 그 경로를 타는 일이 실제로 생긴다.
  ///
  /// 경위와 표는 `docs/planning/specs/account-switch-card-deletion-2026-08-27.md`
  /// 5-1 절에 있다.
  ///
  /// ⭐ **그 신호는 여기가 아니라 저쪽에서 먼저 온다** —
  /// `EncryptionKeyService.knownKeysFor` 가 **키를 둘 이상 돌려주기 시작하는
  /// 날**이다(키링, 2026-09-04에 자리만 미리 냈다). 그 함수에 두 번째 키가
  /// 들어가면, 이 서비스는 그 키를 **「이전 계정 것」으로 보고 30일 뒤에
  /// 지운다** — 그러면 잇기로 열리게 만든 명함이 다시 안 열린다.
  ///
  /// 🚨 **두 자리를 같은 날 고쳐야 한다.** 한쪽만 고치면 조용히 어긋나고,
  /// **30일 뒤에야 드러난다.**
  Future<int> runDue({String? currentUid, DateTime? now}) async {
    final book = await _load();
    if (book.isEmpty) return 0;

    var changed = false;
    if (currentUid != null && currentUid.isNotEmpty) {
      if (book.remove(currentUid) != null) changed = true;
    }

    final at = (now ?? DateTime.now()).toUtc();
    var purged = 0;
    for (final uid in book.keys.toList()) {
      if (uid == currentUid) continue; // 이중 안전장치
      final entry = book[uid];
      final due = _readScheduledAt(entry);
      if (due == null) {
        // 형식이 깨진 항목은 지운다 — 남겨 두면 영원히 안 지워지는 채로
        // 장부만 자란다.
        book.remove(uid);
        changed = true;
        continue;
      }
      if (at.isBefore(due)) continue;

      await _purgeOne(uid, _readContactIds(entry));
      book.remove(uid);
      changed = true;
      purged++;
    }

    if (changed) await _save(book);
    return purged;
  }

  Future<void> _purgeOne(String uid, List<String> contactIds) async {
    for (final id in contactIds) {
      if (id.isEmpty || id == ContactImageService.myProfileCardId) continue;
      try {
        final path = await _imageService.canonicalPath(id);
        if (path == null) continue;
        // 🚨 uid를 넘기지 않는다 — 넘기면 서버 사진과 백업 장부까지 지운다.
        //    지울 것은 이 기기의 파일뿐이다.
        await _imageService.deleteCardImage(path);
      } catch (e) {
        // 한 장이 실패해도 나머지는 계속 지운다. 남은 파일은 다음 실행에
        // 다시 시도되지 않으므로(항목을 지우기 때문에) 완벽하지는 않지만,
        // 여기서 멈추면 더 많이 남는다.
        debugPrint('이전 계정 사진 삭제 실패: ${e.runtimeType}');
      }
    }
    try {
      await _keyService.deleteLocalKey(uid);
    } catch (e) {
      debugPrint('이전 계정 로컬 키 삭제 실패: ${e.runtimeType}');
    }
  }

  DateTime? _readScheduledAt(Object? entry) {
    if (entry is! Map) return null;
    final raw = entry[_fieldScheduledAt];
    if (raw is! String) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  List<String> _readContactIds(Object? entry) {
    if (entry is! Map) return const [];
    final raw = entry[_fieldContactIds];
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      // 못 읽으면 **아무것도 지우지 않는다.** 읽기 실패를 "예약 없음"으로
      // 읽는 것이 안전한 방향이다 — 반대로 지워 버리면 되돌릴 수 없다.
      debugPrint('이전 계정 삭제 예약 조회 실패: ${e.runtimeType}');
      return {};
    }
  }

  Future<void> _save(Map<String, dynamic> book) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (book.isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, jsonEncode(book));
      }
    } catch (e) {
      debugPrint('이전 계정 삭제 예약 저장 실패: ${e.runtimeType}');
    }
  }
}


/// 아직 지우지 않은 이전 계정 하나의 예약.
class PendingLeftoverPurge {
  const PendingLeftoverPurge({
    required this.uid,
    required this.scheduledAt,
    required this.contactIds,
  });

  /// 이전 계정의 uid. ⚠️ **화면에 그대로 보여 주지 않는다** — 이용자에게
  /// 아무 의미가 없는 값이고, 그렇다고 이메일을 보여 줄 수도 없다(우리가
  /// 가진 것은 uid 뿐이다).
  final String uid;

  /// 이 시각이 지나면 지운다(UTC).
  final DateTime scheduledAt;

  /// 지울 명함 id 들. 길이가 곧 「사진 몇 장」이다.
  final List<String> contactIds;

  int get photoCount => contactIds.length;
}
