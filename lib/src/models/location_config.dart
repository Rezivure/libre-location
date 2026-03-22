import '../enums/accuracy.dart';
import '../enums/tracking_mode.dart';

/// Configuration for background location tracking.
class LocationConfig {
  /// The desired accuracy level.
  final Accuracy accuracy;

  /// Minimum time interval between updates in milliseconds.
  final int intervalMs;

  /// Minimum distance change between updates in meters.
  final double distanceFilter;

  /// The tracking mode that balances accuracy vs battery.
  final TrackingMode mode;

  /// Whether to use accelerometer-based motion detection
  /// to pause/resume GPS polling when stationary.
  final bool enableMotionDetection;

  /// Title for the Android foreground service notification.
  final String? notificationTitle;

  /// Body text for the Android foreground service notification.
  final String? notificationBody;

  const LocationConfig({
    this.accuracy = Accuracy.high,
    this.intervalMs = 60000,
    this.distanceFilter = 10.0,
    this.mode = TrackingMode.balanced,
    this.enableMotionDetection = true,
    this.notificationTitle,
    this.notificationBody,
  });

  /// Converts this config to a map for platform communication.
  Map<String, dynamic> toMap() {
    return {
      'accuracy': accuracy.index,
      'intervalMs': intervalMs,
      'distanceFilter': distanceFilter,
      'mode': mode.index,
      'enableMotionDetection': enableMotionDetection,
      'notificationTitle': notificationTitle,
      'notificationBody': notificationBody,
    };
  }

  /// Creates a [LocationConfig] from a platform-specific map.
  factory LocationConfig.fromMap(Map<String, dynamic> map) {
    return LocationConfig(
      accuracy: Accuracy.values[map['accuracy'] as int? ?? 0],
      intervalMs: map['intervalMs'] as int? ?? 60000,
      distanceFilter: (map['distanceFilter'] as num?)?.toDouble() ?? 10.0,
      mode: TrackingMode.values[map['mode'] as int? ?? 1],
      enableMotionDetection: map['enableMotionDetection'] as bool? ?? true,
      notificationTitle: map['notificationTitle'] as String?,
      notificationBody: map['notificationBody'] as String?,
    );
  }
}
