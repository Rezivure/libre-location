import 'package:flutter_test/flutter_test.dart';
import 'package:libre_location/libre_location.dart';

void main() {
  group('Position', () {
    test('fromMap creates correct Position', () {
      final map = {
        'latitude': 37.7749,
        'longitude': -122.4194,
        'altitude': 10.0,
        'accuracy': 5.0,
        'speed': 1.5,
        'heading': 90.0,
        'timestamp': 1700000000000,
        'provider': 'gps',
      };

      final position = Position.fromMap(map);

      expect(position.latitude, 37.7749);
      expect(position.longitude, -122.4194);
      expect(position.altitude, 10.0);
      expect(position.accuracy, 5.0);
      expect(position.speed, 1.5);
      expect(position.heading, 90.0);
      expect(position.provider, 'gps');
    });

    test('toMap round-trips correctly', () {
      final position = Position(
        latitude: 37.7749,
        longitude: -122.4194,
        altitude: 10.0,
        accuracy: 5.0,
        speed: 1.5,
        heading: 90.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        provider: 'gps',
      );

      final map = position.toMap();
      final restored = Position.fromMap(map);

      expect(restored.latitude, position.latitude);
      expect(restored.longitude, position.longitude);
      expect(restored.provider, position.provider);
    });
  });

  group('LocationConfig', () {
    test('default values are correct', () {
      const config = LocationConfig();

      expect(config.accuracy, Accuracy.high);
      expect(config.intervalMs, 60000);
      expect(config.distanceFilter, 10.0);
      expect(config.mode, TrackingMode.balanced);
      expect(config.enableMotionDetection, true);
    });

    test('toMap/fromMap round-trips', () {
      const config = LocationConfig(
        accuracy: Accuracy.low,
        intervalMs: 5000,
        distanceFilter: 50.0,
        mode: TrackingMode.active,
        enableMotionDetection: false,
        notificationTitle: 'Test',
      );

      final map = config.toMap();
      final restored = LocationConfig.fromMap(map);

      expect(restored.accuracy, config.accuracy);
      expect(restored.intervalMs, config.intervalMs);
      expect(restored.distanceFilter, config.distanceFilter);
      expect(restored.mode, config.mode);
      expect(restored.enableMotionDetection, config.enableMotionDetection);
      expect(restored.notificationTitle, config.notificationTitle);
    });
  });

  group('Geofence', () {
    test('fromMap creates correct Geofence', () {
      final map = {
        'id': 'home',
        'latitude': 37.7749,
        'longitude': -122.4194,
        'radiusMeters': 100.0,
        'triggers': [0, 1],
        'dwellDurationMs': 30000,
      };

      final geofence = Geofence.fromMap(map);

      expect(geofence.id, 'home');
      expect(geofence.radiusMeters, 100.0);
      expect(geofence.triggers, {GeofenceTransition.enter, GeofenceTransition.exit});
      expect(geofence.dwellDuration, const Duration(seconds: 30));
    });
  });
}
