/// 묶음 마커 라벨(`_GroupPin`, 추가 445)의 화면 폭을 실제로 재는 부품
/// (추가 452).
///
/// [nearby_map_label_collision.dart]의 충돌 판정은 이 값을 받아 쓰기만 하고
/// 직접 재지는 않는다 — `TextPainter`로 글자 폭을 재는 건 카메라 이동·확대와
/// 무관한 계산이라, 인맥 데이터가 바뀔 때(마커 목록을 다시 만들 때)만 한 번
/// 돌리면 된다. 지도를 움직일 때마다 다시 재면 매 프레임 텍스트 레이아웃을
/// 돌리는 셈이라 느려질 수 있다 — 그래서 이 파일과 충돌 판정 파일을 갈랐다.
library;

import 'package:flutter/painting.dart';

/// `_GroupPin`(nearby_map_view.dart)의 알약 라벨이 쓰는 스타일. 라벨 폭을
/// 실제 렌더링과 다르게 재면 충돌 판정이 화면과 어긋나므로, 위젯의 스타일이
/// 바뀌면 이 값도 함께 고쳐야 한다.
const double kGroupLabelFontSize = 10.5;
const FontWeight kGroupLabelFontWeight = FontWeight.w800;

/// `_GroupPin` 알약의 좌우 패딩 합(8+8). 테두리(`Border.all`)는 위젯 박스
/// 안쪽에 그려져 폭에 더해지지 않으므로 계산에 넣지 않는다.
const double kGroupLabelHorizontalPadding = 16;

/// `_GroupPin` 알약의 `BoxConstraints(maxWidth: ...)`와 반드시 같은 값이어야
/// 한다 — 실제로 그 폭에서 말줄임(ellipsis)되므로, 여기서도 같은 상한으로
/// 잘라야 충돌 판정이 실제 화면과 맞는다.
const double kGroupLabelMaxWidth = 148;

/// 대표 회사명(또는 "같은 주소 N명") [text]가 실제로 화면에서 차지할 폭(dp).
///
/// `_GroupPin`과 같은 글꼴·패딩으로 재고, 같은 최대 폭에서 자른다 — 실제
/// 위젯이 말줄임되는 지점과 다르게 재면 충돌 판정이 화면과 어긋난다.
double measureGroupLabelWidth(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: kGroupLabelFontSize,
        fontWeight: kGroupLabelFontWeight,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final raw = painter.width + kGroupLabelHorizontalPadding;
  return raw > kGroupLabelMaxWidth ? kGroupLabelMaxWidth : raw;
}
