/// A Flutter plugin for background location tracking without Google Play Services.
///
/// Uses pure AOSP LocationManager on Android and CoreLocation on iOS.
/// Designed for privacy-focused apps, GrapheneOS, CalyxOS, and degoogled devices.
library libre_location;

export 'src/libre_location_platform.dart';
export 'src/libre_location_method_channel.dart';
export 'src/models/position.dart';
export 'src/models/location_config.dart';
export 'src/models/geofence.dart';
export 'src/models/geofence_event.dart';
export 'src/enums/accuracy.dart';
export 'src/enums/tracking_mode.dart';
export 'src/enums/geofence_transition.dart';

import 'src/libre_location_platform.dart';
import 'src/models/position.dart';
import 'src/models/location_config.dart';
import 'src/models/geofence.dart';
import 'src/models/geofence_event.dart';
import 'src/enums/accuracy.dart';

/// The main entry point for the libre_location plugin.
///
/// Provides background location tracking, geofencing, and motion detection
/// without any dependency on Google Play Services.
class LibreLocation {
  /// Start tracking location in the background.
  ///
  /// On Android, this starts a foreground service with a persistent notification.
  /// On iOS, this enables background location updates via CLLocationManager.
  static Future<void> startTracking(LocationConfig config) {
    return LibreLocationPlatform.instance.startTracking(config);
  }

  /// Stop all location tracking.
  static Future<void> stopTracking() {
    return LibreLocationPlatform.instance.stopTracking();
  }

  /// Get the current position as a one-shot request.
  ///
  /// Returns the best available position within a reasonable timeout.
  static Future<Position> getCurrentPosition({
    Accuracy accuracy = Accuracy.high,
  }) {
    return LibreLocationPlatform.instance.getCurrentPosition(accuracy: accuracy);
  }

  /// A stream of position updates.
  ///
  /// Updates are emitted based on the [LocationConfig] passed to [startTracking].
  static Stream<Position> get positionStream {
    return LibreLocationPlatform.instance.positionStream;
  }

  /// Whether location tracking is currently active.
  static Future<bool> get isTracking {
    return LibreLocationPlatform.instance.isTracking;
  }

  /// Add a geofence to monitor.
  ///
  /// On Android, uses `LocationManager.addProximityAlert()` (pure AOSP).
  /// On iOS, uses `CLLocationManager.startMonitoring(for: CLCircularRegion)`.
  static Future<void> addGeofence(Geofence geofence) {
    return LibreLocationPlatform.instance.addGeofence(geofence);
  }

  /// Remove a geofence by its ID.
  static Future<void> removeGeofence(String id) {
    return LibreLocationPlatform.instance.removeGeofence(id);
  }

  /// Get all currently registered geofences.
  static Future<List<Geofence>> getGeofences() {
    return LibreLocationPlatform.instance.getGeofences();
  }

  /// A stream of geofence events (enter, exit, dwell).
  static Stream<GeofenceEvent> get geofenceStream {
    return LibreLocationPlatform.instance.geofenceStream;
  }

  /// Check the current location permission status.
  static Future<LocationPermission> checkPermission() {
    return LibreLocationPlatform.instance.checkPermission();
  }

  /// Request location permission from the user.
  static Future<LocationPermission> requestPermission() {
    return LibreLocationPlatform.instance.requestPermission();
  }
}

/// Represents the current state of location permissions.
enum LocationPermission {
  /// Permission has not been requested yet.
  denied,

  /// Permission was denied permanently (user selected "Don't ask again").
  deniedForever,

  /// Permission granted for while-in-use only.
  whileInUse,

  /// Permission granted for always (background).
  always,
}
