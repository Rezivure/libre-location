import 'activity_event.dart';
import 'battery_info.dart';

/// Represents a geographic position with metadata.
class Position {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final double speed;
  final double heading;
  final DateTime timestamp;
  final String provider;
  final bool isMoving;
  final ActivityEvent? activity;
  final BatteryInfo? battery;
  final double? speedAccuracy;
  final double? headingAccuracy;

  const Position({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.accuracy = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    required this.timestamp,
    this.provider = 'unknown',
    this.isMoving = false,
    this.activity,
    this.battery,
    this.speedAccuracy,
    this.headingAccuracy,
  });

  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num).toInt(),
      ),
      provider: map['provider'] as String? ?? 'unknown',
      isMoving: map['isMoving'] as bool? ?? false,
      activity: map['activity'] != null
          ? ActivityEvent.fromMap(Map<String, dynamic>.from(map['activity'] as Map))
          : null,
      battery: _parseBattery(map),
      speedAccuracy: (map['speedAccuracy'] as num?)?.toDouble(),
      headingAccuracy: (map['headingAccuracy'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'provider': provider,
      'isMoving': isMoving,
      if (activity != null) 'activity': activity!.toMap(),
      if (battery != null) 'battery': battery!.toMap(),
      if (speedAccuracy != null) 'speedAccuracy': speedAccuracy,
      if (headingAccuracy != null) 'headingAccuracy': headingAccuracy,
    };
  }

  Position copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    double? accuracy,
    double? speed,
    double? heading,
    DateTime? timestamp,
    String? provider,
    bool? isMoving,
    ActivityEvent? activity,
    BatteryInfo? battery,
    double? speedAccuracy,
    double? headingAccuracy,
  }) {
    return Position(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      accuracy: accuracy ?? this.accuracy,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      provider: provider ?? this.provider,
      isMoving: isMoving ?? this.isMoving,
      activity: activity ?? this.activity,
      battery: battery ?? this.battery,
      speedAccuracy: speedAccuracy ?? this.speedAccuracy,
      headingAccuracy: headingAccuracy ?? this.headingAccuracy,
    );
  }

  /// Parses battery info from either a nested 'battery' map or top-level
  /// 'batteryLevel' / 'isCharging' keys sent by native platforms.
  static BatteryInfo? _parseBattery(Map<String, dynamic> map) {
    if (map['battery'] != null) {
      return BatteryInfo.fromMap(Map<String, dynamic>.from(map['battery'] as Map));
    }
    // Native sends batteryLevel (0-100 int) and isCharging (bool) as top-level keys
    final batteryLevel = map['batteryLevel'];
    if (batteryLevel != null) {
      return BatteryInfo(
        level: (batteryLevel as num).toDouble() / 100.0,
        isCharging: map['isCharging'] as bool? ?? false,
      );
    }
    return null;
  }

  @override
  String toString() =>
      'Position(lat: $latitude, lng: $longitude, acc: ${accuracy}m, moving: $isMoving, provider: $provider)';
}
