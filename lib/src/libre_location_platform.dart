import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../libre_location.dart';
import 'libre_location_method_channel.dart';

/// The platform interface for the libre_location plugin.
abstract class LibreLocationPlatform extends PlatformInterface {
  LibreLocationPlatform() : super(token: _token);

  static final Object _token = Object();

  static LibreLocationPlatform _instance = MethodChannelLibreLocation();

  /// The current platform-specific implementation.
  static LibreLocationPlatform get instance => _instance;

  /// Set the platform-specific implementation (for testing).
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

  Future<Position> getCurrentPosition({Accuracy accuracy = Accuracy.high}) {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  Stream<Position> get positionStream {
    throw UnimplementedError('positionStream has not been implemented.');
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
