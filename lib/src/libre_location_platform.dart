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
}
