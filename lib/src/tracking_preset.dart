import 'models/location_config.dart';
import 'models/notification_config.dart';
import 'enums/accuracy.dart';
import 'enums/tracking_mode.dart';
import 'enums/activity_type.dart';
import 'enums/log_level.dart';
import 'enums/location_authorization.dart';
import 'models/permission_rationale.dart';

/// Simple tracking presets that auto-configure all underlying parameters.
///
/// Each preset encodes best practices for battery/accuracy tradeoffs so
/// developers don't have to think about 15+ config params.
enum TrackingPreset {
  /// Battery sipping (~1%/day). Significant location changes only, ~500m resolution.
  /// For "I just want my friends to know roughly where I am."
  low,

  /// The default — good for most apps (~2-4%/day). Reliable background tracking,
  /// reasonable accuracy, smart motion detection. 90% of apps should use this.
  balanced,

  /// Active tracking (~5-8%/day). For navigation, fitness, delivery drivers.
  /// Frequent GPS updates, tight distance filter.
  high,
}

/// Internal configuration tables for each preset.
///
/// Each preset defines configs for three states: moving, stationary, and
/// foreground override. The auto-adaptation engine selects the right sub-config
/// based on current app lifecycle and detected motion activity.
class PresetConfig {
  const PresetConfig._();

  /// Returns a fully configured [LocationConfig] for the given preset.
  ///
  /// This is the "base" config used for `startTracking()`. The auto-adaptation
  /// engine will then call `setConfig()` with activity/lifecycle adjustments.
  static LocationConfig baseConfig(
    TrackingPreset preset, {
    NotificationConfig? notification,
    PermissionRationale? backgroundPermissionRationale,
    bool stopOnTerminate = false,
    bool startOnBoot = true,
    bool enableHeadless = true,
    bool debug = false,
    LogLevel logLevel = LogLevel.off,
  }) {
    switch (preset) {
      case TrackingPreset.low:
        return LocationConfig(
          accuracy: Accuracy.low,
          intervalMs: 300000, // 5 min
          distanceFilter: 500.0,
          mode: TrackingMode.passive,
          enableMotionDetection: true,
          stopOnTerminate: stopOnTerminate,
          startOnBoot: startOnBoot,
          enableHeadless: enableHeadless,
          stopTimeout: 15, // 15 min before stationary
          stopDetectionDelay: 10,
          stationaryRadius: 200.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: true,
          isMoving: false,
          activityRecognitionInterval: 30000, // 30s
          minimumActivityRecognitionConfidence: 85,
          heartbeatInterval: 1800, // 30 min
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: true,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 50,
          debug: debug,
          logLevel: logLevel,
          notification: notification,
          backgroundPermissionRationale: backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 500.0,
          maxSpeed: 83.33,
        );

      case TrackingPreset.balanced:
        return LocationConfig(
          accuracy: Accuracy.high,
          intervalMs: 60000, // 1 min
          distanceFilter: 50.0,
          mode: TrackingMode.balanced,
          enableMotionDetection: true,
          stopOnTerminate: stopOnTerminate,
          startOnBoot: startOnBoot,
          enableHeadless: enableHeadless,
          stopTimeout: 5, // 5 min before stationary
          stopDetectionDelay: 2,
          stationaryRadius: 50.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: false,
          isMoving: false,
          activityRecognitionInterval: 15000, // 15s
          minimumActivityRecognitionConfidence: 75,
          heartbeatInterval: 1200, // 20 min
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: true,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 100,
          debug: debug,
          logLevel: logLevel,
          notification: notification,
          backgroundPermissionRationale: backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 100.0,
          maxSpeed: 83.33,
        );

      case TrackingPreset.high:
        return LocationConfig(
          accuracy: Accuracy.high,
          intervalMs: 15000, // 15s
          distanceFilter: 10.0,
          mode: TrackingMode.active,
          enableMotionDetection: true,
          stopOnTerminate: stopOnTerminate,
          startOnBoot: startOnBoot,
          enableHeadless: enableHeadless,
          stopTimeout: 3, // 3 min before stationary
          stopDetectionDelay: 1,
          stationaryRadius: 25.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: false,
          isMoving: false,
          activityRecognitionInterval: 10000, // 10s
          minimumActivityRecognitionConfidence: 70,
          heartbeatInterval: 300, // 5 min
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: false,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 200,
          debug: debug,
          logLevel: logLevel,
          notification: notification,
          backgroundPermissionRationale: backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 50.0,
          maxSpeed: 83.33,
        );
    }
  }

  /// Returns config adjustments for activity-based adaptation within a preset.
  ///
  /// Returns a partial config (as a map of overrides) based on detected activity.
  /// The adaptation engine applies these on top of the base config.
  static _ActivityOverrides activityOverrides(TrackingPreset preset, String activity) {
    switch (preset) {
      case TrackingPreset.low:
        // Low preset: minimal adaptation — just tweak heartbeat
        switch (activity) {
          case 'in_vehicle':
            return _ActivityOverrides(distanceFilter: 300, accuracy: Accuracy.balanced, heartbeatInterval: 1200);
          case 'on_bicycle':
          case 'running':
          case 'walking':
          case 'on_foot':
            return _ActivityOverrides(distanceFilter: 400, accuracy: Accuracy.low, heartbeatInterval: 1500);
          case 'still':
          default:
            return _ActivityOverrides(distanceFilter: 500, accuracy: Accuracy.low, heartbeatInterval: 1800);
        }

      case TrackingPreset.balanced:
        switch (activity) {
          case 'in_vehicle':
            return _ActivityOverrides(distanceFilter: 100, accuracy: Accuracy.balanced, heartbeatInterval: 600);
          case 'on_bicycle':
            return _ActivityOverrides(distanceFilter: 30, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'running':
            return _ActivityOverrides(distanceFilter: 20, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'walking':
          case 'on_foot':
            return _ActivityOverrides(distanceFilter: 30, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'still':
          default:
            return _ActivityOverrides(distanceFilter: 200, accuracy: Accuracy.balanced, heartbeatInterval: 1200);
        }

      case TrackingPreset.high:
        switch (activity) {
          case 'in_vehicle':
            return _ActivityOverrides(distanceFilter: 20, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'on_bicycle':
            return _ActivityOverrides(distanceFilter: 10, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'running':
            return _ActivityOverrides(distanceFilter: 5, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'walking':
          case 'on_foot':
            return _ActivityOverrides(distanceFilter: 5, accuracy: Accuracy.high, heartbeatInterval: 300);
          case 'still':
          default:
            return _ActivityOverrides(distanceFilter: 50, accuracy: Accuracy.high, heartbeatInterval: 300);
        }
    }
  }

  /// Returns config adjustments for foreground mode (tighter tracking).
  static _LifecycleOverrides foregroundOverrides(TrackingPreset preset) {
    switch (preset) {
      case TrackingPreset.low:
        return _LifecycleOverrides(
          distanceFilter: 200,
          accuracy: Accuracy.balanced,
          heartbeatInterval: 900,
          intervalMs: 120000,
        );
      case TrackingPreset.balanced:
        return _LifecycleOverrides(
          distanceFilter: 10,
          accuracy: Accuracy.high,
          heartbeatInterval: 300,
          intervalMs: 15000,
        );
      case TrackingPreset.high:
        return _LifecycleOverrides(
          distanceFilter: 5,
          accuracy: Accuracy.navigation,
          heartbeatInterval: 120,
          intervalMs: 5000,
        );
    }
  }

  /// Returns config adjustments for background mode (relaxed for battery).
  static _LifecycleOverrides backgroundOverrides(TrackingPreset preset) {
    switch (preset) {
      case TrackingPreset.low:
        return _LifecycleOverrides(
          distanceFilter: 500,
          accuracy: Accuracy.low,
          heartbeatInterval: 1800,
          intervalMs: 300000,
        );
      case TrackingPreset.balanced:
        return _LifecycleOverrides(
          distanceFilter: 50,
          accuracy: Accuracy.high,
          heartbeatInterval: 1200,
          intervalMs: 60000,
        );
      case TrackingPreset.high:
        return _LifecycleOverrides(
          distanceFilter: 10,
          accuracy: Accuracy.high,
          heartbeatInterval: 300,
          intervalMs: 15000,
        );
    }
  }
}

class _ActivityOverrides {
  final double distanceFilter;
  final Accuracy accuracy;
  final int heartbeatInterval;

  const _ActivityOverrides({
    required this.distanceFilter,
    required this.accuracy,
    required this.heartbeatInterval,
  });
}

class _LifecycleOverrides {
  final double distanceFilter;
  final Accuracy accuracy;
  final int heartbeatInterval;
  final int intervalMs;

  const _LifecycleOverrides({
    required this.distanceFilter,
    required this.accuracy,
    required this.heartbeatInterval,
    required this.intervalMs,
  });
}
