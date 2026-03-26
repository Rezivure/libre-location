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

  Stream<Position>? _positionStream;
  Stream<GeofenceEvent>? _geofenceStream;
  Stream<Position>? _motionChangeStream;
  Stream<ActivityEvent>? _activityChangeStream;
  Stream<ProviderEvent>? _providerChangeStream;
  Stream<HeartbeatEvent>? _heartbeatStream;

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
}
