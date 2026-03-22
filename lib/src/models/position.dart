/// Represents a geographic position with metadata.
class Position {
  /// Latitude in degrees.
  final double latitude;

  /// Longitude in degrees.
  final double longitude;

  /// Altitude in meters above the WGS84 ellipsoid.
  final double altitude;

  /// Estimated horizontal accuracy in meters.
  final double accuracy;

  /// Speed in meters per second.
  final double speed;

  /// Heading (bearing) in degrees from true north.
  final double heading;

  /// The time at which this position was determined.
  final DateTime timestamp;

  /// The provider that generated this position ('gps', 'network', 'passive').
  final String provider;

  const Position({
    required this.latitude,
    required this.longitude,
    this.altitude = 0.0,
    this.accuracy = 0.0,
    this.speed = 0.0,
    this.heading = 0.0,
    required this.timestamp,
    this.provider = 'unknown',
  });

  /// Creates a [Position] from a platform-specific map.
  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num).toInt(),
      ),
      provider: map['provider'] as String? ?? 'unknown',
    );
  }

  /// Converts this position to a map for platform communication.
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'provider': provider,
    };
  }

  @override
  String toString() =>
      'Position(lat: $latitude, lng: $longitude, acc: ${accuracy}m, provider: $provider)';
}
