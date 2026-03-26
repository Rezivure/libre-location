/// A Flutter plugin for background location tracking without Google Play Services.
library libre_location;

export 'src/libre_location_platform.dart';
export 'src/libre_location_method_channel.dart';
export 'src/models/position.dart';
export 'src/models/location_config.dart';
export 'src/models/native_config.dart';
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
export 'src/tracking_preset.dart';
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
import 'src/tracking_preset.dart';
import 'src/auto_adapter.dart';
import 'src/logger.dart';

/// The main entry point for the libre_location plugin.
///
/// ## Quick Start
///
/// ```dart
/// // Start tracking — that's it
/// await LibreLocation.start();
///
/// // Or pick a preset
/// await LibreLocation.start(preset: TrackingPreset.high);
///
/// // Listen for updates
/// LibreLocation.onLocation.listen((pos) => print(pos));
///
/// // Switch preset at runtime (no stop/start needed)
/// await LibreLocation.setPreset(TrackingPreset.low);
///
/// // Manual ping
/// final pos = await LibreLocation.getCurrentPosition(samples: 3);
/// ```
class LibreLocation {
  static AutoAdapter? _adapter;

  // ───────────────────────────────────────────
  // Preset API (recommended)
  // ───────────────────────────────────────────

  /// Start tracking with a preset.
  ///
  /// If [preset] is not provided, defaults to [TrackingPreset.balanced].
  ///
  /// Use [config] to set app-specific options like notification text,
  /// stop-on-terminate behavior, and debug mode. All GPS tuning is
  /// handled automatically by the preset.
  ///
  /// When using a preset, the plugin automatically:
  /// - Adjusts config when the app moves to foreground/background
  /// - Adapts to detected activity (driving/walking/cycling/still)
  /// - Optimizes GPS polling when stationary
  static Future<void> start({
    TrackingPreset? preset,
    LocationConfig config = const LocationConfig(),
  }) async {
    // Stop any existing adapter
    _adapter?.stop();
    _adapter = null;

    final effectivePreset = preset ?? TrackingPreset.balanced;
    final nativeConfig = PresetConfig.buildNativeConfig(effectivePreset, config);

    // Start native tracking
    await LibreLocationPlatform.instance.startTracking(nativeConfig);

    // Start auto-adaptation
    _adapter = AutoAdapter(effectivePreset, config, nativeConfig);
    _adapter!.start();
  }

  /// Switch to a different preset at runtime without stopping tracking.
  ///
  /// This is a no-op if tracking wasn't started with a preset.
  static Future<void> setPreset(TrackingPreset preset) async {
    if (_adapter == null) {
      LibreLocationLogger.warning(
        'setPreset() called but tracking was not started with a preset. '
        'Starting with preset now.',
      );
      await start(preset: preset);
      return;
    }
    await _adapter!.setPreset(preset);
  }

  /// Returns the current preset, or null if not tracking.
  static TrackingPreset? get currentPreset => _adapter?.preset;

  // ───────────────────────────────────────────
  // Core API
  // ───────────────────────────────────────────

  static Future<void> stop() {
    _adapter?.stop();
    _adapter = null;
    return LibreLocationPlatform.instance.stopTracking();
  }

  /// Alias for [stop] — backwards compatible.
  static Future<void> stopTracking() => stop();

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

  // ───────────────────────────────────────────
  // Streams
  // ───────────────────────────────────────────

  /// Stream of location updates. This is the primary stream for tracking.
  static Stream<Position> get onLocation =>
      LibreLocationPlatform.instance.positionStream;

  /// Stream of motion change events (moving ↔ stationary).
  static Stream<Position> get onMotionChange =>
      LibreLocationPlatform.instance.motionChangeStream;

  /// Stream of activity change events (still/walking/driving/etc).
  static Stream<ActivityEvent> get onActivityChange =>
      LibreLocationPlatform.instance.activityChangeStream;

  /// Stream of heartbeat events (periodic pings when stationary).
  static Stream<HeartbeatEvent> get onHeartbeat =>
      LibreLocationPlatform.instance.heartbeatStream;

  /// Stream of provider change events (GPS on/off, permissions).
  static Stream<ProviderEvent> get onProviderChange =>
      LibreLocationPlatform.instance.providerChangeStream;

  /// Stream of power save mode changes.
  static Stream<bool> get onPowerSaveChange =>
      LibreLocationPlatform.instance.powerSaveChangeStream;

  // Legacy stream names (backwards compatible)
  static Stream<Position> get positionStream => onLocation;
  static Stream<Position> get motionChangeStream => onMotionChange;
  static Stream<ActivityEvent> get activityChangeStream => onActivityChange;
  static Stream<ProviderEvent> get providerChangeStream => onProviderChange;
  static Stream<HeartbeatEvent> get heartbeatStream => onHeartbeat;
  static Stream<bool> get powerSaveChangeStream => onPowerSaveChange;

  // ───────────────────────────────────────────
  // State & Permissions
  // ───────────────────────────────────────────

  static Future<bool> get isTracking {
    return LibreLocationPlatform.instance.isTracking;
  }

  static Future<LocationPermission> checkPermission() {
    return LibreLocationPlatform.instance.checkPermission();
  }

  static Future<LocationPermission> requestPermission() {
    return LibreLocationPlatform.instance.requestPermission();
  }

  static Future<LocationPermission> requestAlwaysPermission() {
    return LibreLocationPlatform.instance.requestAlwaysPermission();
  }

  static Future<bool> openAppSettings() {
    return LibreLocationPlatform.instance.openAppSettings();
  }

  static Future<bool> openLocationSettings() {
    return LibreLocationPlatform.instance.openLocationSettings();
  }

  static Stream<LocationPermission> get onPermissionChange =>
      LibreLocationPlatform.instance.permissionChangeStream;

  static Future<bool> shouldShowRequestRationale() {
    return LibreLocationPlatform.instance.shouldShowRequestRationale();
  }

  static Future<bool> isLocationServiceEnabled() {
    return LibreLocationPlatform.instance.isLocationServiceEnabled();
  }

  // ───────────────────────────────────────────
  // Geofencing
  // ───────────────────────────────────────────

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

  // ───────────────────────────────────────────
  // Android-specific
  // ───────────────────────────────────────────

  static Future<void> registerHeadlessDispatcher(
    void Function() dispatcherCallback,
    void Function(Map<String, dynamic>) userCallback,
  ) {
    return LibreLocationPlatform.instance.registerHeadlessDispatcher(
      dispatcherCallback,
      userCallback,
    );
  }

  static Future<bool> checkBatteryOptimization() {
    return LibreLocationPlatform.instance.checkBatteryOptimization();
  }

  static Future<bool> requestBatteryOptimizationExemption() {
    return LibreLocationPlatform.instance.requestBatteryOptimizationExemption();
  }

  static Future<Map<String, dynamic>> isAutoStartEnabled() {
    return LibreLocationPlatform.instance.isAutoStartEnabled();
  }

  static Future<bool> openPowerManagerSettings() {
    return LibreLocationPlatform.instance.openPowerManagerSettings();
  }

  // ───────────────────────────────────────────
  // iOS-specific
  // ───────────────────────────────────────────

  static Future<int> requestTemporaryFullAccuracy({required String purposeKey}) {
    return LibreLocationPlatform.instance.requestTemporaryFullAccuracy(purposeKey: purposeKey);
  }

  // ───────────────────────────────────────────
  // Utilities
  // ───────────────────────────────────────────

  static Future<void> changePace(bool isMoving) {
    return LibreLocationPlatform.instance.setMoving(isMoving);
  }

  static Future<List<Map<String, dynamic>>> getLog() async {
    final dartLogs = LibreLocationLogger.getLog();
    try {
      final nativeLogs = await LibreLocationPlatform.instance.getLog();
      return [...dartLogs, ...nativeLogs];
    } catch (_) {
      return dartLogs;
    }
  }

  static Future<bool> checkNotificationPermission() {
    return LibreLocationPlatform.instance.checkNotificationPermission();
  }

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
