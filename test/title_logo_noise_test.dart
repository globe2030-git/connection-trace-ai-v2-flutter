// 직함 뒤에 붙어 온 **로고 잔재**를 버린다 (추가 617).
//
// 🚨 **왜 있나**: [추가 600]이 「부서를 못 얻으면 손대지 않는다」로 가면서,
// 손대지 않은 줄에 **로고가 읽힌 조각까지 그대로 남았다.** 서울관광재단 옛
// 디자인의 `I·SEOUL·U` 가 직함 뒤에 붙어 다섯 장이 틀렸다.
//
// ⚠️ **가르는 신호는 「길이」가 아니라 「한글도 직함 낱말도 없는가」다.**
// 아래 두 묶음이 그 경계를 지킨다 — 위가 무너지면 로고가 돌아오고, 아래가
// 무너지면 직함의 나머지 반쪽을 다시 잃는다([추가 593]의 회귀 셋).
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String? title(List<String> lines) =>
    OcrScannerService.parseLinesForTesting(lines).title;

void main() {
  group('로고 잔재는 버린다', () {
    for (final c in const [
      ('주임 |·SEÓUL·U', '주임'),
      ('차장 |:SEOUL·U', '차장'),
      ('과장 |:SEOUL-L', '과장'),
      ('본부장 | TS', '본부장'),
    ]) {
      test(c.$1, () => expect(title(['홍길동', c.$1]), c.$2));
    }
  });

  group('🚨 직함의 나머지 반쪽은 남긴다 — 여기가 무너지면 추가 593 회귀다', () {
    for (final c in const [
      ('대표이사 | CEO', '대표이사 | CEO'),
      ('이사장 / President CEO', '이사장 / President CEO'),
      ('대표/공인중개사', '대표/공인중개사'),
    ]) {
      test(c.$1, () => expect(title(['홍길동', c.$1]), c.$2));
    }
  });
}
