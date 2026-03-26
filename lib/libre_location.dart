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

import 'src/libre_location_platform.dart';
import 'src/models/position.dart';
import 'src/models/location_config.dart';
import 'src/models/geofence.dart';
import 'src/models/geofence_event.dart';
import 'src/models/activity_event.dart';
import 'src/models/provider_event.dart';
import 'src/models/heartbeat_event.dart';
import 'src/enums/accuracy.dart';

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
}

/// Represents the current state of location permissions.
enum LocationPermission {
  denied,
  deniedForever,
  whileInUse,
  always,
}
