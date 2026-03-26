import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_location/libre_location.dart';

/// Mock-based tests simulating the full tracking lifecycle through method channels.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('libre_location'),
      (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'startTracking':
            return null;
          case 'stopTracking':
            return null;
          case 'isTracking':
            return methodCalls.any((c) => c.method == 'startTracking');
          case 'getCurrentPosition':
            return <String, dynamic>{
              'latitude': 37.42,
              'longitude': -122.08,
              'altitude': 10.0,
              'accuracy': 5.0,
              'speed': 1.5,
              'heading': 90.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'provider': 'gps',
              'isMoving': true,
            };
          case 'checkPermission':
            return 3; // always
          case 'requestPermission':
            return 3;
          case 'addGeofence':
            return null;
          case 'removeGeofence':
            return null;
          case 'getGeofences':
            return <Map<String, dynamic>>[];
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('libre_location'), null);
  });

  group('Tracking Flow', () {
    test('startTracking sends correct method call', () async {
      await LibreLocation.startTracking(LocationConfig(
        accuracy: Accuracy.high,
        mode: TrackingMode.balanced,
        distanceFilter: 10.0,
        intervalMs: 60000,
      ));

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'startTracking');
      final args = methodCalls[0].arguments as Map;
      expect(args['accuracy'], 0);
      expect(args['mode'], 1);
      expect(args['distanceFilter'], 10.0);
      expect(args['intervalMs'], 60000);
    });

    test('stopTracking sends correct method call', () async {
      await LibreLocation.stopTracking();
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'stopTracking');
    });

    test('full flow: start → getCurrentPosition → stop', () async {
      await LibreLocation.startTracking(LocationConfig(
        accuracy: Accuracy.high,
      ));

      final position = await LibreLocation.getCurrentPosition(
        accuracy: Accuracy.high,
        timeout: 10,
      );

      expect(position.latitude, 37.42);
      expect(position.longitude, -122.08);
      expect(position.isMoving, true);

      await LibreLocation.stopTracking();

      expect(methodCalls.length, 3);
      expect(methodCalls[0].method, 'startTracking');
      expect(methodCalls[1].method, 'getCurrentPosition');
      expect(methodCalls[2].method, 'stopTracking');
    });
  });

  group('getCurrentPosition', () {
    test('returns position with correct fields', () async {
      final position = await LibreLocation.getCurrentPosition();
      expect(position.latitude, 37.42);
      expect(position.longitude, -122.08);
      expect(position.provider, 'gps');
    });

    test('passes parameters correctly', () async {
      await LibreLocation.getCurrentPosition(
        accuracy: Accuracy.low,
        samples: 5,
        timeout: 15,
        maximumAge: 10000,
      );

      final args = methodCalls[0].arguments as Map;
      expect(args['accuracy'], 2);
      expect(args['samples'], 5);
      expect(args['timeout'], 15);
      expect(args['maximumAge'], 10000);
    });
  });

  group('Permissions', () {
    test('checkPermission returns correct value', () async {
      final result = await LibreLocation.checkPermission();
      expect(result, LocationPermission.always);
    });

    test('requestPermission returns correct value', () async {
      final result = await LibreLocation.requestPermission();
      expect(result, LocationPermission.always);
    });
  });

  group('Geofencing', () {
    test('addGeofence sends correct method call', () async {
      await LibreLocation.addGeofence(Geofence(
        id: 'test',
        latitude: 37.42,
        longitude: -122.08,
        radiusMeters: 100,
        triggers: {GeofenceTransition.enter, GeofenceTransition.exit},
      ));

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'addGeofence');
      final args = methodCalls[0].arguments as Map;
      expect(args['id'], 'test');
      expect(args['latitude'], 37.42);
      expect(args['radiusMeters'], 100.0);
    });

    test('removeGeofence sends correct method call', () async {
      await LibreLocation.removeGeofence('test');
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'removeGeofence');
    });
  });
}
