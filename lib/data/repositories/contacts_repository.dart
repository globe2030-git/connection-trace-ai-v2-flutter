import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/contact_image_service.dart';
import '../../core/services/data_crypto_service.dart';
import '../../core/services/encryption_key_service.dart';
import '../../core/services/geo_backfill_service.dart';
import '../models/contact_model.dart';
import '../services/data_backup_service.dart';

class ContactsRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_contacts_v2';

  // 예전엔 여기에 가짜 인맥 3명(김민준/한소율/오현우)을 하드코딩해서 앱을
  // 처음 켜면 마치 실제 등록된 인맥인 것처럼 보여줬다 — 사용자가 "가짜
  // 데이터를 보여주지 말고 실제 연동되는 자료 기반으로 진행해"라고 요청해
  // 제거. 이제 실제로 명함을 스캔하거나 QR로 교환하기 전까지는 빈
  // 목록으로 시작한다.
  List<ContactModel> _contacts = [];

  // 로그인된 사용자의 Firebase uid — 서버 백업 대상 식별용. AuthGate가
  // 로그인/로그아웃 시점에 설정한다. null이면 서버 백업을 시도하지 않는다
  // (게스트 QA 로그인, 또는 Firebase Auth 연동이 실패한 경우).
  String? _uid;

  // 명함 데이터(제3자 개인정보)는 로컬 저장 시와 서버 백업 시 모두
  // AES-256-GCM으로 암호화한다(사용자 요청 — adb로 shared_preferences를
  // 직접 열어보면 평문이 그대로 읽히는 문제가 확인됨). 암호화 키는 uid별로
  // 발급되므로 로그인 전(uid == null)에는 암호화를 걸 수 없다 — 이 경우
  // 게스트 상태로 간주해 평문으로 저장한다(로그인 전에는 서버 백업도 되지
  // 않는 상태라 상대적으로 노출 범위가 좁고, 로그인하는 즉시 아래
  // 마이그레이션 로직으로 자동 암호화된다).
  final EncryptionKeyService _encryptionKeyService;

  // 좌표는 서버에 백업하지 않는다(backlog 추가 75, C안). 기기를 바꾸거나
  // 계정을 다시 연결해 서버에서 복원하면 좌표가 빈 채로 내려오므로, 주소로
  // 다시 계산해 채워 넣는 역할을 이 서비스가 맡는다.
  final GeoBackfillService _geoBackfillService;

  // cardImagePath도 좌표와 같은 이유로 서버 백업에 포함하지 않는다(다른
  // 기기에선 무의미한 로컬 경로). 서버 복원/다기기 병합이 로컬을 덮어쓰면
  // 경로만 유실되고 기기에 저장된 암호문 파일(contact_card_<id>.enc)은
  // 남아 있으므로, 파일명 규칙으로 다시 이어붙이는 역할을 이 서비스가 맡는다.
  final ContactImageService _contactImageService;

  // 좌표 재계산 진행 상태 — 복원 직후에는 거리 계산이 안 되는 구간이
  // 생기므로 화면에서 "준비 중"을 보여줄 수 있게 노출한다.
  bool _isBackfillingGeo = false;
  int _geoBackfillDone = 0;
  int _geoBackfillTotal = 0;

  // 서버 백업에서 좌표를 걷어내는 1회성 마이그레이션이 진행 중인지.
  bool _strippingGeoBackups = false;

  // 앱 시작 직후(uid를 아직 모를 때) 로드를 시도했는데 저장된 값이
  // 암호화된 형태라 열지 못한 경우 true. 이후 [setCurrentUid]로 실제
  // uid가 들어오면 그 시점에 다시 로드를 시도한다.
  bool _pendingEncryptedLoad = false;

  // 레거시 평문 데이터를 uid 없이(게스트 상태로) 읽어들인 경우 true.
  // 로그인 완료 후 uid가 생기면 그 시점에 즉시 암호화해서 재저장한다.
  bool _pendingPlaintextMigration = false;

  ContactsRepository({
    EncryptionKeyService? encryptionKeyService,
    GeoBackfillService? geoBackfillService,
    ContactImageService? contactImageService,
  }) : _encryptionKeyService = encryptionKeyService ?? EncryptionKeyService(),
       _geoBackfillService = geoBackfillService ?? GeoBackfillService(),
       _contactImageService = contactImageService ?? ContactImageService() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  /// 좌표 재계산이 진행 중인지. 복원 직후 주변 인맥 목록이 비어 보이는 구간을
  /// 화면에서 설명하기 위해 쓴다.
  bool get isBackfillingGeo => _isBackfillingGeo;
  int get geoBackfillDone => _geoBackfillDone;
  int get geoBackfillTotal => _geoBackfillTotal;

  Future<void> setCurrentUid(String? uid) async {
    _uid = uid;
    if (uid == null) return;
    if (_pendingEncryptedLoad) {
      _pendingEncryptedLoad = false;
      await _loadFromDisk();
    } else if (_pendingPlaintextMigration) {
      _pendingPlaintextMigration = false;
      await _saveToDisk();
    }
    // ⚠️ **여기서 서버로 아무것도 쓰지 않는다.** 예전에는 이 자리에서
    // `_stripGeoFromServerBackupsOnce`와 `backfillMissingGeo`를 `unawaited`로
    // 띄웠는데, 그것이 **계정 전환 유출의 원인**이었다 — 아래 주석 참고.
    // 두 작업은 계정 동기화 결정이 끝난 뒤 [runPostSyncMaintenance]가 부른다.
  }

  /// 로그인 뒤 뒤처리 — **계정 동기화 결정이 끝난 다음에만** 부른다.
  ///
  /// ## ⚠️ 왜 로그인 시점에서 여기로 옮겼나 (2026-08-21)
  ///
  /// 예전에는 [setCurrentUid]가 이 둘을 `unawaited`로 띄웠다. 그런데
  /// `AuthGate`는 uid를 알린 **뒤에** "교체할까요 유지할까요?" 를 묻는다.
  /// 즉 **이용자가 무엇을 고르든 그 전에 업로드가 시작됐다.**
  ///
  /// ```
  /// setCurrentUid(B) ──→ (기다리지 않고) A의 명함을 B의 서버로 올림
  ///                          ⋮ 동시에
  /// 다음 프레임      ──→ "교체할까요, 유지할까요?"
  /// ```
  ///
  /// ⚠️ **"교체"를 고른 이용자에게도 일어났다.** 이용자가 *"이전 계정
  /// 데이터를 쓰지 않겠다"* 고 명시적으로 밝혔는데도 그 데이터가 새 계정의
  /// 서버 문서로 올라갔다. 완료 플래그가 계정별이라 **계정을 바꿀 때마다**
  /// 다시 돌았다.
  ///
  /// ⚠️ 명함은 **제3자(명함 주인)의 개인정보**다. 두 계정이 다른 사람이면
  /// 근거 없는 제3자 제공이 된다.
  ///
  /// 📌 좌표 백필도 함께 미룬다. 로컬에만 쓰지만 **주소를 외부 지오코더로
  /// 보낸다** — 곧 버릴 계정의 명함 주소를 굳이 밖으로 내보낼 이유가 없다.
  ///
  /// [skipServerMigration]이 참이면 서버로 다시 올리는 일회성 마이그레이션을
  /// **건너뛴다.** 계정 전환에서 "유지"를 고른 경우가 그렇다 — 그 명함들은
  /// 이 계정이 수집한 것이 아니므로 통째로 올려서는 안 된다.
  Future<void> runPostSyncMaintenance({bool skipServerMigration = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (!skipServerMigration) {
      // 좌표를 서버에서 빼기 전에 올라간 문서에는 암호문 안에 좌표가 남아
      // 있다. 계정당 한 번 전체를 다시 올려 지운다.
      unawaited(_stripGeoFromServerBackupsOnce(uid));
    }
    // 복원 때 지오코딩에 실패한 명함이 남아 있을 수 있다(일시적 네트워크
    // 오류, 지오코더 호출 제한 등). 복원 경로에서만 재시도하면 복원이 다시
    // 일어나지 않는 한 영영 재시도되지 않고, 그 명함은 좌표가 없어 주변
    // 인맥 목록에서 조용히 빠진 채로 남는다(실기기에서 확인 — 추가 79).
    // 남은 게 없으면 즉시 반환하므로 비용은 거의 없다.
    unawaited(backfillMissingGeo());
  }

  /// 새 기기(또는 재설치)에서 로그인한 뒤 로컬 명함 목록이 비어있을 때만
  /// 서버 백업분을 통째로 내려받는다 — 이미 로컬에 데이터가 있으면 덮어쓰지
  /// 않는다(사용자가 계속 쓰던 기기에서 실수로 서버 데이터로 갈아치우는
  /// 사고 방지).
  Future<void> restoreFromServerIfEmpty(String uid) async {
    if (_contacts.isNotEmpty) return;
    final restored = await DataBackupService.restoreContacts(uid);
    if (restored.isEmpty) return;
    _contacts = restored;
    // 서버 백업엔 cardImagePath가 없다 — 기기에 남은 암호문 파일과 다시
    // 잇는다(추가 - 명함 이미지 경로 일괄 재연결). 저장은 아래 한 번으로 합친다.
    await relinkMissingCardImagePaths();
    notifyListeners();
    await _saveToDisk();
    // 복원 시점에는 서버 문서에 좌표가 남아 있을 수 있다 — 여기서 한 번 더
    // 정리 기회를 준다(setCurrentUid 시점에는 로컬이 비어 있어 건너뛴다).
    unawaited(_stripGeoFromServerBackupsOnce(uid));
    // 서버에서 내려온 명함에는 좌표가 없다 — 주소로 다시 계산해 채운다.
    // 지오코딩은 건당 최대 10초라 로그인 흐름을 막지 않도록 기다리지 않는다.
    unawaited(backfillMissingGeo());
  }

  /// 계정 전환 안전장치(backlog #50)에서 사용자가 "현재 계정 데이터로
  /// 교체"를 선택했을 때 쓰는 강제 복원 — [restoreFromServerIfEmpty]와
  /// 달리 로컬에 데이터가 있어도 무시하고 서버 백업분으로 덮어쓴다(서버에
  /// 백업분이 없으면 빈 목록이 된다). 호출 전에 [clearLocal]로 먼저 이전
  /// 계정 데이터를 지우는 것을 전제로 한다.
  Future<void> forceRestoreFromServer(String uid) async {
    final restored = await DataBackupService.restoreContacts(uid);
    _contacts = restored;
    // 서버 백업엔 cardImagePath가 없다 — 기기에 남은 암호문 파일과 다시 잇는다.
    await relinkMissingCardImagePaths();
    notifyListeners();
    await _saveToDisk();
    unawaited(_stripGeoFromServerBackupsOnce(uid));
    unawaited(backfillMissingGeo());
  }

  /// 명함의 "최신 시각" — 다기기 병합의 last-write-wins 기준. updatedAt이 없는
  /// 예전 데이터는 "가장 오래됨"(epoch)으로 취급해, 이후 어떤 실제 편집이든 이긴다.
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _updatedAtOf(ContactModel c) => c.updatedAt ?? _epoch;

  /// 다기기 동기화(P1-39 A안)의 핵심 병합 — **순수 함수라 단위 테스트로 고정**한다.
  ///
  /// - [local]: 이 기기 명함(좌표 포함)
  /// - [server]: 서버 백업 명함(좌표 없음, updatedAt 포함)
  /// - [tombstones]: `{id: deletedAt}` 삭제 기록
  ///
  /// 규칙(전부 결정적):
  /// - 같은 id가 양쪽에 있으면 updatedAt이 더 최신인 쪽 채택(편집 전파, LWW).
  ///   같으면 서버 쪽을 채택(불필요한 재업로드 방지).
  /// - 한쪽에만 있으면 그걸 채택(추가 전파, 오프라인 로컬 보존).
  /// - 삭제 기록이 채택본보다 최신이면 제거(삭제 전파). 삭제 이후 다시 편집한
  ///   건(updatedAt이 삭제보다 최신)은 살아남는다(부활).
  ///
  /// 반환:
  /// - `merged`: 로컬에 저장할 최종 목록(updatedAt 내림차순).
  /// - `toPush`: 서버로 올려야 할 것(로컬에만 있거나 로컬이 더 최신 — 손실 방지·편집 전파 완성).
  static ({List<ContactModel> merged, List<ContactModel> toPush}) mergeSync({
    required List<ContactModel> local,
    required List<ContactModel> server,
    required Map<String, DateTime> tombstones,
  }) {
    final localById = {for (final c in local) c.id: c};
    final serverById = {for (final c in server) c.id: c};
    final allIds = <String>{...localById.keys, ...serverById.keys};

    final merged = <ContactModel>[];
    final toPush = <ContactModel>[];

    for (final id in allIds) {
      final l = localById[id];
      final s = serverById[id];

      ContactModel candidate;
      final bool fromLocal;
      if (l != null && s != null) {
        if (_updatedAtOf(l).isAfter(_updatedAtOf(s))) {
          candidate = l;
          fromLocal = true;
        } else {
          candidate = s;
          fromLocal = false;
        }
      } else if (l != null) {
        candidate = l;
        fromLocal = true;
      } else {
        candidate = s!;
        fromLocal = false;
      }

      final tomb = tombstones[id];
      if (tomb != null && tomb.isAfter(_updatedAtOf(candidate))) {
        // 다른 기기의 삭제가 이 후보보다 최신 → 제거(로컬·서버 어디에도 안 남김).
        continue;
      }

      // ⚠️ 좌표는 LWW 판단에서 뺀다(추가 435). 서버 백업엔 좌표가 애초에
      // 없다(toBackupJson이 뺀다, 추가 76) — 그래서 `candidate`가 서버 것으로
      // 뽑히면 항상 geo가 null이다. 문제는 **좌표만 갱신됐을 때**(백필
      // 성공)도 생긴다: `GeoBackfillService.backfill`의 `onResolved`는
      // `copyWith(geo:)`만 하고 `updatedAt`은 건드리지 않는다(좌표는 파생값이라
      // "편집"이 아니라는 의도). 그 결과 local.updatedAt == server.updatedAt
      // 동률이 되고, 동률은 서버 쪽을 채택하므로(위 `isAfter` 분기) **방금
      // 백필로 채운 좌표가 다음 로그인(콜드 스타트)의 syncWithServer에서
      // 즉시 지워졌다.** 실기기 증상: 백필 진행 배너는 30/30으로 완주하는데
      // 좌표 없는 명함 수가 여러 회차(콜드 실행)를 거쳐도 한 장도 안 줄고,
      // 그러니 3회 실패 "포기"도 전혀 쌓이지 않았다(성공은 실패가 아니므로) —
      // 콜드 스타트마다 이전 회차의 성공분이 병합 시점에 조용히 사라지고,
      // 다음 백필이 같은 명함을 또 성공시키는 것을 반복했을 뿐이었다.
      // 좌표는 이 함수의 판단 기준(내용 최신성)과 무관한 기기 로컬 파생값이니
      // 병합 결과가 어느 쪽 내용을 택하든 로컬에 있으면 항상 붙여 둔다.
      //
      // ⚠️ 단, **주소가 같을 때만** 이식한다(PM 검토, 추가 435 보강). 서버
      // 후보가 채택됐는데 그 주소가 로컬과 다르면(다른 기기에서 주소를
      // 고친 경우) 로컬 좌표는 **옛 주소**로 계산된 값이다 — 새 주소에는
      // 안 맞는 좌표인데, geo가 채워져 있으면 `GeoBackfillService`가
      // "이미 있음"으로 보고 재계산을 안 한다(`_needsGeo`). 그러면 틀린
      // 좌표가 지도에 영구히 남는다. 주소가 다르면 이식하지 않고 새
      // 주소의 재계산(백필)에 맡긴다.
      final localGeo = l?.geo;
      if (localGeo != null &&
          candidate.geo == null &&
          l!.address?.trim() == candidate.address?.trim()) {
        candidate = candidate.copyWith(geo: localGeo);
      }

      merged.add(candidate);
      // 로컬에만 있거나 로컬이 더 최신이면 서버로 올려 손실을 막고 편집을 전파한다.
      if (fromLocal) toPush.add(candidate);
    }

    merged.sort((a, b) => _updatedAtOf(b).compareTo(_updatedAtOf(a)));
    return (merged: merged, toPush: toPush);
  }

  /// 다기기 동기화(P1-39 A안) — [mergeSync]를 서버 데이터에 적용한다.
  ///
  /// ⚠️ 반드시 로컬 복호화 로드가 끝난 뒤 불러야 한다 — 로그인 시 `setCurrentUid`
  /// (복호화 재로드)를 **기다린 뒤** 이 메서드를 부르도록 `auth_gate`가 순서를
  /// 보장한다. 안 그러면 로드가 끝나기 전 로컬을 "비었다"고 오판해, 서버로
  /// 통째로 덮어쓰고 오프라인 로컬 데이터를 잃을 수 있다(2026-08-09 실기기에서
  /// 확인된 경합, 추가 120).
  Future<void> syncWithServer(String uid) async {
    final List<ContactModel> serverContacts;
    final Map<String, DateTime> tombstones;
    try {
      serverContacts = await DataBackupService.restoreContacts(uid);
      tombstones = await DataBackupService.fetchTombstones(uid);
    } catch (_) {
      // 네트워크 실패 등 — 로컬은 그대로 두고 다음 로그인에 다시 시도.
      return;
    }
    final outcome = mergeSync(
      local: _contacts,
      server: serverContacts,
      tombstones: tombstones,
    );
    _contacts = outcome.merged;
    // 병합에서 서버 쪽 사본이 채택된 명함은 cardImagePath가 없다(서버 백업엔
    // 애초에 안 담기므로) — 기기에 남은 암호문 파일과 다시 잇는다.
    await relinkMissingCardImagePaths();
    notifyListeners();
    await _saveToDisk();
    // 로컬에만 있거나 로컬이 더 최신인 명함을 서버로 올린다(손실 방지·편집 전파).
    for (final c in outcome.toPush) {
      unawaited(DataBackupService.backupContact(uid, c));
    }
    // 서버 백업엔 좌표가 없으므로(C안) 좌표 없는 명함의 좌표를 주소로 채운다.
    unawaited(backfillMissingGeo());
  }

  /// 주소는 있는데 좌표가 없는 명함들의 좌표를 주소로부터 다시 계산해 채운다.
  ///
  /// 좌표를 서버에 백업하지 않기로 했기 때문에(backlog 추가 75, C안) 기기를
  /// 바꾸거나 계정을 다시 연결해 복원하면 좌표가 빈 상태로 내려온다. 이
  /// 메서드가 그 빈자리를 메운다. 채운 결과는 **기기에만 저장**한다 — 좌표는
  /// 애초에 서버로 보내지 않으므로 재백업할 이유가 없다.
  ///
  /// 실패한 건은 다음 호출에서 다시 시도되며, 반복 실패하면
  /// [GeoBackfillService]가 알아서 포기한다. 호출자는 결과를 기다릴 필요가
  /// 없다(진행 상황은 [isBackfillingGeo]로 관찰).
  ///
  /// ⚠️ **회차 끝이 아니라 한 건 풀릴 때마다 즉시 저장한다**(추가 434). 예전엔
  /// [GeoBackfillService.backfill]이 완전히 반환한 뒤에야 결과를 한꺼번에
  /// 적용·저장했다 — 실기기 실측(QA가 `am force-stop`으로 두 번 재현)에서
  /// 회차 도중 앱이 죽으면 그 회차의 성공분이 통째로 사라지는 것이 확인됐다.
  /// 지금은 [GeoBackfillService.backfill]의 `onResolved` 콜백으로 한 건씩
  /// 반영·저장하므로 "도중에 죽어도 이미 성공한 것은 남는다."
  Future<void> backfillMissingGeo() async {
    if (_isBackfillingGeo) return;

    final pending = await _geoBackfillService.pendingContacts(_contacts);
    if (pending.isEmpty) return;

    _isBackfillingGeo = true;
    _geoBackfillDone = 0;
    _geoBackfillTotal = pending.length;
    notifyListeners();

    try {
      await _geoBackfillService.backfill(
        pending,
        onProgress: (done, total) {
          _geoBackfillDone = done;
          _geoBackfillTotal = total;
          notifyListeners();
        },
        onResolved: (contactId, geo) async {
          final idx = _contacts.indexWhere((c) => c.id == contactId);
          if (idx == -1) return; // 그 사이 명함이 삭제됐을 수 있다.
          _contacts[idx] = _contacts[idx].copyWith(geo: geo);
          notifyListeners();
          await _saveToDisk();
        },
      );
    } catch (e) {
      debugPrint('좌표 재계산 중 오류: $e');
    } finally {
      _isBackfillingGeo = false;
      _geoBackfillDone = 0;
      _geoBackfillTotal = 0;
      notifyListeners();
    }
  }

  /// [relinkMissingCardImagePaths]의 순수 매칭 로직 — 단위 테스트로 고정한다.
  ///
  /// `cardImagePath`가 없는 명함에 한해 [existingPathsById](contactId → 기기
  /// 암호문 파일 경로)에 같은 id가 있으면 경로를 채운다. id가 없으면(정말
  /// 이미지가 없는 명함) 그대로 null을 유지한다. 이미 경로가 있는 명함은
  /// 건드리지 않는다(로컬에서 방금 등록해 경로가 확실한 경우를 덮어써
  /// 사고 나지 않도록).
  @visibleForTesting
  static List<ContactModel> relinkCardImagePaths(
    List<ContactModel> contacts,
    Map<String, String> existingPathsById,
  ) {
    return contacts.map((c) {
      if (c.cardImagePath != null) return c;
      final path = existingPathsById[c.id];
      if (path == null) return c;
      return c.copyWith(cardImagePath: path);
    }).toList();
  }

  /// 서버 복원/다기기 병합이 로컬 명함 목록을 덮어쓰면 `cardImagePath`가
  /// 유실된다(백업 JSON에 넣지 않는 설계 — 다른 기기에선 무의미한 로컬
  /// 경로라서). 기기에 저장된 암호문 파일(`contact_card_<id>.enc`)은 그대로
  /// 남아 있으므로, 파일명 규칙으로 다시 이어붙인다.
  ///
  /// 명함마다 개별로 파일 존재를 확인하지 않고 문서 디렉터리를 **1회만**
  /// 조회한다(명함이 수백 장이어도 IO 1회) — 단, 애초에 경로가 빠진 명함이
  /// 하나도 없으면 그 조회조차 건너뛴다.
  ///
  /// 게스트(로그인 전, `_uid == null`)는 대상에서 제외한다 — 명함 이미지는
  /// 저장 시점에 uid 기반 암호화 키가 있어야만 만들어지므로(`add_card_modal_
  /// view.dart`), 게스트 상태에서는 애초에 암호문 파일이 존재할 수 없다.
  ///
  /// 반환값은 실제로 뭔가 바뀌었는지 — 호출자가 이걸 보고 저장 여부를
  /// 결정한다(이미 그 자리에서 저장하는 흐름이면 중복 저장을 피하려고).
  Future<bool> relinkMissingCardImagePaths() async {
    final uid = _uid;
    if (uid == null) return false;
    if (_contacts.every((c) => c.cardImagePath != null)) return false;

    var existing = await _contactImageService.findAllExistingCardImagePaths();

    // 기기를 바꾸거나 앱을 다시 깔면 로컬 암호문 파일이 **하나도 없다** —
    // 재연결할 대상이 없으니 예전에는 여기서 끝났고, 사진은 영영 돌아오지
    // 않았다(명함 텍스트만 복원되는 상태). 서버에 사본이 있으면 내려받아
    // 되살린다(2026-08-15, 추가 218).
    final missingIds = _contacts
        .where((c) => c.cardImagePath == null && !existing.containsKey(c.id))
        .map((c) => c.id)
        .toList();
    if (missingIds.isNotEmpty) {
      final restored = await _contactImageService.downloadMissingCardImages(
        uid: uid,
        contactIds: missingIds,
      );
      if (restored.isNotEmpty) existing = {...existing, ...restored};
    }

    if (existing.isEmpty) return false;

    final relinked = relinkCardImagePaths(_contacts, existing);
    var changed = false;
    for (var i = 0; i < _contacts.length; i++) {
      if (_contacts[i].cardImagePath != relinked[i].cardImagePath) {
        changed = true;
        break;
      }
    }
    _contacts = relinked;
    return changed;
  }

  /// 좌표를 서버에서 빼기로 하기 전에 올라간 백업 문서에는 암호문 안에
  /// 좌표가 들어 있다. 암호문이라 서버 쪽에서 필드만 지울 수 없으므로,
  /// 좌표가 빠진 페이로드로 전체를 한 번 덮어쓴다. 계정당 1회.
  Future<void> _stripGeoFromServerBackupsOnce(String uid) async {
    // setCurrentUid와 복원 양쪽에서 호출되므로 동시에 두 번 돌 수 있다.
    // 같은 내용을 두 번 올리는 게 위험하진 않지만(set은 멱등) 굳이 쓰기를
    // 두 배로 낼 이유가 없다.
    if (_strippingGeoBackups) return;
    _strippingGeoBackups = true;
    try {
      final flagKey = 'geo_stripped_from_backup_v1_$uid';
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(flagKey) ?? false) return;
      if (_contacts.isEmpty) {
        // 아직 로컬에 명함이 없으면(복원 전) 지울 대상도 판단할 수 없다.
        // 플래그를 세우지 않고 다음 로그인에 다시 시도한다.
        return;
      }
      final ok = await DataBackupService.rebackupAllContacts(uid, _contacts);
      if (ok) await prefs.setBool(flagKey, true);
    } catch (e) {
      debugPrint('서버 백업 좌표 제거 실패: $e');
    } finally {
      _strippingGeoBackups = false;
    }
  }

  /// 계정 삭제(backlog #49) 또는 계정 전환 시 로컬 명함 데이터를 전부
  /// 지운다. 서버 데이터는 건드리지 않는다 — 호출자가 필요하면 별도로
  /// `DataBackupService`를 통해 서버 쪽도 정리한다.
  Future<void> clearLocal() async {
    _contacts = [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing saved contacts: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;

      // 1) 레거시 평문 저장분인지 먼저 시도한다 — 암호화를 도입하기 전에
      // 저장된 데이터(예: 기존 "문정순" 명함)는 순수 JSON 배열 문자열이라
      // 여기서 바로 파싱에 성공한다.
      List<dynamic>? legacyList;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) legacyList = decoded;
      } catch (_) {
        legacyList = null;
      }

      if (legacyList != null) {
        _contacts = legacyList
            .map((j) => ContactModel.fromJson(j as Map<String, dynamic>))
            .toList();
        // 로그인 전(uid==null)이면 내부에서 바로 false를 반환하니 안전하다.
        await relinkMissingCardImagePaths();
        notifyListeners();
        // 로그인된 상태라면 즉시 암호화해서 재저장(1회성 투명 마이그레이션).
        // 아직 로그인 전이면 로그인 시점([setCurrentUid])에 마이그레이션한다.
        if (_uid != null) {
          await _saveToDisk();
        } else {
          _pendingPlaintextMigration = true;
        }
        return;
      }

      // 2) 평문 JSON이 아니면 암호화된 payload로 간주한다.
      final uid = _uid;
      if (uid == null) {
        // 로그인 전이라 키를 만들 수 없다 — setCurrentUid()가 로그인 완료
        // 후 다시 이 메서드를 호출해 복호화를 재시도한다.
        _pendingEncryptedLoad = true;
        return;
      }

      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final decoded = await DataCryptoService.decryptJson(raw, key);
      final jsonList = decoded['contacts'] as List<dynamic>? ?? const [];
      _contacts = jsonList
          .map((j) => ContactModel.fromJson(j as Map<String, dynamic>))
          .toList();
      // 이전 세션에서 서버 복원/병합으로 경로가 빠진 채 저장된 명함이
      // 있을 수 있다 — 일반 로드 시점에도 재연결을 시도해 둔다.
      if (await relinkMissingCardImagePaths()) {
        await _saveToDisk();
      }
      notifyListeners();
    } catch (e) {
      // 복호화 실패(위변조/키 불일치 등)를 포함해 어떤 이유로든 로드에
      // 실패하면 크래시하지 않고 빈 목록으로 시작한다.
      debugPrint('Error loading saved contacts: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _contacts.map((c) => c.toJson()).toList();
      final uid = _uid;
      if (uid == null) {
        // 로그인 전(게스트) — 암호화 키를 만들 수 없으므로 평문으로 저장.
        await prefs.setString(_storageKey, jsonEncode(jsonList));
        return;
      }
      final key = await _encryptionKeyService.getOrCreateUserKey(uid);
      final encoded = await DataCryptoService.encryptJson({
        'contacts': jsonList,
      }, key);
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving contacts to disk: $e');
    }
  }

  /// 같은 전화번호로 이미 등록된 명함을 찾는다. 없으면 null.
  ///
  /// 같은 사람 명함을 두 번 스캔하면 그대로 두 건이 쌓이는 문제(P1-40)를 저장
  /// 직전에 잡기 위한 것. [excludeId]를 주면 그 명함은 제외한다(편집 시 자기 자신).
  ///
  /// ⚠️ **휴대폰 칸 하나만 본다.** 넓게 보려면 [findDuplicate]를 쓴다 — 이
  /// 함수는 기존 호출부를 위해 남겨 둔 좁은 판정이다.
  ContactModel? findByPhone(String phone, {String? excludeId}) =>
      findDuplicate(phone: phone, excludeId: excludeId)?.contact;

  /// 같은 사람으로 볼 만한 명함을 찾는다. 없으면 null.
  ///
  /// ## 무엇끼리 맞춰 보는가 (2026-08-26 사용자 확정)
  ///
  /// | 축 | 규칙 |
  /// |---|---|
  /// | **휴대폰** | 휴대폰끼리만 |
  /// | **이메일** | 완전 일치 |
  /// | **이름 + 회사** | 양쪽 다 **번호가 없을 때만**, 보조로 |
  ///
  /// 🚨 **사무실·직통·팩스는 판정에 쓰지 않는다.** 사용자 지적: *"대표번호는
  /// 같은 사람이 많아서 안 돼."* 회사 대표번호는 그 회사 사람 모두의 명함에
  /// 같이 인쇄되므로, 그것으로 사람을 맞추면 **남남을 같은 사람으로 본다.**
  ///
  /// 📌 **중복을 놓치는 것보다 엉뚱한 사람을 합치라고 권하는 것이 더 나쁘다** —
  /// 전자는 두 건이 쌓일 뿐이지만 후자는 **데이터를 섞는다.**
  ///
  /// ⚠️ 이메일도 공용 주소(`info@…`)가 있어, **이미 명함 둘 이상에 쓰인
  /// 이메일은 개인 주소로 보지 않는다.** 짐작하지 않고 데이터에서 센다 —
  /// 진짜 중복은 기존 명함 한 건에만 있으므로 이 그물에 안 걸린다.
  DuplicateMatch? findDuplicate({
    required String phone,
    String? email,
    String? name,
    String? company,
    String? excludeId,
  }) => matchIn(
    _contacts,
    phone: phone,
    email: email,
    name: name,
    company: company,
    excludeId: excludeId,
  );

  /// [findDuplicate]의 알맹이 — **목록만 있으면 도는 순수 함수**다.
  ///
  /// 저장소를 띄우지 않고 규칙만 테스트할 수 있게 갈라 두었다. 판정 규칙은
  /// 화면과 저장소가 **한 벌만** 써야 하므로(2026-08-26 정정 전에는 두 벌이었다)
  /// 여기 하나로 모은다.
  static DuplicateMatch? matchIn(
    List<ContactModel> contacts, {
    required String phone,
    String? email,
    String? name,
    String? company,
    String? excludeId,
  }) {
    final mobile = normalizePhone(phone);
    final mail = _normalizeEmail(email ?? '');
    final who = _normalizeName(name ?? '');
    final org = _normalizeName(company ?? '');

    final sharedEmails = _sharedEmails(contacts, excludeId: excludeId);

    DuplicateMatch? weak;
    for (final c in contacts) {
      if (c.id == excludeId) continue;

      if (mobile.isNotEmpty && normalizePhone(c.phone) == mobile) {
        return DuplicateMatch(c, DuplicateMatchField.mobile);
      }
      if (mail.isNotEmpty &&
          _normalizeEmail(c.email) == mail &&
          !sharedEmails.contains(mail)) {
        return DuplicateMatch(c, DuplicateMatchField.email);
      }

      // 보조 축 — 번호가 **양쪽 다 없을 때만** 본다. 번호가 있는데 안 맞았다면
      // 그건 "다른 사람"이라는 신호이므로, 이름이 같다고 뒤집지 않는다
      // (동명이인이 그대로 걸린다).
      if (weak == null &&
          mobile.isEmpty &&
          normalizePhone(c.phone).isEmpty &&
          who.isNotEmpty &&
          org.isNotEmpty &&
          _normalizeName(c.name) == who &&
          _normalizeName(c.company) == org) {
        weak = DuplicateMatch(c, DuplicateMatchField.nameAndCompany);
      }
    }
    return weak;
  }

  /// 이미 명함 **둘 이상**에 쓰인 이메일 — 공용 주소로 본다.
  static Set<String> _sharedEmails(
    List<ContactModel> contacts, {
    String? excludeId,
  }) {
    final count = <String, int>{};
    for (final c in contacts) {
      if (c.id == excludeId) continue;
      final e = _normalizeEmail(c.email);
      if (e.isEmpty) continue;
      count[e] = (count[e] ?? 0) + 1;
    }
    return {
      for (final e in count.entries)
        if (e.value >= 2) e.key,
    };
  }

  /// 이름·회사 비교용 — 공백을 없애고 소문자로. 표기 흔들림(`(주)` 앞뒤 공백,
  /// `홍 길동`)까지는 손대지 않는다. **넓게 잡으면 동명이인이 걸린다.**
  static String _normalizeName(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 전화번호를 비교용으로 정규화한다 — 숫자만 남기고, 10자리가 넘으면
  /// **뒤 9자리**만 쓴다.
  ///
  /// ⚠️ 뒤 9자리로 자르는 이유는 국가번호 표기 차이다(`010-1234-5678` ↔
  /// `+82-10-1234-5678`). 앞자리를 그대로 비교하면 같은 번호가 다르게 읽힌다.
  ///
  /// 📌 **이 규칙이 종전에는 두 벌이었다**(2026-08-26 정정) — 저장소는 숫자
  /// 전체를, 등록 화면은 뒤 9자리를 비교해서 **같은 번호가 한쪽에서만 중복으로
  /// 잡혔다.** 관대한 쪽으로 합쳤다.
  static String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  static String _normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// 이 명함이 주소 지오코딩을 모두 실패해 좌표를 못 얻은 상태인지(P1-25).
  /// 화면에서 "주소로 위치를 못 찾아 주변 목록에 안 뜬다"는 안내에 쓴다.
  Future<bool> hasAddressGeocodingFailed(ContactModel c) =>
      _geoBackfillService.hasGivenUpGeo(c);

  void addContact(ContactModel newContact) {
    // 다기기 병합의 최신본 판정(LWW) 기준을 지금 시각으로 찍는다(P1-39 A안).
    final stamped = newContact.updatedAt == null
        ? newContact.copyWith(updatedAt: DateTime.now())
        : newContact;
    _contacts = [stamped, ..._contacts];
    notifyListeners();
    _saveToDisk();
    _backup(stamped);
  }

  void updateContact(ContactModel updatedContact) {
    // 편집이 있었으므로 updatedAt을 지금으로 갱신 — 이래야 다른 기기와 병합할 때
    // 이 편집이 최신본으로 인식돼 전파된다(P1-39 A안).
    final stamped = updatedContact.copyWith(updatedAt: DateTime.now());
    _contacts = _contacts.map((c) {
      if (c.id == stamped.id) {
        return stamped;
      }
      return c;
    }).toList();
    notifyListeners();
    _saveToDisk();
    _backup(stamped);
  }

  void deleteContact(String id) {
    // 삭제 전에 암호화된 명함 이미지 파일도 정리한다(추가 133).
    // uid를 함께 넘겨 **서버 사본까지** 지운다 — 방침은 "이용자가 해당 명함을
    // 삭제한 때 즉시 파기"라고 적고 있다(2026-08-15, 추가 218).
    final idx = _contacts.indexWhere((c) => c.id == id);
    final cardImagePath = idx >= 0 ? _contacts[idx].cardImagePath : null;
    if (cardImagePath != null) {
      _contactImageService.deleteCardImage(
        cardImagePath,
        uid: _uid,
        contactId: id,
      );
    } else if (_uid != null) {
      // 경로가 끊긴 명함(서버 복원 직후 등)이라도 서버엔 사본이 있을 수 있다.
      // 여기서 안 지우면 참조가 사라져 **나중에 지울 수도 없는 고아 파일**이
      // 된다 — 로컬에서 겪은 것과 같은 함정이다. 빈 경로는 "기기 파일은 없고
      // 서버만 정리하라"는 뜻으로 해석된다(deleteCardImage 문서화 참고).
      _contactImageService.deleteCardImage('', uid: _uid, contactId: id);
    }
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
    _saveToDisk();
    final uid = _uid;
    if (uid != null) {
      DataBackupService.deleteContactBackup(uid, id);
      // 삭제 기록(tombstone)을 남겨 다른 기기도 이 삭제를 반영하게 한다(P1-39 A안).
      // 안 남기면 다른 기기와 병합할 때 그 기기의 사본이 다시 살아난다.
      DataBackupService.writeTombstone(uid, id);
    }
  }

  void _backup(ContactModel contact) {
    final uid = _uid;
    if (uid != null) DataBackupService.backupContact(uid, contact);
  }
}

/// [ContactsRepository.findDuplicate]가 무엇 때문에 같은 사람으로 봤는지.
///
/// 화면이 이유를 말해 줄 수 있어야 한다 — *"같은 전화번호"*라고만 하면
/// **이메일이 같아서 걸린 경우에 거짓말이 된다.**
enum DuplicateMatchField {
  /// 휴대폰 칸끼리 같다.
  mobile,

  /// 번호도 이메일도 없어 **이름과 회사가 같은 것**만 보고 걸렀다. 확신이
  /// 낮은 신호이므로 화면이 그렇게 말해야 한다.
  nameAndCompany,

  /// 이메일이 같다.
  email,
}

class DuplicateMatch {
  const DuplicateMatch(this.contact, this.field);

  final ContactModel contact;
  final DuplicateMatchField field;

  /// 화면 문장에 끼워 쓰는 사유. **"~한 명함" 앞에 붙는 꼴**로 통일했다 —
  /// 두 다이얼로그가 문장 모양이 달라서, 명사형으로 두면 한쪽이 깨진다.
  String get reason => switch (field) {
    DuplicateMatchField.mobile => '휴대폰 번호가 같은',
    DuplicateMatchField.email => '이메일 주소가 같은',
    DuplicateMatchField.nameAndCompany =>
      '이름과 회사가 같은(전화번호가 없어 확실하지는 않은)',
  };
}
