// 입력칸에 **미리 채워 둔 가짜 값**이 없는지 원본 코드를 훑어 검사한다.
//
// 왜 소스를 훑나: 이 결함은 **코드가 정상 동작하는데 데이터가 거짓인** 유형이라
// 기능 테스트로는 안 잡힌다. 화면은 잘 뜨고 저장도 잘 되며, 다만 저장된 값이
// 사용자가 넣은 것이 아닐 뿐이다. 그 화면을 열어 눈으로 보기 전까지 아무도
// 모른다(CLAUDE.md 4절 "코드 리뷰로는 안 잡히는 결함").
//
// 실제로 겪은 것:
// - 2026-08-14 명함 등록 태그 기본값이 `'AI, IT'`로 박혀 있었다. 회계사 명함을
//   등록해도 태그에 `AI`·`IT`가 저장됐다(테스터 제보, 빌드6·7 통합본 E-08).
//   ⚠️ 그 전에 코드를 훑고도 "하드코딩 기본 태그를 못 찾았다"고 기록한 적이
//   있다(추가 188) — 사람 눈으로 훑는 것을 믿을 수 없다는 근거다.
// - 2026-08-10 프로필 사진 선택이 실제로는 스톡 사진 4장을 돌려쓰고 있었다
//   (추가 49).
//
// 무엇을 금지하나: `TextEditingController(text: …)`의 **폴백 자리**에 빈 문자열이
// 아닌 리터럴이 오는 것. 즉 "저장된 값이 없을 때 대신 넣는 값"이 있으면 안 된다.
// `join(', ')` 같은 **구분자** 리터럴은 폴백이 아니므로 걸리지 않는다.
//
// 입력칸에 무엇을 적는지는 `hint`(안내 문구)로 알려야 한다 — 안내 문구는 저장되지
// 않으므로 가짜 데이터가 되지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('입력칸 기본값에 미리 채운 가짜 값이 없다', () {
    // `TextEditingController(text: <식>);`의 <식>을 통째로 집는다.
    final controller = RegExp(
      r'TextEditingController\(\s*text:(.*?)\)\s*;',
      dotAll: true,
    );
    // 폴백 자리 둘: 삼항의 else(`: '…'`)와 널 병합(`?? '…'`).
    final fallbacks = [RegExp(r":\s*'([^']*)'"), RegExp(r"\?\?\s*'([^']*)'")];

    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = file.readAsStringSync();
      for (final match in controller.allMatches(src)) {
        final expr = match.group(1)!;
        final seeded = [
          for (final re in fallbacks)
            for (final m in re.allMatches(expr))
              if (m.group(1)!.trim().isNotEmpty) m.group(1)!,
        ];
        if (seeded.isEmpty) continue;
        final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
        offenders.add(
          '${file.path}:$line — 기본값 ${seeded.join(' / ')}'
          '\n    ${expr.replaceAll(RegExp(r'\s+'), ' ').trim()}',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '입력칸에 미리 채운 값이 있으면 사용자가 넣지 않은 값이 그대로 저장된다.\n'
          '빈 값으로 두고, 무엇을 적는 칸인지는 hint(안내 문구)로 알린다.\n'
          '${offenders.join('\n')}',
    );
  });
}
