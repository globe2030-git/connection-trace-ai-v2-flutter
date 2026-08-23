// 회전 즉시 미리보기 + 배경 굽기(P2-③ 2차) 상태 전이 검증.
//
// 왜 중요한가: "연타하면 회전 수만 누적하고, 굽기 큐를 따로 쌓지 않는다 —
// 도는 굽기가 끝나면 그 순간의 누적분을 한 번에 다시 굽는다"는 규칙이다.
// 화면·실제 파일 굽기 없이도 이 전이 규칙 자체를 먼저 고정해 둔다(이 화면은
// 회전×자르기 좌표계를 섞어 실기기에서 두 번 헤맨 전례가 있다, 추가 273·397).
import 'package:connection_trace_ai_flutter/core/utils/crop_rotation_bake_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('회전 누적', () {
    test('클릭 한 번 = pendingTurns 1, 아직 굽는 중은 아니다', () {
      const state = CropRotationBakeState();
      final next = state.rotatedCw();
      expect(next.pendingTurns, 1);
      expect(next.isBaking, isFalse);
    });

    test('시계 3번 = 반시계 1번과 같은 누적값(270도 = -90도)', () {
      var viaCw = const CropRotationBakeState();
      for (var i = 0; i < 3; i++) {
        viaCw = viaCw.rotatedCw();
      }
      final viaCcw = const CropRotationBakeState().rotatedCcw();
      expect(viaCw.pendingTurns, viaCcw.pendingTurns);
    });

    test('시계 4번 = 상쇄(원래대로)', () {
      var state = const CropRotationBakeState();
      for (var i = 0; i < 4; i++) {
        state = state.rotatedCw();
      }
      expect(state.pendingTurns, 0);
    });

    test('시계 한 번 + 반시계 한 번 = 상쇄', () {
      final state = const CropRotationBakeState().rotatedCw().rotatedCcw();
      expect(state.pendingTurns, 0);
    });

    test('굽는 중에도 계속 누적된다(굽기 큐를 쌓지 않고 값만 는다)', () {
      final baking = const CropRotationBakeState()
          .rotatedCw()
          .startBakeIfNeeded(); // pendingTurns=1, bakingTarget=1
      final clickedAgain = baking.rotatedCw(); // 굽는 중에 또 클릭
      expect(clickedAgain.pendingTurns, 2);
      expect(clickedAgain.bakingTarget, 1, reason: '굽기 목표는 새로 시작하기 전엔 그대로다');
    });
  });

  group('굽기 시작 판정(startBakeIfNeeded)', () {
    test('밀린 회전이 없으면 시작하지 않는다', () {
      const state = CropRotationBakeState();
      expect(state.startBakeIfNeeded().isBaking, isFalse);
    });

    test('밀린 회전이 있고 굽는 중이 아니면 그 값을 목표로 시작한다', () {
      final state = const CropRotationBakeState().rotatedCw().rotatedCw();
      final started = state.startBakeIfNeeded();
      expect(started.isBaking, isTrue);
      expect(started.bakingTarget, 2);
    });

    test('이미 굽는 중이면 다시 부르든 값이 바뀌든 목표를 안 바꾼다(한 번에 하나만)', () {
      final baking = const CropRotationBakeState()
          .rotatedCw()
          .startBakeIfNeeded(); // target=1
      final clickedMore = baking.rotatedCw().rotatedCw(); // pendingTurns=3, 아직 굽는 중
      final startedAgain = clickedMore.startBakeIfNeeded();
      expect(startedAgain.bakingTarget, 1, reason: '이미 도는 굽기의 목표를 덮어쓰면 안 된다');
      expect(startedAgain.pendingTurns, 3);
    });
  });

  group('굽기 완료 판정(bakeCompleted) — "저장 시 굽기 완료 대기"의 핵심', () {
    test('목표가 최신이면(더 안 눌렸으면) 그만큼 빼서 정착한다(보통 0)', () {
      final baking = const CropRotationBakeState()
          .rotatedCw()
          .startBakeIfNeeded(); // pendingTurns=1, target=1
      final done = baking.bakeCompleted();
      expect(done.pendingTurns, 0);
      expect(done.bakingTarget, isNull);
      expect(done.isSettled, isTrue);
    });

    test('굽는 동안 더 눌려 목표가 낡았으면 결과를 버리고 pendingTurns는 그대로 둔다', () {
      final baking = const CropRotationBakeState()
          .rotatedCw()
          .startBakeIfNeeded(); // target=1
      final staled = baking.rotatedCw().rotatedCw(); // pendingTurns=3(굽는 동안 더 눌림)
      final done = staled.bakeCompleted();
      expect(done.pendingTurns, 3, reason: '낡은 결과는 버리되 누적값 자체는 잃으면 안 된다');
      expect(done.bakingTarget, isNull, reason: '굽기 표시는 지운다 — 다음 kick이 최신 값으로 다시 건다');
      expect(done.isSettled, isFalse);
    });

    test('굽지도 않았는데 불리면 아무것도 안 한다', () {
      const state = CropRotationBakeState(pendingTurns: 2);
      final result = state.bakeCompleted();
      expect(result.pendingTurns, 2);
      expect(result.bakingTarget, isNull);
    });
  });

  group('isSettled — [자르기 확정]이 기다려야 하는지 판정', () {
    test('초기 상태는 정착', () {
      expect(const CropRotationBakeState().isSettled, isTrue);
    });

    test('밀린 회전이 있으면 정착 아님(굽는 중이 아니어도)', () {
      expect(const CropRotationBakeState().rotatedCw().isSettled, isFalse);
    });

    test('굽는 중이면 정착 아님', () {
      final baking = const CropRotationBakeState().rotatedCw().startBakeIfNeeded();
      expect(baking.isSettled, isFalse);
    });
  });

  test(
    '연타 시나리오 전체: cw, cw(굽는 중 누름), 완료(낡음→버림), 재시작, 완료(정착)',
    () {
      // 1) 첫 클릭
      var state = const CropRotationBakeState().rotatedCw();
      expect(state.pendingTurns, 1);

      // 2) kick — 배경 굽기 시작(target=1)
      state = state.startBakeIfNeeded();
      expect(state.bakingTarget, 1);

      // 3) 굽는 도중 한 번 더 클릭 — 큐를 쌓지 않고 값만 는다
      state = state.rotatedCw();
      expect(state.pendingTurns, 2);
      expect(state.bakingTarget, 1, reason: '진행 중이던 굽기 목표는 그대로');

      // 4) target=1짜리 굽기가 끝남 — 이미 낡았다(2 != 1), 결과 버림
      state = state.bakeCompleted();
      expect(state.pendingTurns, 2, reason: '누적은 그대로 남아야 다시 구울 수 있다');
      expect(state.isBaking, isFalse);

      // 5) 다시 kick — 이번엔 최신 값(2)을 통째로 목표로 삼는다(90을 두 번
      //    나눠 굽지 않고 180도를 한 번에)
      state = state.startBakeIfNeeded();
      expect(state.bakingTarget, 2);

      // 6) 이번엔 더 안 눌렸다 — 완료하면 정착
      state = state.bakeCompleted();
      expect(state.pendingTurns, 0);
      expect(state.isSettled, isTrue);
    },
  );
}
