import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libre_location/libre_location.dart';

void main() {
  // ── Position model tests ──

  group('Position', () {
    test('fromMap creates correct Position with all fields', () {
      final map = {
        'latitude': 37.7749,
        'longitude': -122.4194,
        'altitude': 10.0,
        'accuracy': 5.0,
        'speed': 1.5,
        'heading': 90.0,
        'timestamp': 1700000000000,
        'provider': 'gps',
        'isMoving': true,
        'activity': {'activity': 'walking', 'confidence': 85},
        'battery': {'level': 0.75, 'isCharging': true},
        'speedAccuracy': 0.5,
        'headingAccuracy': 3.0,
      };

      final position = Position.fromMap(map);

      expect(position.latitude, 37.7749);
      expect(position.longitude, -122.4194);
      expect(position.altitude, 10.0);
      expect(position.accuracy, 5.0);
      expect(position.speed, 1.5);
      expect(position.heading, 90.0);
      expect(position.provider, 'gps');
      expect(position.isMoving, true);
      expect(position.activity?.activity, 'walking');
      expect(position.activity?.confidence, 85);
      expect(position.battery?.level, 0.75);
      expect(position.battery?.isCharging, true);
      expect(position.speedAccuracy, 0.5);
      expect(position.headingAccuracy, 3.0);
    });

    test('fromMap handles minimal data', () {
      final map = {
        'latitude': 0.0,
        'longitude': 0.0,
        'timestamp': 0,
      };

      final position = Position.fromMap(map);

      expect(position.latitude, 0.0);
      expect(position.altitude, 0.0);
      expect(position.isMoving, false);
      expect(position.activity, isNull);
      expect(position.battery, isNull);
      expect(position.speedAccuracy, isNull);
      expect(position.provider, 'unknown');
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
        isMoving: true,
        activity: const ActivityEvent(activity: 'driving', confidence: 90),
        battery: const BatteryInfo(level: 0.5, isCharging: false),
        speedAccuracy: 1.0,
        headingAccuracy: 5.0,
      );

      final map = position.toMap();
      final restored = Position.fromMap(map);

      expect(restored.latitude, position.latitude);
      expect(restored.longitude, position.longitude);
      expect(restored.isMoving, position.isMoving);
      expect(restored.activity?.activity, 'driving');
      expect(restored.battery?.level, 0.5);
      expect(restored.speedAccuracy, 1.0);
      expect(restored.headingAccuracy, 5.0);
    });

    test('toMap omits null optional fields', () {
      final position = Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final map = position.toMap();

      expect(map.containsKey('activity'), false);
      expect(map.containsKey('battery'), false);
      expect(map.containsKey('speedAccuracy'), false);
      expect(map.containsKey('headingAccuracy'), false);
    });

    test('copyWith creates modified copy', () {
      final position = Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final modified = position.copyWith(latitude: 99.0, isMoving: true);

      expect(modified.latitude, 99.0);
      expect(modified.longitude, 2.0);
      expect(modified.isMoving, true);
    });

    test('toString includes key fields', () {
      final position = Position(
        latitude: 1.0,
        longitude: 2.0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        isMoving: true,
        provider: 'gps',
      );

      final str = position.toString();
      expect(str, contains('1.0'));
      expect(str, contains('2.0'));
      expect(str, contains('moving: true'));
    });
  });

  // ── ActivityEvent model tests ──

  group('ActivityEvent', () {
    test('fromMap creates correct event', () {
      final event = ActivityEvent.fromMap({
        'activity': 'running',
        'confidence': 95,
      });

      expect(event.activity, 'running');
      expect(event.confidence, 95);
    });

    test('fromMap handles missing values', () {
      final event = ActivityEvent.fromMap({});

      expect(event.activity, 'unknown');
      expect(event.confidence, 0);
    });

    test('toMap round-trips', () {
      const event = ActivityEvent(activity: 'still', confidence: 100);
      final restored = ActivityEvent.fromMap(event.toMap());

      expect(restored.activity, 'still');
      expect(restored.confidence, 100);
    });

    test('equality', () {
      const a = ActivityEvent(activity: 'walking', confidence: 80);
      const b = ActivityEvent(activity: 'walking', confidence: 80);
      const c = ActivityEvent(activity: 'running', confidence: 80);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });

  // ── BatteryInfo model tests ──

  group('BatteryInfo', () {
    test('fromMap creates correct info', () {
      final info = BatteryInfo.fromMap({
        'level': 0.85,
        'isCharging': true,
      });

      expect(info.level, 0.85);
      expect(info.isCharging, true);
    });

    test('fromMap handles missing values', () {
      final info = BatteryInfo.fromMap({});

      expect(info.level, -1.0);
      expect(info.isCharging, false);
    });

    test('equality', () {
      const a = BatteryInfo(level: 0.5, isCharging: false);
      const b = BatteryInfo(level: 0.5, isCharging: false);
      const c = BatteryInfo(level: 0.5, isCharging: true);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString', () {
      const info = BatteryInfo(level: 0.75, isCharging: true);
      expect(info.toString(), contains('75%'));
      expect(info.toString(), contains('true'));
    });
  });

  // ── ProviderEvent model tests ──

  group('ProviderEvent', () {
    test('fromMap creates correct event', () {
      final event = ProviderEvent.fromMap({
        'enabled': true,
        'status': 3,
        'gps': true,
        'network': false,
      });

      expect(event.enabled, true);
      expect(event.status, 3);
      expect(event.gps, true);
      expect(event.network, false);
    });

    test('fromMap handles missing values', () {
      final event = ProviderEvent.fromMap({});

      expect(event.enabled, false);
      expect(event.status, 0);
      expect(event.gps, false);
      expect(event.network, false);
    });

    test('toMap round-trips', () {
      const event = ProviderEvent(enabled: true, status: 2, gps: true, network: true);
      final restored = ProviderEvent.fromMap(event.toMap());

      expect(restored.enabled, true);
      expect(restored.status, 2);
      expect(restored.gps, true);
      expect(restored.network, true);
    });

    test('equality', () {
      const a = ProviderEvent(enabled: true, status: 1, gps: true, network: false);
      const b = ProviderEvent(enabled: true, status: 1, gps: true, network: false);
      const c = ProviderEvent(enabled: false, status: 1, gps: true, network: false);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  // ── HeartbeatEvent model tests ──

  group('HeartbeatEvent', () {
    test('fromMap with nested position', () {
      final event = HeartbeatEvent.fromMap({
        'position': {
          'latitude': 37.0,
          'longitude': -122.0,
          'timestamp': 1700000000000,
        },
      });

      expect(event.position.latitude, 37.0);
      expect(event.position.longitude, -122.0);
    });

    test('fromMap with flat position (fallback)', () {
      final event = HeartbeatEvent.fromMap({
        'latitude': 37.0,
        'longitude': -122.0,
        'timestamp': 1700000000000,
      });

      expect(event.position.latitude, 37.0);
    });

    test('toMap round-trips', () {
      final event = HeartbeatEvent(
        position: Position(
          latitude: 1.0,
          longitude: 2.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );

      final map = event.toMap();
      expect(map['position'], isA<Map>());
      expect((map['position'] as Map)['latitude'], 1.0);
    });
  });

  // ── NotificationConfig model tests ──

  group('NotificationConfig', () {
    test('default values', () {
      const config = NotificationConfig();

      expect(config.title, isNull);
      expect(config.text, isNull);
      expect(config.sticky, true);
      expect(config.priority, NotificationPriority.defaultPriority);
    });

    test('toMap/fromMap round-trips', () {
      const config = NotificationConfig(
        title: 'Tracking',
        text: 'Location is being tracked',
        sticky: false,
        priority: NotificationPriority.high,
      );

      final map = config.toMap();
      final restored = NotificationConfig.fromMap(map);

      expect(restored.title, 'Tracking');
      expect(restored.text, 'Location is being tracked');
      expect(restored.sticky, false);
      expect(restored.priority, NotificationPriority.high);
    });

    test('toMap omits null title/text', () {
      const config = NotificationConfig();
      final map = config.toMap();

      expect(map.containsKey('title'), false);
      expect(map.containsKey('text'), false);
      expect(map['sticky'], true);
    });
  });

  // ── PermissionRationale model tests ──

  group('PermissionRationale', () {
    test('fromMap creates correct rationale', () {
      final rationale = PermissionRationale.fromMap({
        'title': 'Background Location',
        'message': 'We need this to track you',
        'positiveAction': 'OK',
        'negativeAction': 'No',
      });

      expect(rationale.title, 'Background Location');
      expect(rationale.message, 'We need this to track you');
      expect(rationale.positiveAction, 'OK');
      expect(rationale.negativeAction, 'No');
    });

    test('default actions', () {
      const rationale = PermissionRationale(
        title: 'Test',
        message: 'Test',
      );

      expect(rationale.positiveAction, 'Allow');
      expect(rationale.negativeAction, 'Deny');
    });

    test('toMap round-trips', () {
      const rationale = PermissionRationale(
        title: 'T',
        message: 'M',
        positiveAction: 'Yes',
        negativeAction: 'No',
      );

      final restored = PermissionRationale.fromMap(rationale.toMap());
      expect(restored.title, 'T');
      expect(restored.positiveAction, 'Yes');
    });
  });

  // ── LocationConfig model tests ──

  group('LocationConfig', () {
    test('default values are correct', () {
      const config = LocationConfig();

      expect(config.stopOnTerminate, false);
      expect(config.startOnBoot, true);
      expect(config.enableHeadless, true);
      expect(config.debug, false);
      expect(config.notification, isNull);
      expect(config.backgroundPermissionRationale, isNull);
    });

    test('copyWith replaces fields', () {
      const config = LocationConfig();
      final modified = config.copyWith(
        debug: true,
        stopOnTerminate: true,
      );

      expect(modified.debug, true);
      expect(modified.stopOnTerminate, true);
      // unchanged
      expect(modified.startOnBoot, true);
      expect(modified.enableHeadless, true);
    });

    test('toString includes key fields', () {
      const config = LocationConfig(debug: true);
      final str = config.toString();
      expect(str, contains('debug: true'));
    });
  });

  // ── NativeConfig model tests ──

  group('NativeConfig', () {
    test('default values are correct', () {
      const config = NativeConfig();

      expect(config.accuracy, Accuracy.high);
      expect(config.intervalMs, 60000);
      expect(config.distanceFilter, 10.0);
      expect(config.mode, TrackingMode.balanced);
      expect(config.enableMotionDetection, true);
      expect(config.stopOnTerminate, true);
      expect(config.startOnBoot, false);
      expect(config.enableHeadless, false);
      expect(config.stillnessTimeoutMin, 5);
      expect(config.stillnessDelayMs, 0);
      expect(config.stillnessRadiusMeters, 25.0);
      expect(config.skipStillnessDetection, false);
      expect(config.skipActivityUpdates, false);
      expect(config.motionConfirmDelayMs, 0);
      expect(config.significantChangesOnly, false);
      expect(config.initiallyMoving, false);
      expect(config.activityCheckIntervalMs, 10000);
      expect(config.activityConfidenceThreshold, 75);
      expect(config.heartbeatInterval, 0);
      expect(config.activityType, ActivityType.other);
      expect(config.pausesLocationUpdatesAutomatically, false);
      expect(config.keepAwake, false);
      expect(config.retentionDays, 1);
      expect(config.retentionMaxRecords, -1);
      expect(config.debug, false);
      expect(config.logLevel, LogLevel.off);
      expect(config.notification, isNull);
      expect(config.backgroundPermissionRationale, isNull);
      expect(config.locationAuthorizationRequest,
          LocationAuthorizationRequest.always);
    });

    test('toMap produces correct keys for native layer', () {
      const config = NativeConfig(
        stillnessDelayMs: 3,
        skipStillnessDetection: true,
        skipActivityUpdates: true,
        motionConfirmDelayMs: 500,
        significantChangesOnly: true,
        initiallyMoving: true,
        activityCheckIntervalMs: 5000,
        activityConfidenceThreshold: 50,
        keepAwake: true,
        retentionDays: 7,
        retentionMaxRecords: 1000,
      );

      final map = config.toMap();

      expect(map['stillnessDelayMs'], 3);
      expect(map['skipStillnessDetection'], true);
      expect(map['skipActivityUpdates'], true);
      expect(map['motionConfirmDelayMs'], 500);
      expect(map['significantChangesOnly'], true);
      expect(map['initiallyMoving'], true);
      expect(map['activityCheckIntervalMs'], 5000);
      expect(map['activityConfidenceThreshold'], 50);
      expect(map['keepAwake'], true);
      expect(map['retentionDays'], 7);
      expect(map['retentionMaxRecords'], 1000);
      // Verify no legacy keys are emitted
      expect(map.containsKey('stopDetectionDelay'), false);
      expect(map.containsKey('disableStopDetection'), false);
      expect(map.containsKey('preventSuspend'), false);
      expect(map.containsKey('maxDaysToPersist'), false);
    });

    test('copyWith replaces fields', () {
      const config = NativeConfig();
      final modified = config.copyWith(
        debug: true,
        heartbeatInterval: 60,
      );

      expect(modified.debug, true);
      expect(modified.heartbeatInterval, 60);
      // unchanged
      expect(modified.distanceFilter, 10.0);
      expect(modified.stopOnTerminate, true);
    });
  });

  // ── Geofence model tests ──

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
      expect(
          geofence.triggers, {GeofenceTransition.enter, GeofenceTransition.exit});
      expect(geofence.dwellDuration, const Duration(seconds: 30));
    });

    test('toMap round-trips', () {
      const geofence = Geofence(
        id: 'work',
        latitude: 40.0,
        longitude: -74.0,
        radiusMeters: 200.0,
        triggers: {GeofenceTransition.enter, GeofenceTransition.dwell},
        dwellDuration: Duration(minutes: 5),
      );

      final map = geofence.toMap();
      final restored = Geofence.fromMap(map);

      expect(restored.id, 'work');
      expect(restored.radiusMeters, 200.0);
      expect(restored.triggers,
          {GeofenceTransition.enter, GeofenceTransition.dwell});
      expect(restored.dwellDuration, const Duration(minutes: 5));
    });

    test('toString', () {
      const geofence = Geofence(
        id: 'test',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 50.0,
      );

      expect(geofence.toString(), contains('test'));
      expect(geofence.toString(), contains('50.0'));
    });
  });

  // ── GeofenceEvent model tests ──

  group('GeofenceEvent', () {
    test('fromMap creates correct event', () {
      final event = GeofenceEvent.fromMap({
        'geofence': {
          'id': 'home',
          'latitude': 37.0,
          'longitude': -122.0,
          'radiusMeters': 100.0,
        },
        'transition': 0,
        'timestamp': 1700000000000,
      });

      expect(event.geofence.id, 'home');
      expect(event.transition, GeofenceTransition.enter);
    });
  });

  // ── Enum tests ──

  group('Enums', () {
    test('Accuracy has all values', () {
      expect(Accuracy.values.length, 5);
      expect(Accuracy.values, contains(Accuracy.navigation));
    });

    test('ActivityType has all values', () {
      expect(ActivityType.values.length, 4);
      expect(ActivityType.values,
          containsAll([ActivityType.other, ActivityType.automotive,
            ActivityType.fitness, ActivityType.navigation]));
    });

    test('LogLevel has all values', () {
      expect(LogLevel.values.length, 6);
    });

    test('LocationAuthorizationRequest has all values', () {
      expect(LocationAuthorizationRequest.values.length, 2);
    });

    test('NotificationPriority has all values', () {
      expect(NotificationPriority.values.length, 5);
    });

    test('LocationPermission has all values', () {
      expect(LocationPermission.values.length, 4);
    });
  });

  // ── Method channel tests ──

  group('MethodChannelLibreLocation', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late MethodChannelLibreLocation platform;
    final List<MethodCall> log = [];

    setUp(() {
      platform = MethodChannelLibreLocation();
      log.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('libre_location'),
        (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'startTracking':
              return null;
            case 'stopTracking':
              return null;
            case 'getCurrentPosition':
              return {
                'latitude': 37.0,
                'longitude': -122.0,
                'timestamp': 1700000000000,
              };
            case 'setConfig':
              return null;
            case 'isTracking':
              return true;
            case 'addGeofence':
              return null;
            case 'removeGeofence':
              return null;
            case 'getGeofences':
              return [
                {
                  'id': 'home',
                  'latitude': 37.0,
                  'longitude': -122.0,
                  'radiusMeters': 100.0,
                }
              ];
            case 'checkPermission':
              return 3; // always
            case 'requestPermission':
              return 2; // whileInUse
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('libre_location'),
        null,
      );
    });

    test('startTracking sends config', () async {
      const config = NativeConfig(
        accuracy: Accuracy.high,
        distanceFilter: 20.0,
        debug: true,
      );
      await platform.startTracking(config);

      expect(log.length, 1);
      expect(log.first.method, 'startTracking');
      final args = log.first.arguments as Map;
      expect(args['distanceFilter'], 20.0);
      expect(args['debug'], true);
    });

    test('stopTracking calls method', () async {
      await platform.stopTracking();

      expect(log.length, 1);
      expect(log.first.method, 'stopTracking');
    });

    test('getCurrentPosition with parameters', () async {
      final position = await platform.getCurrentPosition(
        accuracy: Accuracy.navigation,
        samples: 5,
        timeout: 60,
        maximumAge: 10,
        persist: false,
      );

      expect(log.first.method, 'getCurrentPosition');
      final args = log.first.arguments as Map;
      expect(args['accuracy'], Accuracy.navigation.index);
      expect(args['samples'], 5);
      expect(args['timeout'], 60);
      expect(args['maximumAge'], 10);
      expect(args['persist'], false);
      expect(position.latitude, 37.0);
    });

    test('setConfig sends config', () async {
      const config = NativeConfig(heartbeatInterval: 60);
      await platform.setConfig(config);

      expect(log.first.method, 'setConfig');
      final args = log.first.arguments as Map;
      expect(args['heartbeatInterval'], 60);
    });

    test('isTracking returns correct value', () async {
      final result = await platform.isTracking;
      expect(result, true);
    });

    test('addGeofence sends geofence data', () async {
      const geofence = Geofence(
        id: 'test',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );
      await platform.addGeofence(geofence);

      expect(log.first.method, 'addGeofence');
      final args = log.first.arguments as Map;
      expect(args['id'], 'test');
    });

    test('removeGeofence sends id', () async {
      await platform.removeGeofence('test');

      expect(log.first.method, 'removeGeofence');
      final args = log.first.arguments as Map;
      expect(args['id'], 'test');
    });

    test('getGeofences returns list', () async {
      final geofences = await platform.getGeofences();

      expect(geofences.length, 1);
      expect(geofences.first.id, 'home');
    });

    test('checkPermission returns correct enum', () async {
      final perm = await platform.checkPermission();
      expect(perm, LocationPermission.always);
    });

    test('requestPermission returns correct enum', () async {
      final perm = await platform.requestPermission();
      expect(perm, LocationPermission.whileInUse);
    });
  });
}
