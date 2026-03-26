/// Represents a detected motion activity change.
class ActivityEvent {
  /// The activity type (e.g., 'still', 'walking', 'running', 'in_vehicle', 'on_bicycle', 'unknown').
  final String activity;

  /// Confidence of the activity detection, 0-100.
  final int confidence;

  const ActivityEvent({
    required this.activity,
    required this.confidence,
  });

  factory ActivityEvent.fromMap(Map<String, dynamic> map) {
    return ActivityEvent(
      activity: map['activity'] as String? ?? 'unknown',
      confidence: (map['confidence'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activity': activity,
      'confidence': confidence,
    };
  }

  @override
  String toString() => 'ActivityEvent($activity, confidence: $confidence)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityEvent &&
          runtimeType == other.runtimeType &&
          activity == other.activity &&
          confidence == other.confidence;

  @override
  int get hashCode => activity.hashCode ^ confidence.hashCode;
}
