/// Log verbosity level for the location plugin.
enum LogLevel {
  /// No logging.
  off,

  /// Errors only.
  error,

  /// Warnings and errors.
  warning,

  /// Informational messages, warnings, and errors.
  info,

  /// Debug-level logging (verbose).
  debug,

  /// Full verbose trace logging.
  verbose,
}
