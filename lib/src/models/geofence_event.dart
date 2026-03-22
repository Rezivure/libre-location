import '../enums/geofence_transition.dart';
import 'geofence.dart';

/// An event emitted when a geofence transition occurs.
class GeofenceEvent {
  /// The geofence that triggered this event.
  final Geofence geofence;

  /// The type of transition that occurred.
  final GeofenceTransition transition;

  /// The time at which the transition was detected.
  final DateTime timestamp;

  const GeofenceEvent({
    required this.geofence,
    required this.transition,
    required this.timestamp,
  });

  /// Creates a [GeofenceEvent] from a platform-specific map.
  factory GeofenceEvent.fromMap(Map<String, dynamic> map) {
    return GeofenceEvent(
      geofence: Geofence.fromMap(map['geofence'] as Map<String, dynamic>),
      transition: GeofenceTransition.values[map['transition'] as int],
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num).toInt(),
      ),
    );
  }

  @override
  String toString() =>
      'GeofenceEvent(${geofence.id}, ${transition.name}, $timestamp)';
}
