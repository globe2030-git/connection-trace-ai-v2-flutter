import '../../core/utils/motion_strategy.dart';

class NotificationSettings {
  final bool enabled;
  final double radiusMeters;
  final BatteryMode batteryMode;

  const NotificationSettings({
    this.enabled = true,
    this.radiusMeters = double.infinity,
    this.batteryMode = BatteryMode.adaptive,
  });

  NotificationSettings copyWith({
    bool? enabled,
    double? radiusMeters,
    BatteryMode? batteryMode,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      batteryMode: batteryMode ?? this.batteryMode,
    );
  }
}
