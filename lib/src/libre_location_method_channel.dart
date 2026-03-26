import 'dart:ui' show PluginUtilities;

import 'package:flutter/services.dart';

import '../libre_location.dart';

/// The MethodChannel-based implementation of [LibreLocationPlatform].
class MethodChannelLibreLocation extends LibreLocationPlatform {
  static const MethodChannel _channel = MethodChannel('libre_location');
  static const EventChannel _positionChannel = EventChannel('libre_location/position');
  static const EventChannel _geofenceChannel = EventChannel('libre_location/geofence');
  static const EventChannel _motionChangeChannel = EventChannel('libre_location/motionChange');
  static const EventChannel _activityChangeChannel = EventChannel('libre_location/activityChange');
  static const EventChannel _providerChangeChannel = EventChannel('libre_location/providerChange');
  static const EventChannel _heartbeatChannel = EventChannel('libre_location/heartbeat');
  static const EventChannel _powerSaveChannel = EventChannel('libre_location/powerSaveChange');
  static const EventChannel _permissionChangeChannel = EventChannel('libre_location/permissionChange');

  Stream<Position>? _positionStream;
  Stream<GeofenceEvent>? _geofenceStream;
  Stream<Position>? _motionChangeStream;
  Stream<ActivityEvent>? _activityChangeStream;
  Stream<ProviderEvent>? _providerChangeStream;
  Stream<HeartbeatEvent>? _heartbeatStream;
  Stream<bool>? _powerSaveStream;
  Stream<LocationPermission>? _permissionChangeStream;

  @override
  Future<void> startTracking(LocationConfig config) async {
    await _channel.invokeMethod('startTracking', config.toMap());
  }

  @override
  Future<void> stopTracking() async {
    await _channel.invokeMethod('stopTracking');
  }

  @override
  Future<Position> getCurrentPosition({
    Accuracy accuracy = Accuracy.high,
    int samples = 3,
    int timeout = 30,
    int maximumAge = 0,
    bool persist = true,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCurrentPosition',
      {
        'accuracy': accuracy.index,
        'samples': samples,
        'timeout': timeout,
        'maximumAge': maximumAge,
        'persist': persist,
      },
    );
    return Position.fromMap(result!);
  }

  @override
  Future<void> setConfig(LocationConfig config) async {
    await _channel.invokeMethod('setConfig', config.toMap());
  }

  @override
  Stream<Position> get positionStream {
    _positionStream ??= _positionChannel
        .receiveBroadcastStream()
        .map((event) => Position.fromMap(Map<String, dynamic>.from(event as Map)));
    return _positionStream!;
  }

  @override
  Stream<Position> get motionChangeStream {
    _motionChangeStream ??= _motionChangeChannel
        .receiveBroadcastStream()
        .map((event) => Position.fromMap(Map<String, dynamic>.from(event as Map)));
    return _motionChangeStream!;
  }

  @override
  Stream<ActivityEvent> get activityChangeStream {
    _activityChangeStream ??= _activityChangeChannel
        .receiveBroadcastStream()
        .map((event) => ActivityEvent.fromMap(Map<String, dynamic>.from(event as Map)));
    return _activityChangeStream!;
  }

  @override
  Stream<ProviderEvent> get providerChangeStream {
    _providerChangeStream ??= _providerChangeChannel
        .receiveBroadcastStream()
        .map((event) => ProviderEvent.fromMap(Map<String, dynamic>.from(event as Map)));
    return _providerChangeStream!;
  }

  @override
  Stream<HeartbeatEvent> get heartbeatStream {
    _heartbeatStream ??= _heartbeatChannel
        .receiveBroadcastStream()
        .map((event) => HeartbeatEvent.fromMap(Map<String, dynamic>.from(event as Map)));
    return _heartbeatStream!;
  }

  @override
  Future<bool> get isTracking async {
    final result = await _channel.invokeMethod<bool>('isTracking');
    return result ?? false;
  }

  @override
  Future<void> addGeofence(Geofence geofence) async {
    await _channel.invokeMethod('addGeofence', geofence.toMap());
  }

  @override
  Future<void> removeGeofence(String id) async {
    await _channel.invokeMethod('removeGeofence', {'id': id});
  }

  @override
  Future<List<Geofence>> getGeofences() async {
    final result = await _channel.invokeListMethod<Map>('getGeofences');
    return result
            ?.map((m) => Geofence.fromMap(Map<String, dynamic>.from(m)))
            .toList() ??
        [];
  }

  @override
  Stream<GeofenceEvent> get geofenceStream {
    _geofenceStream ??= _geofenceChannel
        .receiveBroadcastStream()
        .map((event) => GeofenceEvent.fromMap(Map<String, dynamic>.from(event as Map)));
    return _geofenceStream!;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    final result = await _channel.invokeMethod<int>('checkPermission');
    return LocationPermission.values[result ?? 0];
  }

  @override
  Future<LocationPermission> requestPermission() async {
    final result = await _channel.invokeMethod<int>('requestPermission');
    return LocationPermission.values[result ?? 0];
  }

  @override
  Future<void> registerHeadlessDispatcher(
    void Function() dispatcherCallback,
    void Function(Map<String, dynamic>) userCallback,
  ) async {
    final dispatcherHandle = PluginUtilities.getCallbackHandle(dispatcherCallback)?.toRawHandle();
    final userHandle = PluginUtilities.getCallbackHandle(userCallback)?.toRawHandle();
    if (dispatcherHandle == null || userHandle == null) {
      throw ArgumentError('Callbacks must be top-level or static functions');
    }
    await _channel.invokeMethod('registerHeadlessDispatcher', {
      'dispatcherHandle': dispatcherHandle,
      'userCallbackHandle': userHandle,
    });
  }

  @override
  Future<bool> checkBatteryOptimization() async {
    final result = await _channel.invokeMethod<bool>('checkBatteryOptimization');
    return result ?? false;
  }

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    final result = await _channel.invokeMethod<bool>('requestBatteryOptimizationExemption');
    return result ?? false;
  }

  @override
  Future<Map<String, dynamic>> isAutoStartEnabled() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('isAutoStartEnabled');
    return result ?? {};
  }

  @override
  Future<bool> openPowerManagerSettings() async {
    final result = await _channel.invokeMethod<bool>('openPowerManagerSettings');
    return result ?? false;
  }

  @override
  Stream<bool> get powerSaveChangeStream {
    _powerSaveStream ??= _powerSaveChannel
        .receiveBroadcastStream()
        .map((event) => event as bool);
    return _powerSaveStream!;
  }

  @override
  Future<int> requestTemporaryFullAccuracy({required String purposeKey}) async {
    final result = await _channel.invokeMethod<int>(
      'requestTemporaryFullAccuracy',
      {'purposeKey': purposeKey},
    );
    return result ?? 1; // default to reducedAccuracy
  }

  @override
  Future<void> changePace(bool isMoving) async {
    await _channel.invokeMethod('changePace', {'isMoving': isMoving});
  }

  @override
  Future<List<Map<String, dynamic>>> getLog() async {
    final result = await _channel.invokeListMethod<Map>('getLog');
    return result
            ?.map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
  }

  @override
  Future<LocationPermission> requestAlwaysPermission() async {
    final result = await _channel.invokeMethod<int>('requestAlwaysPermission');
    return LocationPermission.values[result ?? 0];
  }

  @override
  Future<bool> openAppSettings() async {
    final result = await _channel.invokeMethod<bool>('openAppSettings');
    return result ?? false;
  }

  @override
  Future<bool> openLocationSettings() async {
    final result = await _channel.invokeMethod<bool>('openLocationSettings');
    return result ?? false;
  }

  @override
  Stream<LocationPermission> get permissionChangeStream {
    _permissionChangeStream ??= _permissionChangeChannel
        .receiveBroadcastStream()
        .map((event) => LocationPermission.values[event as int]);
    return _permissionChangeStream!;
  }

  @override
  Future<bool> shouldShowRequestRationale() async {
    final result = await _channel.invokeMethod<bool>('shouldShowRequestRationale');
    return result ?? false;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    final result = await _channel.invokeMethod<bool>('isLocationServiceEnabled');
    return result ?? false;
  }

  @override
  Future<bool> checkNotificationPermission() async {
    final result = await _channel.invokeMethod<bool>('checkNotificationPermission');
    return result ?? false;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final result = await _channel.invokeMethod<bool>('requestNotificationPermission');
    return result ?? false;
  }
}
