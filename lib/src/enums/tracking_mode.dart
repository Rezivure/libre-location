/// The tracking mode that controls the balance between accuracy and battery usage.
enum TrackingMode {
  /// Active tracking: GPS every 30s–2min, highest accuracy.
  /// Battery impact: ~5–8%/day.
  active,

  /// Balanced tracking: Network provider every 5 min + GPS on motion detected.
  /// Battery impact: ~2–4%/day.
  balanced,

  /// Passive tracking: Significant location changes only, ~500m resolution.
  /// Battery impact: ~1%/day.
  passive,
}
