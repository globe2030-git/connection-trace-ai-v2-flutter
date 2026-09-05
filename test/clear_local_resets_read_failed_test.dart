/// **`clearLocal()` 은 「못 읽었다」도 함께 내린다** (2026-09-05).
///
/// ## 무엇이 문제였나
///
/// `localReadFailed` 가 참인 동안 저장은 아무것도 쓰지 않는다 — 열지 못한
/// 암호문을 덮지 않기 위한 장치다(#820 · #857). 그런데 **`clearLocal()` 이
/// 그 플래그를 되돌리지 않았다.** 셋 다 그랬다.
///
/// 그래서 계정 전환의 「현재 계정 데이터로 교체」가 **조용히 실패한다.**
///
/// ```
/// auth_gate.dart   clearLocal() ×3   →  forceRestoreFromServer() ×3  →  저장
///                                                                        ↑ 막힌다
/// 결과   서버에서 받아온 것이 로컬에 안 남는다
///        앱을 껐다 켜면 다시 비어 있다
/// ```
///
/// ## 🚨 왜 「지운 뒤에」 내리나
///
/// `prefs.remove()` 는 실패할 수 있고, 그 실패는 `catch` 가 삼킨다. 실패하면
/// **암호문이 그대로 남는데**, 그때 플래그를 내리면 저장 차단이 풀려
/// **원본을 덮어쓴다** — 이 장치가 막으려는 바로 그 사고다.
///
/// ```
/// remove 성공   지울 것이 없어졌다  →  내린다 (막을 이유가 사라졌다)
/// remove 실패   암호문이 남아 있다  →  그대로 둔다 (계속 막는다)
/// ```
///
/// ⚠️ **아래 검사는 「성공」 쪽만 잡는다.** `SharedPreferences` 목에서
/// `remove` 를 실패시킬 방법이 없어 「실패 쪽」은 코드 순서(=`try` 안,
/// `remove` 뒤)로만 보장된다 — 검사가 없는 자리라 여기 적어 둔다.
library;

import 'package:connection_trace_ai_flutter/core/services/encryption_key_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/my_profile_repository.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _contactsKey = 'saved_contacts_v2';
const _profileKey = 'my_profile_v1';
const _groupsKey = 'saved_groups_v1';

/// 평문 JSON 도 아니고 이 키로 열리지도 않는 값 — 「못 읽는 상태」를 만든다.
const _unreadable = 'bm90LWEtdmFsaWQtY2lwaGVydGV4dA==';

/// 실기기의 보안 저장소·Firestore 를 타지 않고 **항상 같은 키**를 준다.
///
/// 📌 이게 있어야 「clearLocal 뒤에 저장이 **실제로** 된다」를 잴 수 있다 —
/// 진짜 서비스는 테스트 환경에서 키를 못 만들어, 차단이 풀렸는지 막혔는지가
/// 구분되지 않는다(둘 다 아무것도 안 써진다).
class _FixedKeyService extends EncryptionKeyService {
  static final SecretKey _key = SecretKey(List<int>.filled(32, 7));

  @override
  Future<SecretKey> getOrCreateUserKey(String uid) async => _key;

  @override
  Future<List<SecretKey>> knownKeysFor(String uid) async => [_key];
}

/// 🚨 **고정 시간으로 기다리지 않는다** (2026-09-06, 깜빡임 수정).
///
/// 처음에는 `Future.delayed(50ms)` 로 기다렸다. **CI 에서 깜빡였다** —
/// 같은 커밋이 어떤 실행에서는 통과하고 어떤 실행에서는 실패했다.
///
/// ## 왜 그런가
///
/// `addContact`·`createGroup` 은 저장을 **`await` 없이** 부른다
/// (`contacts_repository.dart` `_saveToDisk()` · `groups_repository.dart`
/// `_persist()` 의 `unawaited`). 게다가 이 검사는 `_FixedKeyService` 로
/// **진짜 AES-GCM 암호화**를 돌린다. 그래서 「50ms 안에 끝난다」는 **러너가
/// 한가할 때만 참**이다.
///
/// 📌 **재현했다**: `_settle` 을 5ms 로 줄이면 `Expected: not null` ·
/// `Actual: null` 로 깨진다(15ms 부터는 통과). CI 실패 메시지와 같은 모양이다.
///
/// ## 그래서 조건으로 기다린다
///
/// ⚠️ **넉넉히 기다리는 것이 검사를 무르게 만들지 않는다** — 차단이 안 풀리면
/// 값은 **영영** 안 바뀌므로 제한 시간을 다 쓰고 그대로 실패한다. 바뀌는 것은
/// **언제 성공을 알아채는가**뿐이다.
const _limit = Duration(seconds: 5);
const _tick = Duration(milliseconds: 5);

/// [check] 가 참이 될 때까지 기다린다. 안 되면 그대로 두고 돌아온다(검사가 판정).
Future<void> _until(bool Function() check) async {
  final deadline = DateTime.now().add(_limit);
  while (!check() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(_tick);
  }
}

/// [key] 에 **새 값이 쓰일 때까지** 기다리고 그 값을 돌려준다.
///
/// [was] 는 쓰이기 전의 값이다 — 그대로면 아직 안 쓰인 것으로 본다.
Future<String?> _waitSaved(String key, {required String was}) async {
  String? v;
  await _until(() {
    v = _prefsCache?.getString(key);
    return v != null && v != was;
  });
  return v;
}

/// `SharedPreferences.getInstance()` 는 비동기라 `_until` 안에서 못 쓴다.
/// 한 번 받아 두고 쓴다 — 목 구현이라 같은 인스턴스를 돌려준다.
SharedPreferences? _prefsCache;

Future<void> _settle() async {
  _prefsCache = await SharedPreferences.getInstance();
}

ContactModel _contact(String id) => ContactModel(
  id: id,
  name: id,
  company: '',
  title: '',
  phone: '',
  email: '',
  tags: const [],
  talkingPoints: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContactsRepository', () {
    test('🚨 clearLocal 이 「못 읽었다」도 함께 내린다', () async {
      SharedPreferences.setMockInitialValues({_contactsKey: _unreadable});
      final repo = ContactsRepository(encryptionKeyService: _FixedKeyService());
      await repo.setCurrentUid('uid_test');
      await _settle();
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _until(() => !repo.localReadFailed);

      expect(
        repo.localReadFailed,
        isFalse,
        reason: '⭐ 지웠으므로 덮어쓸 암호문이 없다 — 계속 막으면 교체가 조용히 실패한다',
      );
    });

    test('🚨 clearLocal 뒤에는 저장이 실제로 된다 — 계정 전환의 「교체」가 로컬에 남는다', () async {
      SharedPreferences.setMockInitialValues({_contactsKey: _unreadable});
      final repo = ContactsRepository(encryptionKeyService: _FixedKeyService());
      await repo.setCurrentUid('uid_test');
      await _settle();
      // 🚨 로드도 비동기다 — 여기서도 고정 시간으로 기다리지 않는다.
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      // auth_gate 의 순서 그대로다: clearLocal → (서버 복원) → 저장.
      await repo.clearLocal();
      repo.addContact(_contact('c1'));

      // ⚠️ `addContact` 는 저장을 **await 없이** 부른다 — 고정 시간으로
      //    기다리면 러너가 느린 날 깜빡인다(위 `_waitSaved` 주석).
      final saved = await _waitSaved(_contactsKey, was: _unreadable);
      expect(saved, isNotNull, reason: '🚨 차단이 안 풀리면 여기가 null 이다');
      expect(saved, isNot(_unreadable), reason: '옛 암호문이 아니라 새로 쓴 것이어야 한다');
    });
  });

  group('MyProfileRepository', () {
    test('🚨 clearLocal 이 「못 읽었다」도 함께 내린다', () async {
      SharedPreferences.setMockInitialValues({_profileKey: _unreadable});
      final repo = MyProfileRepository(
        encryptionKeyService: _FixedKeyService(),
      );
      await repo.setCurrentUid('uid_test');
      await _settle();
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _until(() => !repo.localReadFailed);

      expect(repo.localReadFailed, isFalse);
    });

    test('🚨 clearLocal 뒤에는 저장이 실제로 된다 — 계정 전환의 「교체」가 로컬에 남는다', () async {
      SharedPreferences.setMockInitialValues({_profileKey: _unreadable});
      final repo = MyProfileRepository(
        encryptionKeyService: _FixedKeyService(),
      );
      await repo.setCurrentUid('uid_test');
      await _settle();
      // 🚨 로드도 비동기다 — 여기서도 고정 시간으로 기다리지 않는다.
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await repo.updateProfile(
        MyProfileModel.defaultProfile.copyWith(name: '교체된 프로필'),
      );

      // 📌 프로필은 `updateProfile` 이 저장을 **await 한다** — 그래서 이쪽은
      //    원래도 안 깜빡였다. 그래도 같은 방식으로 둔다: 셋이 다른 모양이면
      //    다음 사람이 「왜 여기만 다르지」에 시간을 쓴다.
      final saved = await _waitSaved(_profileKey, was: _unreadable);
      expect(saved, isNotNull, reason: '🚨 차단이 안 풀리면 여기가 null 이다');
      expect(saved, isNot(_unreadable));
    });
  });

  group('GroupsRepository', () {
    test('🚨 clearLocal 이 「못 읽었다」도 함께 내린다', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: _unreadable});
      final repo = GroupsRepository(encryptionKeyService: _FixedKeyService());
      await repo.setCurrentUid('uid_test');
      await _settle();
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _until(() => !repo.localReadFailed);

      expect(repo.localReadFailed, isFalse);
    });

    test('🚨 clearLocal 뒤에는 저장이 실제로 된다 — 계정 전환의 「교체」가 로컬에 남는다', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: _unreadable});
      final repo = GroupsRepository(encryptionKeyService: _FixedKeyService());
      await repo.setCurrentUid('uid_test');
      await _settle();
      // 🚨 로드도 비동기다 — 여기서도 고정 시간으로 기다리지 않는다.
      await _until(() => repo.localReadFailed);
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      repo.createGroup('교체된 그룹');

      // ⚠️ `_persist()` 가 `unawaited(_saveToDisk())` 다 — contacts 와 같다.
      final saved = await _waitSaved(_groupsKey, was: _unreadable);
      expect(saved, isNotNull, reason: '🚨 차단이 안 풀리면 여기가 null 이다');
      expect(saved, isNot(_unreadable));
    });
  });

  test('대조군 — 처음부터 잘 읽히면 clearLocal 이 아무것도 안 바꾼다', () async {
    SharedPreferences.setMockInitialValues({_groupsKey: '[]'});
    final repo = GroupsRepository(encryptionKeyService: _FixedKeyService());
    await _settle();
    expect(repo.localReadFailed, isFalse, reason: '전제 — 잘 읽힌 상태');

    await repo.clearLocal();
    await _settle();

    expect(repo.localReadFailed, isFalse);
  });
}
