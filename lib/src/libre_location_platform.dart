import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../libre_location.dart';

/// The platform interface for the libre_location plugin.
abstract class LibreLocationPlatform extends PlatformInterface {
  LibreLocationPlatform() : super(token: _token);

  static final Object _token = Object();

  static LibreLocationPlatform _instance = MethodChannelLibreLocation();

  static LibreLocationPlatform get instance => _instance;

  static set instance(LibreLocationPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> startTracking(LocationConfig config) {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  Future<Position> getCurrentPosition({
    Accuracy accuracy = Accuracy.high,
    int samples = 3,
    int timeout = 30,
    int maximumAge = 0,
    bool persist = true,
  }) {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  Future<void> setConfig(LocationConfig config) {
    throw UnimplementedError('setConfig() has not been implemented.');
  }

  Stream<Position> get positionStream {
    throw UnimplementedError('positionStream has not been implemented.');
  }

  Stream<Position> get motionChangeStream {
    throw UnimplementedError('motionChangeStream has not been implemented.');
  }

  Stream<ActivityEvent> get activityChangeStream {
    throw UnimplementedError('activityChangeStream has not been implemented.');
  }

  Stream<ProviderEvent> get providerChangeStream {
    throw UnimplementedError('providerChangeStream has not been implemented.');
  }

  Stream<HeartbeatEvent> get heartbeatStream {
    throw UnimplementedError('heartbeatStream has not been implemented.');
  }

  Future<bool> get isTracking {
    throw UnimplementedError('isTracking has not been implemented.');
  }

  Future<void> addGeofence(Geofence geofence) {
    throw UnimplementedError('addGeofence() has not been implemented.');
  }

  Future<void> removeGeofence(String id) {
    throw UnimplementedError('removeGeofence() has not been implemented.');
  }

  Future<List<Geofence>> getGeofences() {
    throw UnimplementedError('getGeofences() has not been implemented.');
  }

  Stream<GeofenceEvent> get geofenceStream {
    throw UnimplementedError('geofenceStream has not been implemented.');
  }

  Future<LocationPermission> checkPermission() {
    throw UnimplementedError('checkPermission() has not been implemented.');
  }

  Future<LocationPermission> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Requests "Always" (background) location permission, upgrading from "When In Use".
  /// On iOS: calls requestAlwaysAuthorization after WhenInUse is granted.
  /// On Android 10+: requests ACCESS_BACKGROUND_LOCATION separately.
  Future<LocationPermission> requestAlwaysPermission() {
    throw UnimplementedError('requestAlwaysPermission() has not been implemented.');
  }

  /// Opens the app's system settings page where the user can change permissions.
  Future<bool> openAppSettings() {
    throw UnimplementedError('openAppSettings() has not been implemented.');
  }

  /// Opens the device location settings (e.g., to enable GPS).
  Future<bool> openLocationSettings() {
    throw UnimplementedError('openLocationSettings() has not been implemented.');
  }

  /// Stream that fires when location permission status changes.
  Stream<LocationPermission> get permissionChangeStream {
    throw UnimplementedError('permissionChangeStream has not been implemented.');
  }

  /// Android-only: returns true if the app should show a rationale before
  /// requesting location permission (user previously denied but didn't
  /// check "don't ask again").
  Future<bool> shouldShowRequestRationale() {
    throw UnimplementedError('shouldShowRequestRationale() has not been implemented.');
  }

  /// Checks if device-level location services (GPS) are enabled.
  Future<bool> isLocationServiceEnabled() {
    throw UnimplementedError('isLocationServiceEnabled() has not been implemented.');
  }

  /// Registers a headless callback dispatcher for receiving location updates
  /// after app termination (Android only).
  Future<void> registerHeadlessDispatcher(
    void Function() dispatcherCallback,
    void Function(Map<String, dynamic>) userCallback,
  ) {
    throw UnimplementedError('registerHeadlessDispatcher() has not been implemented.');
  }

  /// Returns whether the app is battery-optimized (Android only).
  /// `true` means the OS may kill it aggressively.
  Future<bool> checkBatteryOptimization() {
    throw UnimplementedError('checkBatteryOptimization() has not been implemented.');
  }

  /// Requests battery optimization exemption from the system (Android only).
  Future<bool> requestBatteryOptimizationExemption() {
    throw UnimplementedError('requestBatteryOptimizationExemption() has not been implemented.');
  }

  /// Checks manufacturer-specific auto-start settings availability (Android only).
  Future<Map<String, dynamic>> isAutoStartEnabled() {
    throw UnimplementedError('isAutoStartEnabled() has not been implemented.');
  }

  /// Opens the manufacturer-specific power/battery settings page (Android only).
  Future<bool> openPowerManagerSettings() {
    throw UnimplementedError('openPowerManagerSettings() has not been implemented.');
  }

  /// Stream that emits `true` when power save mode is enabled, `false` when disabled.
  Stream<bool> get powerSaveChangeStream {
    throw UnimplementedError('powerSaveChangeStream has not been implemented.');
  }

  /// Requests temporary full accuracy on iOS 14+ when the user has granted
  /// "approximate location" permission. [purposeKey] must match a key in
  /// `NSLocationTemporaryUsageDescriptionDictionary` in Info.plist.
  ///
  /// Returns the resulting accuracy authorization:
  /// 0 = fullAccuracy, 1 = reducedAccuracy.
  Future<int> requestTemporaryFullAccuracy({required String purposeKey}) {
    throw UnimplementedError('requestTemporaryFullAccuracy() has not been implemented.');
  }

  /// Manually overrides the motion state.
  /// When [isMoving] is `true`, tracking switches to active/moving mode.
  /// When `false`, tracking switches to stationary mode.
  Future<void> changePace(bool isMoving) {
    throw UnimplementedError('changePace() has not been implemented.');
  }

  /// Returns recent log entries from the in-memory log buffer.
  Future<List<Map<String, dynamic>>> getLog() {
    throw UnimplementedError('getLog() has not been implemented.');
  }

  /// Checks whether the POST_NOTIFICATIONS permission is granted (Android 13+).
  Future<bool> checkNotificationPermission() {
    throw UnimplementedError('checkNotificationPermission() has not been implemented.');
  }

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  /// Returns `true` if granted.
  Future<bool> requestNotificationPermission() {
    throw UnimplementedError('requestNotificationPermission() has not been implemented.');
  }
}
