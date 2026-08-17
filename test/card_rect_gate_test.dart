// 자동 촬영 관문(E-01, 추가 293).
//
// ⚠️ 이 판단이 틀리면 증상이 *"빈 벽이 그냥 찍힌다"* 또는 *"자동으로 안
// 찍힌다"* 하나로만 나타나고, 원인은 실기기에서 한참 뒤에야 드러난다.
// 그래서 화면 상태에서 빼내 여기서 고정한다.
//
// ## 이 검사들이 지키는 것
//
// 처음에는 *"몇 초 안에 못 잡으면 조건을 풀어 준다"*로 만들었다가 **실기기에서
// 빈 벽과 손바닥이 6초 뒤 그대로 찍혔다.** 유예가 곧 *"6초 뒤에는 아무거나
// 찍는다"*였다. 그래서 **시간이 아니라 검출기 상태로** 정하게 바꿨다.
import 'package:connection_trace_ai_flutter/core/utils/card_quad_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool gate({
    bool supported = true,
    bool disabled = false,
    bool answering = true,
  }) => requiresCardRectGate(
    supported: supported,
    detectorDisabled: disabled,
    detectorAnswering: answering,
  );

  group('⭐ 검출기가 살아 있으면 명함을 요구한다', () {
    test('답하고 있으면 요구한다 — 못 잡는 것은 "거기 명함이 없다"는 뜻이다', () {
      expect(gate(answering: true), isTrue);
    });

    test('📌 시간이 지나도 풀리지 않는다 — 빈 벽을 오래 비춰도 안 찍힌다', () {
      // 예전에는 6초 뒤 풀려서 **막으려던 것이 그대로 통과했다.**
      // 이 함수에는 이제 시간 인자가 아예 없다. 그것이 이 검사의 요지다.
      expect(gate(answering: true), isTrue);
    });
  });

  group('⚠️ 못 쓰는 장치로 사용자를 막지 않는다', () {
    test('아직 첫 답이 안 왔으면 요구하지 않는다 — 화면을 막 연 순간', () {
      expect(gate(answering: false), isFalse);
    });

    test('검출기가 없거나 오류면 요구하지 않는다', () {
      expect(gate(answering: false), isFalse);
    });

    test('지원하지 않는 플랫폼이면 요구하지 않는다', () {
      expect(gate(supported: false), isFalse);
    });

    test('사용자가 검출을 껐으면 요구하지 않는다', () {
      // ⚠️ 이게 없으면 검출을 끈 사용자가 **자동 촬영을 통째로 잃는다.**
      expect(gate(disabled: true), isFalse);
    });

    test('꺼져 있으면 검출기가 살아 있어도 요구하지 않는다', () {
      expect(gate(disabled: true, answering: true), isFalse);
    });
  });
}
