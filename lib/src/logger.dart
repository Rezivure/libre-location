import 'dart:collection';

import 'enums/log_level.dart';

/// Structured logging system for the libre_location plugin.
///
/// All Dart-side logging goes through this class instead of `print()`.
/// Log entries are stored in a ring buffer for retrieval via [getLog].
class LibreLocationLogger {
  LibreLocationLogger._();

  static LogLevel _level = LogLevel.off;
  static final int _maxEntries = 500;
  static final Queue<LogEntry> _entries = Queue<LogEntry>();

  /// Sets the current log level. Messages below this level are discarded.
  static set logLevel(LogLevel level) => _level = level;

  /// Returns the current log level.
  static LogLevel get logLevel => _level;

  static void verbose(String message) => _log(LogLevel.verbose, message);
  static void debug(String message) => _log(LogLevel.debug, message);
  static void info(String message) => _log(LogLevel.info, message);
  static void warning(String message) => _log(LogLevel.warning, message);
  static void error(String message) => _log(LogLevel.error, message);

  static void _log(LogLevel level, String message) {
    if (_level == LogLevel.off) return;
    // LogLevel enum order: off(0), error(1), warning(2), info(3), debug(4), verbose(5)
    // A message is logged if its level index <= current level index
    if (level.index > _level.index) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
  }

  /// Returns recent log entries as a list of maps.
  static List<Map<String, dynamic>> getLog() {
    return _entries.map((e) => e.toMap()).toList();
  }

  /// Clears all stored log entries.
  static void clearLog() => _entries.clear();
}

/// A single log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'message': message,
      };
}
