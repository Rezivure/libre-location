import 'models/native_config.dart';
import 'models/location_config.dart';
import 'enums/accuracy.dart';
import 'enums/tracking_mode.dart';
import 'enums/activity_type.dart';
import 'enums/log_level.dart';
import 'enums/location_authorization.dart';

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

  /// Returns a fully configured [NativeConfig] for the given preset,
  /// merging in the developer's [LocationConfig] overrides.
  static NativeConfig buildNativeConfig(
    TrackingPreset preset,
    LocationConfig config,
  ) {
    switch (preset) {
      case TrackingPreset.low:
        return NativeConfig(
          accuracy: Accuracy.low,
          intervalMs: 300000,
          distanceFilter: 500.0,
          mode: TrackingMode.passive,
          enableMotionDetection: true,
          stopOnTerminate: config.stopOnTerminate,
          startOnBoot: config.startOnBoot,
          enableHeadless: config.enableHeadless,
          stopTimeout: 15,
          stopDetectionDelay: 10,
          stationaryRadius: 200.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: true,
          isMoving: false,
          activityRecognitionInterval: 30000,
          minimumActivityRecognitionConfidence: 85,
          heartbeatInterval: 1800,
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: true,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 50,
          debug: config.debug,
          logLevel: config.debug ? LogLevel.debug : LogLevel.off,
          notification: config.notification,
          backgroundPermissionRationale: config.backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 500.0,
          maxSpeed: 83.33,
        );

      case TrackingPreset.balanced:
        return NativeConfig(
          accuracy: Accuracy.high,
          intervalMs: 60000,
          distanceFilter: 50.0,
          mode: TrackingMode.balanced,
          enableMotionDetection: true,
          stopOnTerminate: config.stopOnTerminate,
          startOnBoot: config.startOnBoot,
          enableHeadless: config.enableHeadless,
          stopTimeout: 5,
          stopDetectionDelay: 2,
          stationaryRadius: 50.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: false,
          isMoving: false,
          activityRecognitionInterval: 15000,
          minimumActivityRecognitionConfidence: 75,
          heartbeatInterval: 1200,
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: true,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 100,
          debug: config.debug,
          logLevel: config.debug ? LogLevel.debug : LogLevel.off,
          notification: config.notification,
          backgroundPermissionRationale: config.backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 100.0,
          maxSpeed: 83.33,
        );

      case TrackingPreset.high:
        return NativeConfig(
          accuracy: Accuracy.high,
          intervalMs: 15000,
          distanceFilter: 10.0,
          mode: TrackingMode.active,
          enableMotionDetection: true,
          stopOnTerminate: config.stopOnTerminate,
          startOnBoot: config.startOnBoot,
          enableHeadless: config.enableHeadless,
          stopTimeout: 3,
          stopDetectionDelay: 1,
          stationaryRadius: 25.0,
          disableStopDetection: false,
          disableMotionActivityUpdates: false,
          motionTriggerDelay: 0,
          useSignificantChangesOnly: false,
          isMoving: false,
          activityRecognitionInterval: 10000,
          minimumActivityRecognitionConfidence: 70,
          heartbeatInterval: 300,
          activityType: ActivityType.other,
          pausesLocationUpdatesAutomatically: false,
          preventSuspend: false,
          maxDaysToPersist: 1,
          maxRecordsToPersist: 200,
          debug: config.debug,
          logLevel: config.debug ? LogLevel.debug : LogLevel.off,
          notification: config.notification,
          backgroundPermissionRationale: config.backgroundPermissionRationale,
          locationAuthorizationRequest: LocationAuthorizationRequest.always,
          locationFilterEnabled: true,
          maxAccuracy: 50.0,
          maxSpeed: 83.33,
        );
    }
  }

  /// Returns config adjustments for activity-based adaptation within a preset.
  static ActivityOverrides activityOverrides(TrackingPreset preset, String activity) {
    switch (preset) {
      case TrackingPreset.low:
        switch (activity) {
          case 'in_vehicle':
            return const ActivityOverrides(distanceFilter: 300, accuracy: Accuracy.balanced, heartbeatInterval: 1200);
          case 'on_bicycle':
          case 'running':
          case 'walking':
          case 'on_foot':
            return const ActivityOverrides(distanceFilter: 400, accuracy: Accuracy.low, heartbeatInterval: 1500);
          case 'still':
          default:
            return const ActivityOverrides(distanceFilter: 500, accuracy: Accuracy.low, heartbeatInterval: 1800);
        }

      case TrackingPreset.balanced:
        switch (activity) {
          case 'in_vehicle':
            return const ActivityOverrides(distanceFilter: 100, accuracy: Accuracy.balanced, heartbeatInterval: 600);
          case 'on_bicycle':
            return const ActivityOverrides(distanceFilter: 30, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'running':
            return const ActivityOverrides(distanceFilter: 20, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'walking':
          case 'on_foot':
            return const ActivityOverrides(distanceFilter: 30, accuracy: Accuracy.high, heartbeatInterval: 900);
          case 'still':
          default:
            return const ActivityOverrides(distanceFilter: 200, accuracy: Accuracy.balanced, heartbeatInterval: 1200);
        }

      case TrackingPreset.high:
        switch (activity) {
          case 'in_vehicle':
            return const ActivityOverrides(distanceFilter: 20, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'on_bicycle':
            return const ActivityOverrides(distanceFilter: 10, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'running':
            return const ActivityOverrides(distanceFilter: 5, accuracy: Accuracy.high, heartbeatInterval: 180);
          case 'walking':
          case 'on_foot':
            return const ActivityOverrides(distanceFilter: 5, accuracy: Accuracy.high, heartbeatInterval: 300);
          case 'still':
          default:
            return const ActivityOverrides(distanceFilter: 50, accuracy: Accuracy.high, heartbeatInterval: 300);
        }
    }
  }

  /// Returns config adjustments for foreground mode (tighter tracking).
  static LifecycleOverrides foregroundOverrides(TrackingPreset preset) {
    switch (preset) {
      case TrackingPreset.low:
        return const LifecycleOverrides(distanceFilter: 200, accuracy: Accuracy.balanced, heartbeatInterval: 900, intervalMs: 120000);
      case TrackingPreset.balanced:
        return const LifecycleOverrides(distanceFilter: 10, accuracy: Accuracy.high, heartbeatInterval: 300, intervalMs: 15000);
      case TrackingPreset.high:
        return const LifecycleOverrides(distanceFilter: 5, accuracy: Accuracy.navigation, heartbeatInterval: 120, intervalMs: 5000);
    }
  }

  /// Returns config adjustments for background mode (relaxed for battery).
  static LifecycleOverrides backgroundOverrides(TrackingPreset preset) {
    switch (preset) {
      case TrackingPreset.low:
        return const LifecycleOverrides(distanceFilter: 500, accuracy: Accuracy.low, heartbeatInterval: 1800, intervalMs: 300000);
      case TrackingPreset.balanced:
        return const LifecycleOverrides(distanceFilter: 50, accuracy: Accuracy.high, heartbeatInterval: 1200, intervalMs: 60000);
      case TrackingPreset.high:
        return const LifecycleOverrides(distanceFilter: 10, accuracy: Accuracy.high, heartbeatInterval: 300, intervalMs: 15000);
    }
  }
}

class ActivityOverrides {
  final double distanceFilter;
  final Accuracy accuracy;
  final int heartbeatInterval;

  const ActivityOverrides({
    required this.distanceFilter,
    required this.accuracy,
    required this.heartbeatInterval,
  });
}

class LifecycleOverrides {
  final double distanceFilter;
  final Accuracy accuracy;
  final int heartbeatInterval;
  final int intervalMs;

  const LifecycleOverrides({
    required this.distanceFilter,
    required this.accuracy,
    required this.heartbeatInterval,
    required this.intervalMs,
  });
}
