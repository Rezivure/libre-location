/// Migration example: Grid's location_manager.dart with libre_location presets.
///
/// BEFORE (flutter_background_geolocation): ~370 lines
///   - 4 different config contexts (foreground, background, battery saver, activity-based)
///   - 15+ hardcoded magic numbers per config
///   - Manual lifecycle listener for foreground/background switching
///   - Manual activity-based config adjustment with switch statements
///   - Manual throttling logic
///
/// AFTER (libre_location presets): ~100 lines
///   - Plugin handles ALL adaptation internally
///   - No lifecycle management needed
///   - No activity-based config switching needed
///   - No magic numbers anywhere

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:libre_location/libre_location.dart';

class LocationManager with ChangeNotifier {
  final StreamController<Position> _locationStreamController =
      StreamController.broadcast();

  Position? _lastPosition;
  bool _isTracking = false;
  bool _batterySaverEnabled = false;
  DateTime? _lastLocationUpdate;

  // Subscriptions
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<Position>? _motionSub;

  LocationManager();

  Stream<Position> get locationStream => _locationStreamController.stream;

  double? get currentLat => _lastPosition?.latitude;
  double? get currentLng => _lastPosition?.longitude;

  bool get isTracking => _isTracking;
  bool get batterySaverEnabled => _batterySaverEnabled;
  DateTime? get lastLocationUpdate => _lastLocationUpdate;

  bool get isLocationStale {
    if (_lastLocationUpdate == null) return true;
    return DateTime.now().difference(_lastLocationUpdate!) >
        const Duration(minutes: 10);
  }

  /// Toggle battery saver — just switches between presets.
  Future<void> toggleBatterySaverMode(bool enabled) async {
    _batterySaverEnabled = enabled;
    if (_isTracking) {
      // That's it. One line. The plugin handles everything else.
      await LibreLocation.setPreset(
        enabled ? TrackingPreset.low : TrackingPreset.balanced,
      );
    }
    notifyListeners();
  }

  /// Start tracking. The plugin auto-adapts to:
  /// - Foreground/background (lifecycle)
  /// - Activity (driving/walking/cycling/still)
  /// - Stationary optimization (reduced GPS, heartbeat alive)
  Future<void> startTracking() async {
    if (_isTracking) return;

    // Request permissions
    final permission = await LibreLocation.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    // Start with one line — everything else is automatic
    await LibreLocation.start(
      preset: _batterySaverEnabled ? TrackingPreset.low : TrackingPreset.balanced,
      config: const LocationConfig(
        notification: NotificationConfig(
          title: 'Location Sharing',
          text: 'Active',
        ),
      ),
    );

    // Listen for updates
    _locationSub = LibreLocation.onLocation.listen((position) {
      _lastPosition = position;
      _lastLocationUpdate = DateTime.now();
      _locationStreamController.add(position);
      notifyListeners();
    });

    _motionSub = LibreLocation.onMotionChange.listen((position) {
      _lastPosition = position;
      if (position.isMoving) {
        _lastLocationUpdate = DateTime.now();
        _locationStreamController.add(position);
        notifyListeners();
      }
    });

    _isTracking = true;
    notifyListeners();
  }

  /// Manual location ping (e.g., "share my location now" button).
  Future<void> grabLocationAndPing() async {
    final pos = await LibreLocation.getCurrentPosition(
      samples: 3,
      accuracy: Accuracy.high,
    );
    _lastPosition = pos;
    _lastLocationUpdate = DateTime.now();
    _locationStreamController.add(pos);
    notifyListeners();
  }

  Future<void> stopTracking() async {
    if (!_isTracking) return;
    await LibreLocation.stop();
    _locationSub?.cancel();
    _motionSub?.cancel();
    _isTracking = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _motionSub?.cancel();
    _locationStreamController.close();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════
// What was removed (all handled internally by the plugin now):
// ═══════════════════════════════════════════════════════════════
//
// ✗ AppLifecycleListener + _isInForeground tracking
// ✗ _updateTrackingConfig() with 3 different Config blocks
// ✗ onActivityChange handler with switch(activity) config adjustment
// ✗ Manual throttling logic (timeSinceLastUpdate, throttleInterval)
// ✗ 60+ lines of bg.Config() with hardcoded values like:
//     - desiredAccuracy, distanceFilter, stopTimeout,
//     - stopDetectionDelay, stationaryRadius, heartbeatInterval,
//     - activityRecognitionInterval, minimumActivityRecognitionConfidence,
//     - disableMotionActivityUpdates, pausesLocationUpdatesAutomatically...
// ✗ SharedPreferences for battery saver state (now just a preset switch)
//
// Lines: 368 → ~100 (73% reduction)
// Config params managed by developer: 15+ → 0
// Adaptation logic managed by developer: 4 contexts → 0
