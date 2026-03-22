/// The type of geofence transition event.
enum GeofenceTransition {
  /// The device entered the geofence region.
  enter,

  /// The device exited the geofence region.
  exit,

  /// The device has been dwelling inside the geofence for the configured duration.
  dwell,
}
