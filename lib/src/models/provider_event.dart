/// Event emitted when the location provider state changes.
class ProviderEvent {
  final bool enabled;
  final int status;
  final bool gps;
  final bool network;

  const ProviderEvent({
    required this.enabled,
    required this.status,
    required this.gps,
    required this.network,
  });

  factory ProviderEvent.fromMap(Map<String, dynamic> map) {
    return ProviderEvent(
      enabled: map['enabled'] as bool? ?? false,
      status: (map['status'] as num?)?.toInt() ?? 0,
      gps: map['gps'] as bool? ?? false,
      network: map['network'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'status': status,
      'gps': gps,
      'network': network,
    };
  }

  @override
  String toString() =>
      'ProviderEvent(enabled: $enabled, gps: $gps, network: $network)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderEvent &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          status == other.status &&
          gps == other.gps &&
          network == other.network;

  @override
  int get hashCode =>
      enabled.hashCode ^ status.hashCode ^ gps.hashCode ^ network.hashCode;
}
