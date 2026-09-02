import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 일괄 스캔 내보내기(TSV)의 **머리글과 값의 자리가 어긋나지 않게** 고정한다.
///
/// ## 왜 필요한가
///
/// 이 파일은 `_buildTsv()` 안에서 **머리글 목록과 값 목록을 따로** 만든다.
/// 한쪽에만 칸을 더하면 **그 뒤의 모든 칸이 한 자리씩 밀린다.**
///
/// 🚨 **밀려도 파일은 멀쩡해 보인다.** 탭으로 나뉜 표가 그대로 열리고, 회사
/// 칸에 직함이 들어가 있을 뿐이다. 채점 도구(`tool/ocr_review/`)는 칸을
/// **이름으로** 찾으므로 잘못된 값을 **정상으로 받아들여 점수를 낸다.**
/// 그러면 파서를 안 고쳤는데 정확도가 떨어진 것처럼 보이고, 원인을 코드에서
/// 찾게 된다.
///
/// 📌 실제로 **부서 칸이 통째로 빠져 있었다**(2026-09-02 발견). 파서는
/// `department` 를 뽑고 있었고 채점 도구도 `정답_부서` 를 갖고 있었는데,
/// **내보내기에만 없어서 부서를 아예 잴 수 없었다.** 한쪽만 보면 안 보이는
/// 종류의 결함이라 테스트로 고정한다.
void main() {
  test('내보내기 머리글과 값의 칸 수가 같다', () {
    final src = File(
      'lib/presentation/features/settings/views/ocr_batch_scan_view.dart',
    ).readAsStringSync();

    final headers = _listAfter(src, "'파일명',");
    final values = _listAfter(src, 'row.fileName,');

    expect(headers, isNotEmpty, reason: '머리글 목록을 못 찾았다');
    expect(values, isNotEmpty, reason: '값 목록을 못 찾았다');
    expect(
      values.length,
      headers.length,
      reason:
          '머리글 ${headers.length}칸 · 값 ${values.length}칸 — 한쪽에만 칸을 더하면 '
          '그 뒤가 전부 한 자리씩 밀리고, 그래도 파일은 멀쩡해 보인다',
    );
  });

  test('부서 칸이 직함 다음에 있다', () {
    final src = File(
      'lib/presentation/features/settings/views/ocr_batch_scan_view.dart',
    ).readAsStringSync();
    final headers = _listAfter(src, "'파일명',");
    final i = headers.indexOf("'부서'");
    expect(i, isNot(-1), reason: '부서 칸이 없으면 채점 도구가 부서를 잴 수 없다');
    expect(
      headers[i - 1],
      "'직함'",
      reason: 'tool/ocr_review/score_matrix.py 의 ORDER 와 같은 자리여야 한다',
    );
  });
}

/// `_buildTsv()` 안의 목록 리터럴을 훑어 **항목의 첫 조각들**을 돌려준다.
///
/// 목록 안에 주석과 여러 줄짜리 식(`.map(...)`)이 섞여 있어 정규식 하나로는
/// 못 센다. 그래서 **들여쓰기가 같은 줄 중 주석이 아닌 것**만 세되, 여는
/// 괄호가 닫힐 때까지 깊이를 따라간다.
List<String> _listAfter(String src, String firstItem) {
  final start = src.indexOf(firstItem);
  if (start == -1) return const [];
  final lines = src.substring(start).split('\n');
  final baseIndent = ' ' * 10;
  final items = <String>[];
  var depth = 0;
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('//')) continue;
    // 목록의 끝 — `].join(...)` 또는 `].map(...)`
    if (depth == 0 && t.startsWith('].')) break;
    if (depth == 0 && line.startsWith(baseIndent) && !line.startsWith('$baseIndent ')) {
      items.add(t.endsWith(',') ? t.substring(0, t.length - 1) : t);
    }
    depth += '('.allMatches(line).length + '['.allMatches(line).length;
    depth -= ')'.allMatches(line).length + ']'.allMatches(line).length;
    if (depth < 0) depth = 0;
  }
  return items;
}
