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

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

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
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _settle();

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
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      // auth_gate 의 순서 그대로다: clearLocal → (서버 복원) → 저장.
      await repo.clearLocal();
      repo.addContact(_contact('c1'));
      await _settle();

      final saved = (await SharedPreferences.getInstance()).getString(
        _contactsKey,
      );
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
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _settle();

      expect(repo.localReadFailed, isFalse);
    });

    test('🚨 clearLocal 뒤에는 저장이 실제로 된다 — 계정 전환의 「교체」가 로컬에 남는다', () async {
      SharedPreferences.setMockInitialValues({_profileKey: _unreadable});
      final repo = MyProfileRepository(
        encryptionKeyService: _FixedKeyService(),
      );
      await repo.setCurrentUid('uid_test');
      await _settle();
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await repo.updateProfile(
        MyProfileModel.defaultProfile.copyWith(name: '교체된 프로필'),
      );
      await _settle();

      final saved = (await SharedPreferences.getInstance()).getString(
        _profileKey,
      );
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
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      await _settle();

      expect(repo.localReadFailed, isFalse);
    });

    test('🚨 clearLocal 뒤에는 저장이 실제로 된다 — 계정 전환의 「교체」가 로컬에 남는다', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: _unreadable});
      final repo = GroupsRepository(encryptionKeyService: _FixedKeyService());
      await repo.setCurrentUid('uid_test');
      await _settle();
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      await repo.clearLocal();
      repo.createGroup('교체된 그룹');
      await _settle();

      final saved = (await SharedPreferences.getInstance()).getString(
        _groupsKey,
      );
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
