/// The type of location authorization to request.
enum LocationAuthorizationRequest {
  /// Request "always" (background) location permission.
  always,

  /// Request "when in use" (foreground-only) location permission.
  whenInUse,
}
