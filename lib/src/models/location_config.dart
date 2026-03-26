import '../enums/accuracy.dart';
import '../enums/tracking_mode.dart';
import '../enums/activity_type.dart';
import '../enums/log_level.dart';
import '../enums/location_authorization.dart';
import 'notification_config.dart';
import 'permission_rationale.dart';

/// Configuration for background location tracking.
class LocationConfig {
  final Accuracy accuracy;
  final int intervalMs;
  final double distanceFilter;
  final TrackingMode mode;
  final bool enableMotionDetection;
  final bool stopOnTerminate;
  final bool startOnBoot;
  final bool enableHeadless;
  final int stopTimeout;
  final int stopDetectionDelay;
  final double stationaryRadius;
  final bool disableStopDetection;
  final bool disableMotionActivityUpdates;
  final int motionTriggerDelay;
  final bool useSignificantChangesOnly;
  final bool isMoving;
  final int activityRecognitionInterval;
  final int minimumActivityRecognitionConfidence;
  final int heartbeatInterval;
  final ActivityType activityType;
  final bool pausesLocationUpdatesAutomatically;
  final bool preventSuspend;
  final int maxDaysToPersist;
  final int maxRecordsToPersist;
  final bool debug;
  final LogLevel logLevel;
  final NotificationConfig? notification;
  final PermissionRationale? backgroundPermissionRationale;
  final LocationAuthorizationRequest locationAuthorizationRequest;

  // GPS filtering / smoothing
  final bool locationFilterEnabled;
  final double maxAccuracy;
  final double maxSpeed;

  const LocationConfig({
    this.accuracy = Accuracy.high,
    this.intervalMs = 60000,
    this.distanceFilter = 10.0,
    this.mode = TrackingMode.balanced,
    this.enableMotionDetection = true,
    this.stopOnTerminate = true,
    this.startOnBoot = false,
    this.enableHeadless = false,
    this.stopTimeout = 5,
    this.stopDetectionDelay = 0,
    this.stationaryRadius = 25.0,
    this.disableStopDetection = false,
    this.disableMotionActivityUpdates = false,
    this.motionTriggerDelay = 0,
    this.useSignificantChangesOnly = false,
    this.isMoving = false,
    this.activityRecognitionInterval = 10000,
    this.minimumActivityRecognitionConfidence = 75,
    this.heartbeatInterval = 0,
    this.activityType = ActivityType.other,
    this.pausesLocationUpdatesAutomatically = false,
    this.preventSuspend = false,
    this.maxDaysToPersist = 1,
    this.maxRecordsToPersist = -1,
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
      'stopTimeout': stopTimeout,
      'stopDetectionDelay': stopDetectionDelay,
      'stationaryRadius': stationaryRadius,
      'disableStopDetection': disableStopDetection,
      'disableMotionActivityUpdates': disableMotionActivityUpdates,
      'motionTriggerDelay': motionTriggerDelay,
      'useSignificantChangesOnly': useSignificantChangesOnly,
      'isMoving': isMoving,
      'activityRecognitionInterval': activityRecognitionInterval,
      'minimumActivityRecognitionConfidence': minimumActivityRecognitionConfidence,
      'heartbeatInterval': heartbeatInterval,
      'activityType': activityType.index,
      'pausesLocationUpdatesAutomatically': pausesLocationUpdatesAutomatically,
      'preventSuspend': preventSuspend,
      'maxDaysToPersist': maxDaysToPersist,
      'maxRecordsToPersist': maxRecordsToPersist,
      'debug': debug,
      'logLevel': logLevel.index,
      if (notification != null) ...{
        'notification': notification!.toMap(),
        // Flatten for Android native compatibility
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

  factory LocationConfig.fromMap(Map<String, dynamic> map) {
    return LocationConfig(
      accuracy: Accuracy.values[map['accuracy'] as int? ?? 0],
      intervalMs: map['intervalMs'] as int? ?? 60000,
      distanceFilter: (map['distanceFilter'] as num?)?.toDouble() ?? 10.0,
      mode: TrackingMode.values[map['mode'] as int? ?? 1],
      enableMotionDetection: map['enableMotionDetection'] as bool? ?? true,
      stopOnTerminate: map['stopOnTerminate'] as bool? ?? true,
      startOnBoot: map['startOnBoot'] as bool? ?? false,
      enableHeadless: map['enableHeadless'] as bool? ?? false,
      stopTimeout: map['stopTimeout'] as int? ?? 5,
      stopDetectionDelay: map['stopDetectionDelay'] as int? ?? 0,
      stationaryRadius: (map['stationaryRadius'] as num?)?.toDouble() ?? 25.0,
      disableStopDetection: map['disableStopDetection'] as bool? ?? false,
      disableMotionActivityUpdates: map['disableMotionActivityUpdates'] as bool? ?? false,
      motionTriggerDelay: map['motionTriggerDelay'] as int? ?? 0,
      useSignificantChangesOnly: map['useSignificantChangesOnly'] as bool? ?? false,
      isMoving: map['isMoving'] as bool? ?? false,
      activityRecognitionInterval: map['activityRecognitionInterval'] as int? ?? 10000,
      minimumActivityRecognitionConfidence: map['minimumActivityRecognitionConfidence'] as int? ?? 75,
      heartbeatInterval: map['heartbeatInterval'] as int? ?? 0,
      activityType: ActivityType.values[map['activityType'] as int? ?? 0],
      pausesLocationUpdatesAutomatically: map['pausesLocationUpdatesAutomatically'] as bool? ?? false,
      preventSuspend: map['preventSuspend'] as bool? ?? false,
      maxDaysToPersist: map['maxDaysToPersist'] as int? ?? 1,
      maxRecordsToPersist: map['maxRecordsToPersist'] as int? ?? -1,
      debug: map['debug'] as bool? ?? false,
      logLevel: LogLevel.values[map['logLevel'] as int? ?? 0],
      notification: map['notification'] != null
          ? NotificationConfig.fromMap(Map<String, dynamic>.from(map['notification'] as Map))
          : null,
      backgroundPermissionRationale: map['backgroundPermissionRationale'] != null
          ? PermissionRationale.fromMap(Map<String, dynamic>.from(map['backgroundPermissionRationale'] as Map))
          : null,
      locationAuthorizationRequest: LocationAuthorizationRequest.values[map['locationAuthorizationRequest'] as int? ?? 0],
      locationFilterEnabled: map['locationFilterEnabled'] as bool? ?? true,
      maxAccuracy: (map['maxAccuracy'] as num?)?.toDouble() ?? 100.0,
      maxSpeed: (map['maxSpeed'] as num?)?.toDouble() ?? 83.33,
    );
  }

  LocationConfig copyWith({
    Accuracy? accuracy,
    int? intervalMs,
    double? distanceFilter,
    TrackingMode? mode,
    bool? enableMotionDetection,
    bool? stopOnTerminate,
    bool? startOnBoot,
    bool? enableHeadless,
    int? stopTimeout,
    int? stopDetectionDelay,
    double? stationaryRadius,
    bool? disableStopDetection,
    bool? disableMotionActivityUpdates,
    int? motionTriggerDelay,
    bool? useSignificantChangesOnly,
    bool? isMoving,
    int? activityRecognitionInterval,
    int? minimumActivityRecognitionConfidence,
    int? heartbeatInterval,
    ActivityType? activityType,
    bool? pausesLocationUpdatesAutomatically,
    bool? preventSuspend,
    int? maxDaysToPersist,
    int? maxRecordsToPersist,
    bool? debug,
    LogLevel? logLevel,
    NotificationConfig? notification,
    PermissionRationale? backgroundPermissionRationale,
    LocationAuthorizationRequest? locationAuthorizationRequest,
    bool? locationFilterEnabled,
    double? maxAccuracy,
    double? maxSpeed,
  }) {
    return LocationConfig(
      accuracy: accuracy ?? this.accuracy,
      intervalMs: intervalMs ?? this.intervalMs,
      distanceFilter: distanceFilter ?? this.distanceFilter,
      mode: mode ?? this.mode,
      enableMotionDetection: enableMotionDetection ?? this.enableMotionDetection,
      stopOnTerminate: stopOnTerminate ?? this.stopOnTerminate,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      enableHeadless: enableHeadless ?? this.enableHeadless,
      stopTimeout: stopTimeout ?? this.stopTimeout,
      stopDetectionDelay: stopDetectionDelay ?? this.stopDetectionDelay,
      stationaryRadius: stationaryRadius ?? this.stationaryRadius,
      disableStopDetection: disableStopDetection ?? this.disableStopDetection,
      disableMotionActivityUpdates: disableMotionActivityUpdates ?? this.disableMotionActivityUpdates,
      motionTriggerDelay: motionTriggerDelay ?? this.motionTriggerDelay,
      useSignificantChangesOnly: useSignificantChangesOnly ?? this.useSignificantChangesOnly,
      isMoving: isMoving ?? this.isMoving,
      activityRecognitionInterval: activityRecognitionInterval ?? this.activityRecognitionInterval,
      minimumActivityRecognitionConfidence: minimumActivityRecognitionConfidence ?? this.minimumActivityRecognitionConfidence,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      activityType: activityType ?? this.activityType,
      pausesLocationUpdatesAutomatically: pausesLocationUpdatesAutomatically ?? this.pausesLocationUpdatesAutomatically,
      preventSuspend: preventSuspend ?? this.preventSuspend,
      maxDaysToPersist: maxDaysToPersist ?? this.maxDaysToPersist,
      maxRecordsToPersist: maxRecordsToPersist ?? this.maxRecordsToPersist,
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
      'LocationConfig(accuracy: ${accuracy.name}, distanceFilter: $distanceFilter, mode: ${mode.name})';
}
