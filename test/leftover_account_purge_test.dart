// 계정을 바꿨을 때 이 기기에 남는 이전 계정 사진을 30일 뒤에 지운다
// (추가 522, globe2030님 결정 2026-08-27 · 「유지」 제거 2026-09-04).
//
// 🚨 **이 파일이 지키는 것은 「지운다」가 아니라 「안 지운다」쪽이다.**
// 지우는 것은 코드를 보면 알 수 있는데, **지우면 안 되는 것을 안 지키는
// 것은 실기기에서도 한참 뒤에야 드러난다** — 30일 뒤에 남의 사진이 사라지는
// 식이라 그때는 원인을 찾기도 어렵다. 그래서 안전장치 넷을 여기서 잠근다.
//
//   ① 지금 로그인한 계정은 절대 안 지운다 (돌아오면 취소)
//   ② 서버는 절대 안 건드린다 (deleteCardImage 에 uid 를 안 넘긴다)
//   ③ 내 프로필 사진(`_my_profile_card`)은 대상이 아니다 — A·B 공용 파일이다
//   ④ 만기 전에는 안 지운다
import 'package:connection_trace_ai_flutter/core/services/contact_image_service.dart';
import 'package:connection_trace_ai_flutter/core/services/encryption_key_service.dart';
import 'package:connection_trace_ai_flutter/core/services/leftover_account_purge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 지운 경로와 **uid 를 넘겼는지**를 기록한다. uid 가 넘어갔다면 그 순간
/// 서버 사진과 백업 장부까지 지워진다 — 그것이 안전장치 ②가 막는 것이다.
class _FakeImageService extends ContactImageService {
  final List<String> deletedPaths = [];
  final List<String?> uidsPassed = [];

  @override
  Future<String?> canonicalPath(String contactId) async =>
      '/fake/docs/contact_card_$contactId.enc';

  @override
  Future<void> deleteCardImage(
    String path, {
    String? uid,
    String? contactId,
  }) async {
    deletedPaths.add(path);
    uidsPassed.add(uid);
  }
}

class _FakeKeyService extends EncryptionKeyService {
  final List<String> deletedKeys = [];

  @override
  Future<bool> deleteLocalKey(String uid) async {
    deletedKeys.add(uid);
    return true;
  }
}

void main() {
  late _FakeImageService images;
  late _FakeKeyService keys;
  late LeftoverAccountPurgeService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    images = _FakeImageService();
    keys = _FakeKeyService();
    service = LeftoverAccountPurgeService(
      imageService: images,
      keyService: keys,
    );
  });

  test('⭐ 유예는 30일이다 — 줄이려면 근거를 함께 적어라', () {
    expect(LeftoverAccountPurgeService.delay, const Duration(days: 30));
  });

  test('예약하면 예정 시각이 30일 뒤로 남는다', () async {
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1', 'c2'], now: now);

    final pending = await service.pendingSchedules();
    expect(pending.keys, ['uid-A']);
    expect(pending['uid-A'], DateTime.utc(2026, 10, 4));
  });

  test('④ 만기 전에는 한 장도 안 지운다', () async {
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: now);

    final purged = await service.runDue(
      currentUid: 'uid-B',
      now: now.add(const Duration(days: 29, hours: 23)),
    );

    expect(purged, 0);
    expect(images.deletedPaths, isEmpty);
    expect(keys.deletedKeys, isEmpty);
    // 예약은 그대로 남아 있어야 한다 — 지우면 영영 안 지워진다.
    expect((await service.pendingSchedules()).keys, ['uid-A']);
  });

  test('만기가 지나면 사진과 로컬 키를 지우고 예약을 없앤다', () async {
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1', 'c2'], now: now);

    final purged = await service.runDue(
      currentUid: 'uid-B',
      now: now.add(const Duration(days: 31)),
    );

    expect(purged, 1);
    expect(images.deletedPaths, [
      '/fake/docs/contact_card_c1.enc',
      '/fake/docs/contact_card_c2.enc',
    ]);
    expect(keys.deletedKeys, ['uid-A']);
    expect(await service.pendingSchedules(), isEmpty);
  });

  test('🚨 ② 서버는 안 건드린다 — deleteCardImage 에 uid 를 넘기지 않는다', () async {
    // uid 를 넘기면 그 함수가 Cloud Storage 객체와 백업 장부까지 지운다.
    // 이전 계정(A)이 다른 기기에서 멀쩡히 쓰고 있을 수 있으므로, 그건
    // 「기기 정리」가 아니라 「A 몰래 A 의 계정을 건드리는 일」이 된다.
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: now);
    await service.runDue(
      currentUid: 'uid-B',
      now: now.add(const Duration(days: 31)),
    );

    expect(images.uidsPassed, [null]);
  });

  test('🚨 ① 지금 로그인한 계정의 예약은 만기가 지났어도 취소된다', () async {
    // 「로그인 자체가 취소 행위」다 — 실수로 계정을 바꿨던 사람이 돌아오면
    // 아무 일도 없었던 것이 되어야 한다.
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: now);

    final purged = await service.runDue(
      currentUid: 'uid-A',
      now: now.add(const Duration(days: 99)),
    );

    expect(purged, 0);
    expect(images.deletedPaths, isEmpty);
    expect(keys.deletedKeys, isEmpty);
    expect(await service.pendingSchedules(), isEmpty);
  });

  test('cancelFor 는 그 계정의 예약만 지운다', () async {
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: now);
    await service.schedule(uid: 'uid-B', contactIds: ['c2'], now: now);

    expect(await service.cancelFor('uid-A'), isTrue);
    expect((await service.pendingSchedules()).keys, ['uid-B']);
    // 없는 계정을 취소해도 조용히 false 다.
    expect(await service.cancelFor('uid-없음'), isFalse);
  });

  test('🚨 ③ 내 프로필 사진은 예약에도 삭제에도 들어가지 않는다', () async {
    // `_my_profile_card` 는 계정과 무관한 **고정 파일명**이라 A 와 B 가 같은
    // 파일을 쓴다. 이것을 예약에 넣으면 30일 뒤에 **B 가 그 사이 저장한
    // 자기 프로필 사진**을 지워버린다.
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(
      uid: 'uid-A',
      contactIds: ['c1', ContactImageService.myProfileCardId],
      now: now,
    );
    await service.runDue(
      currentUid: 'uid-B',
      now: now.add(const Duration(days: 31)),
    );

    expect(images.deletedPaths, ['/fake/docs/contact_card_c1.enc']);
  });

  test('같은 계정으로 다시 전환하면 예약을 덮어쓴다 — 장부가 안 자란다', () async {
    final first = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: first);
    final second = DateTime.utc(2026, 9, 10);
    await service.schedule(uid: 'uid-A', contactIds: ['c9'], now: second);

    final pending = await service.pendingSchedules();
    expect(pending.keys, ['uid-A']);
    expect(pending['uid-A'], DateTime.utc(2026, 10, 10));

    await service.runDue(
      currentUid: 'uid-B',
      now: second.add(const Duration(days: 31)),
    );
    // 첫 예약의 c1 이 아니라 마지막 예약의 c9 를 지운다.
    expect(images.deletedPaths, ['/fake/docs/contact_card_c9.enc']);
  });

  test('purgeNow 는 기다리지 않고 지우고 예약도 없앤다', () async {
    final now = DateTime.utc(2026, 9, 4);
    await service.schedule(uid: 'uid-A', contactIds: ['c1'], now: now);

    await service.purgeNow(uid: 'uid-A', contactIds: ['c1']);

    expect(images.deletedPaths, ['/fake/docs/contact_card_c1.enc']);
    expect(images.uidsPassed, [null]); // 여기서도 서버는 안 건드린다
    expect(keys.deletedKeys, ['uid-A']);
    expect(await service.pendingSchedules(), isEmpty);
  });

  test('빈 명함 목록은 예약하지 않는다 — 지울 것이 없다', () async {
    await service.schedule(uid: 'uid-A', contactIds: [], now: DateTime.utc(2026, 9, 4));
    expect(await service.pendingSchedules(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LeftoverAccountPurgeService.prefsKey), isNull);
  });

  test('장부가 깨져 있으면 조용히 비운다 — 못 읽는 채로 자라게 두지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      LeftoverAccountPurgeService.prefsKey: '이건 JSON 이 아니다',
    });
    expect(await service.pendingSchedules(), isEmpty);
    // 🚨 못 읽었을 때 「전부 지운다」로 가면 안 된다 — 되돌릴 수 없다.
    expect(await service.runDue(currentUid: 'uid-B'), 0);
    expect(images.deletedPaths, isEmpty);
  });
}
