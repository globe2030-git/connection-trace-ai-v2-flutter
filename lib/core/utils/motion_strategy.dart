enum BatteryMode { adaptive, saver, realtime }

class MotionStrategy {
  static String getModeLabel(BatteryMode mode) {
    switch (mode) {
      case BatteryMode.adaptive:
        return '⚡ 스마트 모션 최적화 (보행: 2분 / 정지: 15분 / 차량: 5분)';
      case BatteryMode.saver:
        return '🔋 배터리 절약 모드 (10분 주기)';
      case BatteryMode.realtime:
        return '📍 실시간 보행 모드 (2분 주기)';
    }
  }

  static Duration getPollingInterval(BatteryMode mode, String activity) {
    if (mode == BatteryMode.saver) return const Duration(minutes: 10);
    if (mode == BatteryMode.realtime) return const Duration(minutes: 2);

    // Adaptive mode
    if (activity == 'STATIONARY') return const Duration(minutes: 15);
    if (activity == 'IN_VEHICLE') return const Duration(minutes: 5);
    return const Duration(minutes: 2); // WALKING
  }
}
