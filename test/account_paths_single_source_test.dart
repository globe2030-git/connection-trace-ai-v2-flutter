// 명함첩 경로를 한 군데에서만 조립한다는 것을 못 박는 검사
// (2026-09-05, 계정 식별 C안 1단계).
//
// 무엇을 지키려는 검사인가:
// ① **`users/` 를 조립하는 곳이 한 군데뿐이다** — 계정 식별 C안이 들어오면
//    명함첩이 `users/{uid}/contacts` 에서 `people/{personId}/contacts` 로
//    옮겨간다(`docs/planning/data-schema.md`). 그날 고칠 곳이 열몇 군데면
//    **그중 하나는 빠뜨린다.** 빠뜨린 자리는 조용히 옛 경로를 읽으므로
//    화면에는 "명함이 없다"로 보이고, 원인을 찾기 어렵다.
// ② **새로 늘어나는 것을 막는다** — 오늘 모아 놓아도 내일 누가 다시
//    `collection('users')` 를 쓰면 원래대로 흩어진다. 이 저장소는 그런
//    식으로 되돌아간 전례가 있다.
//
// ⚠️ 왜 경로 문자열을 직접 안 재는가: `FirebaseFirestore` 를 테스트에서
// 만들려면 Firebase 초기화가 필요한데 이 저장소에는 가짜 Firestore 가 없다.
// 그래서 **런타임 값 대신 소스**를 잰다 — 지키려는 성질이 애초에
// "부르는 자리가 몇 군데냐"이므로, 소스를 세는 것이 오히려 곧바른 방법이다.
//
// 🚨 이 검사가 깨졌다면 코드를 고치기 전에 이것부터 물을 것:
// **새로 쓴 그 자리가 정말 `users/` 여야 하는가, 아니면
// `AccountPaths` 에 함수를 하나 더 내야 하는가?**
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 경로 조립이 허용되는 유일한 파일.
const _theOnePlace = 'lib/core/utils/account_paths.dart';

/// `collection('users')` 또는 `collection("users")` 를 찾는다.
final _assemblesUsersPath = RegExp(r"""collection\(\s*['"]users['"]\s*\)""");

List<File> _dartFilesUnderLib() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('명함첩 경로는 한 군데에서만 조립한다', () {
    test('AccountPaths 말고는 users/ 를 조립하지 않는다', () {
      final offenders = <String>[];

      for (final file in _dartFilesUnderLib()) {
        final path = file.path.replaceAll(r'\', '/');
        if (path == _theOnePlace) continue;

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_assemblesUsersPath.hasMatch(lines[i])) {
            offenders.add('$path:${i + 1}  ${lines[i].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'users/ 경로를 직접 조립한 자리가 있습니다. $_theOnePlace 의 '
            'AccountPaths 를 쓰거나, 없는 경로라면 거기에 함수를 더하십시오.\n'
            '${offenders.join('\n')}',
      );
    });

    test('그 한 군데는 실제로 있고, 네 자리를 낸다', () {
      final file = File(_theOnePlace);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$_theOnePlace 가 없습니다. 옮겼다면 이 검사의 상수도 함께 고치십시오.',
      );

      final source = file.readAsStringSync();
      // 계정 문서 하나 + 사람에게 딸려 옮겨갈 컬렉션 셋.
      for (final name in const [
        'account',
        'contacts',
        'cardSources',
        'deletedContacts',
      ]) {
        expect(
          source,
          contains('static '),
          reason: 'AccountPaths 가 static 진입점을 내야 합니다.',
        );
        expect(
          source.contains(' $name('),
          isTrue,
          reason:
              'AccountPaths.$name 이 없습니다. 지웠다면 부르는 쪽이 다시 '
              '문자열을 조립하고 있지 않은지 확인하십시오.',
        );
      }
    });

    test('조립은 오직 한 줄에서만 일어난다', () {
      final source = File(_theOnePlace).readAsStringSync();
      final matches = _assemblesUsersPath.allMatches(source);

      // 하위 컬렉션들은 account() 를 거쳐야 한다 — 각자 users/ 를 다시
      // 조립하면 옮길 때 또 여러 군데를 고치게 된다.
      expect(
        matches.length,
        1,
        reason:
            'AccountPaths 안에서도 users/ 조립은 account() 한 곳뿐이어야 합니다. '
            '지금 ${matches.length}곳입니다.',
      );
    });
  });
}
