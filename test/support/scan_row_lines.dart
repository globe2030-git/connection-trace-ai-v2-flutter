// 스캔 결과 한 줄에서 **파서에 먹일 줄 목록**을 만든다.
//
// ## 왜 따로 두나 (추가 334)
//
// 채점기와 분해기가 **같은 자를 써야** 숫자를 나란히 놓을 수 있다. 추가 322에서
// 이미 한 번 데었다 — 두 도구가 다른 자를 쓰는 바람에 팩스가 *"미검출 37건"*
// 으로 보였는데 실제로는 1건이었다. 그래서 읽는 자리를 하나로 모은다.
//
// ## 좌표
//
// 앱의 일괄 스캔은 **`좌표` 칸에 `left,top,width,height`를 `원문`과 같은 순서로**
// 내보낸다(추가 317). 그런데 두 하네스는 그동안 `원문`만 읽어서, 좌표가 결과에
// 실려 있어도 **파서까지 가지 못했다.** 좌표 규칙(R-05)을 만들어도 잴 수가 없는
// 상태였다.
//
// ⚠️ **옛 자료도 그대로 돌아가야 한다.** `좌표` 칸이 없는 파일(2026-08-17까지
// 저장된 것)이 실제로 쓰이고 있다. 그때는 좌표를 **전부 0**으로 채운다 —
// `lineBoxOf`의 규약대로 0은 "왼쪽 맨 위"가 아니라 **모른다**는 뜻이고, 좌표를
// 보는 규칙은 그런 목록을 만나면 판단을 건너뛰어야 한다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';

/// 스캔 결과 한 행(`원문`·`좌표`)에서 줄 목록을 만든다.
///
/// 좌표가 없거나 개수가 원문과 안 맞으면 **좌표 없이** 만든다(0으로 채움).
List<OcrLineBox> scanRowLines(Map<String, String> row) {
  final texts = (row['원문'] ?? '')
      .split(' ⏐ ')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (texts.isEmpty) return const [];

  final boxCells = (row['좌표'] ?? '')
      .split(' ⏐ ')
      .where((c) => c.trim().isNotEmpty)
      .toList();

  // ⚠️ 개수가 다르면 **짝이 어긋난 것**이다. 앞에서부터 맞춰 쓰면 엉뚱한 줄에
  // 엉뚱한 좌표가 붙어 조용히 틀린다 — 차라리 통째로 버린다.
  if (boxCells.length != texts.length) {
    return [for (final t in texts) lineBoxOf(t)];
  }

  final out = <OcrLineBox>[];
  for (var i = 0; i < texts.length; i++) {
    final n = boxCells[i].split(',');
    final v = n.length == 4
        ? [for (final s in n) double.tryParse(s.trim())]
        : const <double?>[];
    if (v.length != 4 || v.contains(null)) {
      // 한 줄이라도 깨졌으면 전부 버린다 — 섞이면 어느 줄이 믿을 만한지
      // 알 수 없다.
      return [for (final t in texts) lineBoxOf(t)];
    }
    out.add((
      text: texts[i],
      left: v[0]!,
      top: v[1]!,
      width: v[2]!,
      height: v[3]!,
    ));
  }
  return out;
}

/// 이 스캔 결과에 **쓸 만한 좌표가 실려 있나.** 하네스가 머리글에 찍어
/// *"좌표 없이 잰 숫자"*를 좌표 숫자로 오해하지 않게 한다.
bool scanRowHasBoxes(Map<String, String> row) {
  final lines = scanRowLines(row);
  return lines.isNotEmpty && lines.any((b) => b.width > 0 || b.top > 0);
}
