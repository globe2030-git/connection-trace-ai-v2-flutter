/// **저장된 명함을 못 읽었을 때, 그것을 「없다」로 다루지 않는다** (2026-09-04).
///
/// ## 무엇이 문제였나
///
/// 복호화에 실패하면 `debugPrint` 한 줄을 남기고 **빈 목록으로 시작**했다.
/// 크래시를 막은 판단 자체는 옳은데 거기서 멈췄다 — `debugPrint` 는
/// **릴리스에서 아무 데도 안 나오므로** 화면은 그냥 비어 있고 아무 말도
/// 하지 않는다.
///
/// 🚨 **그리고 오해로 끝나지 않는다.** 빈 목록인 채로 저장이 한 번 돌면
/// **열지 못한 암호문을 덮어쓴다.** 그때는 되돌릴 방법이 없다.
///
/// ```
/// ① 기기의 키가 없다(재설치 등)
/// ② 서버에서 키를 못 받는다 → 새 키가 발급된다
/// ③ 기존 암호문이 안 열린다 → 빈 목록
/// ④ 저장이 한 번 돌면 새 키로 덮어쓴다
/// ⑤ 🚨 명함이 진짜로 사라진다
/// ```
///
/// **이 테스트가 지키는 것은 ④를 막는 것**이다.
library;

import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storageKey = 'saved_contacts_v2';

/// 평문 JSON 도 아니고 이 기기의 키로 열리지도 않는 값 — 「못 읽는 상태」다.
const _unreadable = 'bm90LWEtdmFsaWQtY2lwaGVydGV4dA==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨 못 읽었으면 「없다」가 아니라 「못 읽었다」로 남는다', () async {
    SharedPreferences.setMockInitialValues({_storageKey: _unreadable});
    final repo = ContactsRepository();
    await Future<void>.delayed(Duration.zero);

    // uid 가 생겨야 복호화를 시도한다(그 전에는 판단을 미룬다).
    await repo.setCurrentUid('uid_test');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.contacts, isEmpty, reason: '못 읽었으니 목록은 비어 있다');
    expect(
      repo.localReadFailed,
      isTrue,
      reason: '🚨 비어 있는 이유가 「없어서」가 아니라 「못 읽어서」임을 화면이 알아야 한다',
    );
  });

  // ⚠️ **이 테스트의 한계를 적어 둔다.** 여기서 보는 것은 「원본이 남아
  // 있다」는 **결과**이지, 「저장 차단 분기를 탔다」는 **경로**가 아니다.
  // `_saveToDisk` 는 private 이고, 그것을 확실히 트리거하는 공개 경로가
  // 지금은 마땅치 않다.
  //
  // 📌 그래도 남기는 이유: 이 값이 바뀌면(원본이 덮이면) **여기서 깨진다.**
  // 경로를 못 재도 결과는 잠근다. 나중에 명함 추가 같은 공개 경로가 잡히면
  // 그때 이 테스트를 그쪽으로 바꾸는 것이 낫다.
  test('🚨 못 읽은 상태에서는 저장이 원본을 덮지 않는다', () async {
    SharedPreferences.setMockInitialValues({_storageKey: _unreadable});
    final repo = ContactsRepository();
    await Future<void>.delayed(Duration.zero);

    await repo.setCurrentUid('uid_test');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.localReadFailed, isTrue);

    // 저장이 돌 만한 일을 시킨다.
    await repo.setCurrentUid('uid_test');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(_storageKey),
      _unreadable,
      reason: '⭐ 못 읽은 암호문이 그대로 남아야 나중에 키가 돌아왔을 때 열 수 있다',
    );
  });

  test('정상적으로 읽히면 「못 읽었다」가 아니다 — 대조군', () async {
    // 레거시 평문 저장분은 키 없이도 읽힌다.
    SharedPreferences.setMockInitialValues({_storageKey: '[]'});
    final repo = ContactsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.localReadFailed, isFalse);
  });

  test('저장된 것이 아예 없으면 「못 읽었다」가 아니다 — 첫 실행', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = ContactsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      repo.localReadFailed,
      isFalse,
      reason: '처음 쓰는 사람에게 「명함을 열지 못했어요」를 보여주면 안 된다',
    );
  });
}
