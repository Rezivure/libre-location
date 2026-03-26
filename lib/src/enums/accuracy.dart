/// The desired accuracy level for location updates.
enum Accuracy {
  /// Highest accuracy, uses GPS. Most battery-intensive.
  high,

  /// Balanced accuracy, uses a mix of GPS and network.
  balanced,

  /// Low accuracy, primarily network-based. Battery-friendly.
  low,

  /// Passive mode — only receives locations requested by other apps.
  passive,

  /// Navigation-grade accuracy. Highest possible precision.
  navigation,
}
