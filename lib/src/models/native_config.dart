import '../enums/accuracy.dart';
import '../enums/tracking_mode.dart';
import '../enums/activity_type.dart';
import '../enums/log_level.dart';
import '../enums/location_authorization.dart';
import 'notification_config.dart';
import 'permission_rationale.dart';

/// Internal configuration sent to the native layer via method channels.
///
/// This class contains ALL tuning parameters that the native Android/iOS code
/// expects. Developers never interact with this directly — it's built
/// internally by [PresetConfig] from a [TrackingPreset] + [LocationConfig].
class NativeConfig {
  final Accuracy accuracy;
  final int intervalMs;
  final double distanceFilter;
  final TrackingMode mode;
  final bool enableMotionDetection;
  final bool stopOnTerminate;
  final bool startOnBoot;
  final bool enableHeadless;
  final int stillnessTimeoutMin;
  final int stillnessDelayMs;
  final double stillnessRadiusMeters;
  final bool skipStillnessDetection;
  final bool skipActivityUpdates;
  final int motionConfirmDelayMs;
  final bool significantChangesOnly;
  final bool initiallyMoving;
  final int activityCheckIntervalMs;
  final int activityConfidenceThreshold;
  final int heartbeatInterval;
  final ActivityType activityType;
  final bool pausesLocationUpdatesAutomatically;
  final bool keepAwake;
  final int retentionDays;
  final int retentionMaxRecords;
  final bool debug;
  final LogLevel logLevel;
  final NotificationConfig? notification;
  final PermissionRationale? backgroundPermissionRationale;
  final LocationAuthorizationRequest locationAuthorizationRequest;
  final bool locationFilterEnabled;
  final double maxAccuracy;
  final double maxSpeed;

  const NativeConfig({
    this.accuracy = Accuracy.high,
    this.intervalMs = 60000,
    this.distanceFilter = 10.0,
    this.mode = TrackingMode.balanced,
    this.enableMotionDetection = true,
    this.stopOnTerminate = true,
    this.startOnBoot = false,
    this.enableHeadless = false,
    this.stillnessTimeoutMin = 5,
    this.stillnessDelayMs = 0,
    this.stillnessRadiusMeters = 25.0,
    this.skipStillnessDetection = false,
    this.skipActivityUpdates = false,
    this.motionConfirmDelayMs = 0,
    this.significantChangesOnly = false,
    this.initiallyMoving = false,
    this.activityCheckIntervalMs = 10000,
    this.activityConfidenceThreshold = 75,
    this.heartbeatInterval = 0,
    this.activityType = ActivityType.other,
    this.pausesLocationUpdatesAutomatically = false,
    this.keepAwake = false,
    this.retentionDays = 1,
    this.retentionMaxRecords = -1,
    this.debug = false,
    this.logLevel = LogLevel.off,
    this.notification,
    this.backgroundPermissionRationale,
    this.locationAuthorizationRequest = LocationAuthorizationRequest.always,
    this.locationFilterEnabled = true,
    this.maxAccuracy = 100.0,
    this.maxSpeed = 83.33,
  });

  Map<String, dynamic> toMap() {
    return {
      'accuracy': accuracy.index,
      'intervalMs': intervalMs,
      'distanceFilter': distanceFilter,
      'mode': mode.index,
      'enableMotionDetection': enableMotionDetection,
      'stopOnTerminate': stopOnTerminate,
      'startOnBoot': startOnBoot,
      'enableHeadless': enableHeadless,
      'stillnessTimeoutMin': stillnessTimeoutMin,
      'stillnessDelayMs': stillnessDelayMs,
      'stillnessRadiusMeters': stillnessRadiusMeters,
      'skipStillnessDetection': skipStillnessDetection,
      'skipActivityUpdates': skipActivityUpdates,
      'motionConfirmDelayMs': motionConfirmDelayMs,
      'significantChangesOnly': significantChangesOnly,
      'initiallyMoving': initiallyMoving,
      'activityCheckIntervalMs': activityCheckIntervalMs,
      'activityConfidenceThreshold': activityConfidenceThreshold,
      'heartbeatInterval': heartbeatInterval,
      'activityType': activityType.index,
      'pausesLocationUpdatesAutomatically': pausesLocationUpdatesAutomatically,
      'keepAwake': keepAwake,
      'retentionDays': retentionDays,
      'retentionMaxRecords': retentionMaxRecords,
      'debug': debug,
      'logLevel': logLevel.index,
      if (notification != null) ...{
        'notification': notification!.toMap(),
        'notificationTitle': notification!.title,
        'notificationBody': notification!.text,
        'notificationSticky': notification!.sticky,
        'notificationPriority': notification!.priority.index,
      },
      if (backgroundPermissionRationale != null)
        'backgroundPermissionRationale': backgroundPermissionRationale!.toMap(),
      'locationAuthorizationRequest': locationAuthorizationRequest.index,
      'locationFilterEnabled': locationFilterEnabled,
      'maxAccuracy': maxAccuracy,
      'maxSpeed': maxSpeed,
    };
  }

  NativeConfig copyWith({
    Accuracy? accuracy,
    int? intervalMs,
    double? distanceFilter,
    TrackingMode? mode,
    bool? enableMotionDetection,
    bool? stopOnTerminate,
    bool? startOnBoot,
    bool? enableHeadless,
    int? stillnessTimeoutMin,
    int? stillnessDelayMs,
    double? stillnessRadiusMeters,
    bool? skipStillnessDetection,
    bool? skipActivityUpdates,
    int? motionConfirmDelayMs,
    bool? significantChangesOnly,
    bool? initiallyMoving,
    int? activityCheckIntervalMs,
    int? activityConfidenceThreshold,
    int? heartbeatInterval,
    ActivityType? activityType,
    bool? pausesLocationUpdatesAutomatically,
    bool? keepAwake,
    int? retentionDays,
    int? retentionMaxRecords,
    bool? debug,
    LogLevel? logLevel,
    NotificationConfig? notification,
    PermissionRationale? backgroundPermissionRationale,
    LocationAuthorizationRequest? locationAuthorizationRequest,
    bool? locationFilterEnabled,
    double? maxAccuracy,
    double? maxSpeed,
  }) {
    return NativeConfig(
      accuracy: accuracy ?? this.accuracy,
      intervalMs: intervalMs ?? this.intervalMs,
      distanceFilter: distanceFilter ?? this.distanceFilter,
      mode: mode ?? this.mode,
      enableMotionDetection: enableMotionDetection ?? this.enableMotionDetection,
      stopOnTerminate: stopOnTerminate ?? this.stopOnTerminate,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      enableHeadless: enableHeadless ?? this.enableHeadless,
      stillnessTimeoutMin: stillnessTimeoutMin ?? this.stillnessTimeoutMin,
      stillnessDelayMs: stillnessDelayMs ?? this.stillnessDelayMs,
      stillnessRadiusMeters: stillnessRadiusMeters ?? this.stillnessRadiusMeters,
      skipStillnessDetection: skipStillnessDetection ?? this.skipStillnessDetection,
      skipActivityUpdates: skipActivityUpdates ?? this.skipActivityUpdates,
      motionConfirmDelayMs: motionConfirmDelayMs ?? this.motionConfirmDelayMs,
      significantChangesOnly: significantChangesOnly ?? this.significantChangesOnly,
      initiallyMoving: initiallyMoving ?? this.initiallyMoving,
      activityCheckIntervalMs: activityCheckIntervalMs ?? this.activityCheckIntervalMs,
      activityConfidenceThreshold: activityConfidenceThreshold ?? this.activityConfidenceThreshold,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      activityType: activityType ?? this.activityType,
      pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically ?? this.pausesLocationUpdatesAutomatically,
      keepAwake: keepAwake ?? this.keepAwake,
      retentionDays: retentionDays ?? this.retentionDays,
      retentionMaxRecords: retentionMaxRecords ?? this.retentionMaxRecords,
      debug: debug ?? this.debug,
      logLevel: logLevel ?? this.logLevel,
      notification: notification ?? this.notification,
      backgroundPermissionRationale: backgroundPermissionRationale ?? this.backgroundPermissionRationale,
      locationAuthorizationRequest: locationAuthorizationRequest ?? this.locationAuthorizationRequest,
      locationFilterEnabled: locationFilterEnabled ?? this.locationFilterEnabled,
      maxAccuracy: maxAccuracy ?? this.maxAccuracy,
      maxSpeed: maxSpeed ?? this.maxSpeed,
    );
  }

  @override
  String toString() =>
      'NativeConfig(accuracy: ${accuracy.name}, distanceFilter: $distanceFilter, mode: ${mode.name})';
}
