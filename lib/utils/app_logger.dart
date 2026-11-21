import 'package:flutter/foundation.dart';

enum LogLevel { info, success, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  final ValueNotifier<List<LogEntry>> logs = ValueNotifier<List<LogEntry>>(
    const [],
  );

  void info(String message) => _add(LogLevel.info, message);
  void success(String message) => _add(LogLevel.success, message);
  void error(String message) => _add(LogLevel.error, message);

  void _add(LogLevel level, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );
    final updated = [entry, ...logs.value];
    logs.value = updated.length > 100 ? updated.take(100).toList() : updated;
  }
}
