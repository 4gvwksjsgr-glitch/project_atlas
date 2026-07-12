enum LogLevel {
  debug,
  info,
  warning,
  error;

  static LogLevel fromString(String value) {
    return LogLevel.values.firstWhere(
      (level) => level.name == value.toLowerCase(),
      orElse: () => LogLevel.debug,
    );
  }

  int get priority => index;
}

/// Logger centralizzato con output su console.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  LogLevel _minLevel = LogLevel.debug;

  void initialize({required LogLevel minLevel}) {
    _minLevel = minLevel;
  }

  void debug(String message, {Map<String, Object?>? context}) {
    _log(LogLevel.debug, message, context);
  }

  void info(String message, {Map<String, Object?>? context}) {
    _log(LogLevel.info, message, context);
  }

  void warning(String message, {Map<String, Object?>? context}) {
    _log(LogLevel.warning, message, context);
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    _log(LogLevel.error, message, {
      ...?context,
      'error': ?error,
      'stackTrace': ?stackTrace,
    });
  }

  void _log(LogLevel level, String message, Map<String, Object?>? context) {
    if (level.priority < _minLevel.priority) {
      return;
    }

    final buffer = StringBuffer('[${level.name.toUpperCase()}] $message');
    if (context != null && context.isNotEmpty) {
      buffer.write(' | $context');
    }

    // ignore: avoid_print
    print(buffer);
  }
}
