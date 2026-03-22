import '../enums/geofence_transition.dart';

/// Represents a circular geofence region to monitor.
class Geofence {
  /// Unique identifier for this geofence.
  final String id;

  /// Center latitude in degrees.
  final double latitude;

  /// Center longitude in degrees.
  final double longitude;

  /// Radius of the geofence in meters.
  final double radiusMeters;

  /// The transitions to monitor (enter, exit, dwell).
  final Set<GeofenceTransition> triggers;

  /// How long the device must remain inside the region to trigger a dwell event.
  /// Only used when [GeofenceTransition.dwell] is in [triggers].
  final Duration? dwellDuration;

  const Geofence({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.triggers = const {GeofenceTransition.enter, GeofenceTransition.exit},
    this.dwellDuration,
  });

  /// Converts this geofence to a map for platform communication.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'triggers': triggers.map((t) => t.index).toList(),
      'dwellDurationMs': dwellDuration?.inMilliseconds,
    };
  }

  /// Creates a [Geofence] from a platform-specific map.
  factory Geofence.fromMap(Map<String, dynamic> map) {
    return Geofence(
      id: map['id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radiusMeters'] as num).toDouble(),
      triggers: (map['triggers'] as List<dynamic>?)
              ?.map((i) => GeofenceTransition.values[i as int])
              .toSet() ??
          {GeofenceTransition.enter, GeofenceTransition.exit},
      dwellDuration: map['dwellDurationMs'] != null
          ? Duration(milliseconds: map['dwellDurationMs'] as int)
          : null,
    );
  }

  @override
  String toString() =>
      'Geofence(id: $id, lat: $latitude, lng: $longitude, radius: ${radiusMeters}m)';
}
