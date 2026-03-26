/// A Flutter plugin for background location tracking without Google Play Services.
library libre_location;

export 'src/libre_location_platform.dart';
export 'src/libre_location_method_channel.dart';
export 'src/models/position.dart';
export 'src/models/location_config.dart';
export 'src/models/geofence.dart';
export 'src/models/geofence_event.dart';
export 'src/models/activity_event.dart';
export 'src/models/battery_info.dart';
export 'src/models/provider_event.dart';
export 'src/models/heartbeat_event.dart';
export 'src/models/notification_config.dart';
export 'src/models/permission_rationale.dart';
export 'src/enums/accuracy.dart';
export 'src/enums/tracking_mode.dart';
export 'src/enums/geofence_transition.dart';
export 'src/enums/activity_type.dart';
export 'src/enums/log_level.dart';
export 'src/enums/location_authorization.dart';
export 'src/enums/notification_priority.dart';
export 'src/logger.dart';

import 'src/libre_location_platform.dart';
import 'src/models/position.dart';
import 'src/models/location_config.dart';
import 'src/models/geofence.dart';
import 'src/models/geofence_event.dart';
import 'src/models/activity_event.dart';
import 'src/models/provider_event.dart';
import 'src/models/heartbeat_event.dart';
import 'src/enums/accuracy.dart';
import 'src/logger.dart';

/// The main entry point for the libre_location plugin.
class LibreLocation {
  static Future<void> startTracking(LocationConfig config) {
    return LibreLocationPlatform.instance.startTracking(config);
  }

  static Future<void> stopTracking() {
    return LibreLocationPlatform.instance.stopTracking();
  }

  static Future<Position> getCurrentPosition({
    Accuracy accuracy = Accuracy.high,
    int samples = 3,
    int timeout = 30,
    int maximumAge = 0,
    bool persist = true,
  }) {
    return LibreLocationPlatform.instance.getCurrentPosition(
      accuracy: accuracy,
      samples: samples,
      timeout: timeout,
      maximumAge: maximumAge,
      persist: persist,
    );
  }

  static Future<void> setConfig(LocationConfig config) {
    return LibreLocationPlatform.instance.setConfig(config);
  }

  static Stream<Position> get positionStream {
    return LibreLocationPlatform.instance.positionStream;
  }

  static Stream<Position> get motionChangeStream {
    return LibreLocationPlatform.instance.motionChangeStream;
  }

  static Stream<ActivityEvent> get activityChangeStream {
    return LibreLocationPlatform.instance.activityChangeStream;
  }

  static Stream<ProviderEvent> get providerChangeStream {
    return LibreLocationPlatform.instance.providerChangeStream;
  }

  static Stream<HeartbeatEvent> get heartbeatStream {
    return LibreLocationPlatform.instance.heartbeatStream;
  }

  static Future<bool> get isTracking {
    return LibreLocationPlatform.instance.isTracking;
  }

  static Future<void> addGeofence(Geofence geofence) {
    return LibreLocationPlatform.instance.addGeofence(geofence);
  }

  static Future<void> removeGeofence(String id) {
    return LibreLocationPlatform.instance.removeGeofence(id);
  }

  static Future<List<Geofence>> getGeofences() {
    return LibreLocationPlatform.instance.getGeofences();
  }

  static Stream<GeofenceEvent> get geofenceStream {
    return LibreLocationPlatform.instance.geofenceStream;
  }

  static Future<LocationPermission> checkPermission() {
    return LibreLocationPlatform.instance.checkPermission();
  }

  static Future<LocationPermission> requestPermission() {
    return LibreLocationPlatform.instance.requestPermission();
  }

  /// Registers a headless callback dispatcher for receiving location updates
  /// after app termination (Android only).
  ///
  /// Both callbacks must be top-level or static functions.
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// void headlessDispatcher() {
  ///   // Initialize the headless isolate
  /// }
  ///
  /// @pragma('vm:entry-point')
  /// void onHeadlessLocation(Map<String, dynamic> data) {
  ///   print('Headless location: $data');
  /// }
  ///
  /// LibreLocation.registerHeadlessDispatcher(headlessDispatcher, onHeadlessLocation);
  /// ```
  static Future<void> registerHeadlessDispatcher(
    void Function() dispatcherCallback,
    void Function(Map<String, dynamic>) userCallback,
  ) {
    return LibreLocationPlatform.instance.registerHeadlessDispatcher(
      dispatcherCallback,
      userCallback,
    );
  }

  /// Returns `true` if the app is battery-optimized (Android only).
  /// When optimized, the OS may aggressively kill background processes.
  static Future<bool> checkBatteryOptimization() {
    return LibreLocationPlatform.instance.checkBatteryOptimization();
  }

  /// Requests the system to exempt this app from battery optimization (Android only).
  /// Returns `true` if the settings dialog was opened.
  static Future<bool> requestBatteryOptimizationExemption() {
    return LibreLocationPlatform.instance.requestBatteryOptimizationExemption();
  }

  /// Checks manufacturer-specific auto-start settings (Android only).
  /// Returns a map with `manufacturer`, `hasAutoStartSetting`, and `isBatteryOptimized`.
  static Future<Map<String, dynamic>> isAutoStartEnabled() {
    return LibreLocationPlatform.instance.isAutoStartEnabled();
  }

  /// Opens the manufacturer-specific power/battery settings page (Android only).
  /// Returns `true` if a settings page was opened.
  static Future<bool> openPowerManagerSettings() {
    return LibreLocationPlatform.instance.openPowerManagerSettings();
  }

  /// Stream that emits `true` when power save / low power mode is enabled,
  /// `false` when disabled.
  static Stream<bool> get powerSaveChangeStream {
    return LibreLocationPlatform.instance.powerSaveChangeStream;
  }

  /// Requests temporary full accuracy authorization on iOS 14+.
  ///
  /// [purposeKey] must match a key defined in
  /// `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.
  ///
  /// Returns 0 for fullAccuracy, 1 for reducedAccuracy.
  static Future<int> requestTemporaryFullAccuracy({required String purposeKey}) {
    return LibreLocationPlatform.instance.requestTemporaryFullAccuracy(purposeKey: purposeKey);
  }

  /// Manually overrides the motion state.
  ///
  /// Pass `true` to force moving mode (active GPS tracking).
  /// Pass `false` to force stationary mode (reduced power).
  static Future<void> changePace(bool isMoving) {
    return LibreLocationPlatform.instance.changePace(isMoving);
  }

  /// Returns recent log entries from the in-memory log buffer.
  ///
  /// Each entry contains `timestamp`, `level`, and `message`.
  /// Also fetches native-side logs when available.
  static Future<List<Map<String, dynamic>>> getLog() async {
    // Combine Dart-side logs with native-side logs
    final dartLogs = LibreLocationLogger.getLog();
    try {
      final nativeLogs = await LibreLocationPlatform.instance.getLog();
      return [...dartLogs, ...nativeLogs];
    } catch (_) {
      return dartLogs;
    }
  }

  /// Checks whether the POST_NOTIFICATIONS permission is granted (Android 13+).
  /// Returns `true` on iOS and pre-Android 13 devices.
  static Future<bool> checkNotificationPermission() {
    return LibreLocationPlatform.instance.checkNotificationPermission();
  }

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  /// Returns `true` if granted. No-op on iOS and pre-Android 13.
  static Future<bool> requestNotificationPermission() {
    return LibreLocationPlatform.instance.requestNotificationPermission();
  }
}

/// Represents the current state of location permissions.
enum LocationPermission {
  denied,
  deniedForever,
  whileInUse,
  always,
}
