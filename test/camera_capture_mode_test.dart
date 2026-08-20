// 자동↔수동 촬영 전환의 핵심 분기 회귀 방지.
//
// 자동 촬영이라는 기존 설계는 갈아엎지 않고, 수동 전환을 공존 옵션으로
// 추가한다(사용자 확정). 이 테스트가 지키는 것은 딱 하나 — **수동 모드에서는
// 안정성 조건이 맞아도 자동으로 찍히면 안 된다.**
import 'package:connection_trace_ai_flutter/core/utils/camera_capture_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldTriggerAutoCapture', () {
    test('자동 모드 + 안정됨 → 찍는다(기존 동작)', () {
      expect(
        shouldTriggerAutoCapture(
          mode: CameraCaptureMode.auto,
          stabilityConditionMet: true,
        ),
        isTrue,
      );
    });

    test('자동 모드 + 안 안정됨 → 안 찍는다', () {
      expect(
        shouldTriggerAutoCapture(
          mode: CameraCaptureMode.auto,
          stabilityConditionMet: false,
        ),
        isFalse,
      );
    });

    test('수동 모드 + 안정됨 → 그래도 안 찍는다(핵심 회귀 방지)', () {
      expect(
        shouldTriggerAutoCapture(
          mode: CameraCaptureMode.manual,
          stabilityConditionMet: true,
        ),
        isFalse,
      );
    });

    test('수동 모드 + 안 안정됨 → 안 찍는다', () {
      expect(
        shouldTriggerAutoCapture(
          mode: CameraCaptureMode.manual,
          stabilityConditionMet: false,
        ),
        isFalse,
      );
    });
  });

  group('CameraCaptureMode 토글', () {
    test('자동 → 수동', () {
      expect(CameraCaptureMode.auto.toggled, CameraCaptureMode.manual);
    });

    test('수동 → 자동', () {
      expect(CameraCaptureMode.manual.toggled, CameraCaptureMode.auto);
    });

    test('isManual / isAuto', () {
      expect(CameraCaptureMode.auto.isAuto, isTrue);
      expect(CameraCaptureMode.auto.isManual, isFalse);
      expect(CameraCaptureMode.manual.isManual, isTrue);
      expect(CameraCaptureMode.manual.isAuto, isFalse);
    });
  });
}
