/// Battery information included with position updates.
class BatteryInfo {
  /// Battery level as a fraction (0.0-1.0).
  final double level;

  /// Whether the device is currently charging.
  final bool isCharging;

  const BatteryInfo({
    required this.level,
    required this.isCharging,
  });

  factory BatteryInfo.fromMap(Map<String, dynamic> map) {
    return BatteryInfo(
      level: (map['level'] as num?)?.toDouble() ?? -1.0,
      isCharging: map['isCharging'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'level': level,
      'isCharging': isCharging,
    };
  }

  @override
  String toString() =>
      'BatteryInfo(level: ${(level * 100).toStringAsFixed(0)}%, charging: $isCharging)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatteryInfo &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          isCharging == other.isCharging;

  @override
  int get hashCode => level.hashCode ^ isCharging.hashCode;
}
