/// **프로필과 그룹도 「못 읽었다」를 「없다」로 다루지 않는다** (2026-09-05).
///
/// ## 왜 이 파일이 따로 있나
///
/// `test/local_read_failed_test.dart` 가 2026-09-04에 **명함**에서 같은 것을
/// 잠갔다. 그런데 **같은 패턴을 쓰는 저장소가 셋인데 하나만 고쳐져 있었다** —
/// `MyProfileRepository` 와 `GroupsRepository` 는 `catch { debugPrint }` 뿐이라
/// 손실이 나는 길이 그대로 열려 있었다.
///
/// ```
/// ① 재설치 등으로 기기의 키가 없다
/// ② 서버에서 키를 못 받는다 → 새 키가 발급된다
/// ③ 기존 암호문이 안 열린다 → 기본 프로필 / 빈 그룹 목록
/// ④ 저장이 한 번 돌면 새 키로 덮어쓴다
/// ⑤ 🚨 진짜로 사라진다
/// ```
///
/// **이 테스트가 지키는 것은 ④를 막는 것**이다.
///
/// ⭐ **명함 쪽 테스트가 못 잰 것을 여기서는 잰다.** 그 파일은 스스로
/// *"여기서 보는 것은 「원본이 남아 있다」는 **결과**이지, 「저장 차단 분기를
/// 탔다」는 **경로**가 아니다 — `_saveToDisk` 를 확실히 트리거하는 공개
/// 경로가 지금은 마땅치 않다"* 고 한계를 적어 뒀다. 프로필·그룹에는 그
/// 공개 경로가 있다(`updateProfile` · `createGroup`) — **저장을 실제로
/// 시키고** 원본이 그대로인지 본다.
///
/// 📌 **그룹명을 「작은 데이터」로 보지 않는다.** 이용자가 자유롭게 적는
/// 값이라 제3자를 특정할 수 있고, `groups_repository.dart` 머리말이 프로필과
/// 같은 취급을 받는다고 적어 뒀다(법무 스팟 확인).
library;

import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/groups_repository.dart';
import 'package:connection_trace_ai_flutter/data/repositories/my_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profileKey = 'my_profile_v1';
const _groupsKey = 'saved_groups_v1';

/// 평문 JSON 도 아니고 이 기기의 키로 열리지도 않는 값 — 「못 읽는 상태」다.
const _unreadable = 'bm90LWEtdmFsaWQtY2lwaGVydGV4dA==';

/// 로드는 생성자·`setCurrentUid` 안에서 비동기로 돈다. 끝날 때까지 기다린다.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MyProfileRepository', () {
    test('🚨 못 읽었으면 「없다」가 아니라 「못 읽었다」로 남는다', () async {
      SharedPreferences.setMockInitialValues({_profileKey: _unreadable});
      final repo = MyProfileRepository();
      await _settle();

      // uid 가 생겨야 복호화를 시도한다(그 전에는 판단을 미룬다).
      await repo.setCurrentUid('uid_test');
      await _settle();

      expect(
        repo.localReadFailed,
        isTrue,
        reason: '🚨 기본 프로필로 보이는 이유가 「안 적어서」가 아니라 '
            '「못 읽어서」임을 화면이 알아야 한다',
      );
      expect(
        repo.hasCustomProfile,
        isFalse,
        reason: '못 읽었으므로 「직접 입력한 프로필이 있다」고 말하면 안 된다',
      );
    });

    test('🚨 못 읽은 상태에서는 저장이 원본을 덮지 않는다 — 공개 경로로 실제 저장을 시킨다', () async {
      SharedPreferences.setMockInitialValues({_profileKey: _unreadable});
      final repo = MyProfileRepository();
      await _settle();
      await repo.setCurrentUid('uid_test');
      await _settle();
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      // ⭐ 이용자가 프로필을 고치는 것과 같은 경로다. `_persistToDisk` 가
      //    반드시 불린다 — 차단이 없으면 여기서 암호문이 덮인다.
      await repo.updateProfile(
        MyProfileModel.defaultProfile.copyWith(name: '덮어쓰기 시도'),
      );
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_profileKey),
        _unreadable,
        reason: '⭐ 못 읽은 암호문이 그대로 남아야 나중에 키가 돌아왔을 때 열 수 있다',
      );
    });

    test('정상적으로 읽히면 「못 읽었다」가 아니다 — 대조군', () async {
      // 레거시 평문 저장분은 키 없이도 읽힌다.
      SharedPreferences.setMockInitialValues({_profileKey: '{"name":"홍길동"}'});
      final repo = MyProfileRepository();
      await _settle();

      expect(repo.localReadFailed, isFalse);
      expect(repo.profile.name, '홍길동', reason: '실제로 읽혔는지까지 본다');
    });

    test('저장된 것이 아예 없으면 「못 읽었다」가 아니다 — 첫 실행', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = MyProfileRepository();
      await _settle();

      expect(
        repo.localReadFailed,
        isFalse,
        reason: '처음 쓰는 사람에게 「프로필을 열지 못했어요」를 보여주면 안 된다',
      );
    });
  });

  group('GroupsRepository', () {
    test('🚨 못 읽었으면 「없다」가 아니라 「못 읽었다」로 남는다', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: _unreadable});
      final repo = GroupsRepository();
      await _settle();

      await repo.setCurrentUid('uid_test');
      await _settle();

      expect(repo.groups, isEmpty, reason: '못 읽었으니 목록은 비어 있다');
      expect(
        repo.localReadFailed,
        isTrue,
        reason: '🚨 비어 있는 이유가 「없어서」가 아니라 「못 읽어서」임을 화면이 알아야 한다',
      );
    });

    test('🚨 못 읽은 상태에서는 저장이 원본을 덮지 않는다 — 공개 경로로 실제 저장을 시킨다', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: _unreadable});
      final repo = GroupsRepository();
      await _settle();
      await repo.setCurrentUid('uid_test');
      await _settle();
      expect(repo.localReadFailed, isTrue, reason: '전제 — 못 읽은 상태여야 한다');

      // ⭐ 이용자가 그룹을 하나 만드는 것과 같은 경로다(`_persist` → `_saveToDisk`).
      repo.createGroup('덮어쓰기 시도');
      await _settle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(_groupsKey),
        _unreadable,
        reason: '⭐ 못 읽은 암호문이 그대로 남아야 나중에 키가 돌아왔을 때 열 수 있다',
      );
    });

    test('정상적으로 읽히면 「못 읽었다」가 아니다 — 대조군', () async {
      SharedPreferences.setMockInitialValues({_groupsKey: '[]'});
      final repo = GroupsRepository();
      await _settle();

      expect(repo.localReadFailed, isFalse);
    });

    test('저장된 것이 아예 없으면 「못 읽었다」가 아니다 — 첫 실행', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = GroupsRepository();
      await _settle();

      expect(
        repo.localReadFailed,
        isFalse,
        reason: '처음 쓰는 사람에게 「그룹을 열지 못했어요」를 보여주면 안 된다',
      );
    });
  });
}
