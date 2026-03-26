import 'position.dart';

/// Event emitted on heartbeat intervals with the latest known position.
class HeartbeatEvent {
  final Position position;

  const HeartbeatEvent({required this.position});

  factory HeartbeatEvent.fromMap(Map<String, dynamic> map) {
    return HeartbeatEvent(
      position: Position.fromMap(
        map['position'] != null
            ? Map<String, dynamic>.from(map['position'] as Map)
            : map,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'position': position.toMap(),
    };
  }

  @override
  String toString() => 'HeartbeatEvent(position: $position)';
}
