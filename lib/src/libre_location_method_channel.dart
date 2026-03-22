import 'package:flutter/services.dart';

import '../libre_location.dart';
import 'libre_location_platform.dart';

/// The MethodChannel-based implementation of [LibreLocationPlatform].
class MethodChannelLibreLocation extends LibreLocationPlatform {
  static const MethodChannel _channel = MethodChannel('libre_location');
  static const EventChannel _positionChannel =
      EventChannel('libre_location/position');
  static const EventChannel _geofenceChannel =
      EventChannel('libre_location/geofence');

  Stream<Position>? _positionStream;
  Stream<GeofenceEvent>? _geofenceStream;

  @override
  Future<void> startTracking(LocationConfig config) async {
    await _channel.invokeMethod('startTracking', config.toMap());
  }

  @override
  Future<void> stopTracking() async {
    await _channel.invokeMethod('stopTracking');
  }

  @override
  Future<Position> getCurrentPosition({Accuracy accuracy = Accuracy.high}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCurrentPosition',
      {'accuracy': accuracy.index},
    );
    return Position.fromMap(result!);
  }

  @override
  Stream<Position> get positionStream {
    _positionStream ??= _positionChannel
        .receiveBroadcastStream()
        .map((event) => Position.fromMap(Map<String, dynamic>.from(event)));
    return _positionStream!;
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
        .map((event) =>
            GeofenceEvent.fromMap(Map<String, dynamic>.from(event)));
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
