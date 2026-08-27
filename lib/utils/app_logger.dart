import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'app_logger_interface.dart';

class AppLogger implements AppLoggerInterface {
  static AppLoggerInterface? _instance;
  
  /// Console-only logger, usable the moment the instance exists.
  ///
  /// Non-nullable on purpose: nothing in the app awaits [initialize], so a
  /// null-until-initialized logger would silently drop every message from
  /// every service that takes an [AppLoggerInterface]. [initialize] upgrades
  /// this to console + file output.
  Logger _logger = Logger();
  String? _logFilePath;

  /// Get the current logger instance (for dependency injection)
  static AppLoggerInterface get instance {
    _instance ??= AppLogger._internal();
    return _instance!;
  }
  
  /// Set a custom logger instance (useful for testing)
  static void setInstance(AppLoggerInterface logger) {
    _instance = logger;
  }
  
  /// Reset to default implementation
  static void resetToDefault() {
    _instance = AppLogger._internal();
  }

  AppLogger._internal();

  @override
  Future<void> initialize() async {
    _logFilePath = await _getLogFilePath();
    // Upgrades the console-only logger from the field initializer.
    _logger = Logger(
      printer: PrettyPrinter(),
      output: MultiOutput([
        ConsoleOutput(),
        FileOutput(
          file: File(_logFilePath!),
          overrideExisting: false,
          encoding: utf8,
        ),
      ]),
    );
    i('Logger initialized at: $_logFilePath');
  }

  @override
  void i(String message) {
    _logger.i(message);
    if (_logFilePath != null) {
      _checkLogFileSize(_logFilePath!);
    }
  }

  @override
  void d(String message) {
    _logger.d(message);
    if (_logFilePath != null) {
      _checkLogFileSize(_logFilePath!);
    }
  }

  @override
  void e(String message) {
    _logger.e(message);
    if (_logFilePath != null) {
      _checkLogFileSize(_logFilePath!);
    }
  }

  // Legacy static methods for backwards compatibility
  static void legacyInitialize() async {
    await instance.initialize();
  }

  static void legacyI(String message) {
    instance.i(message);
  }

  static void legacyD(String message) {
    instance.d(message);
  }

  static void legacyE(String message) {
    instance.e(message);
  }

  static Future<String> _getLogFilePath() async {
    try {
      final Directory directory = await getApplicationSupportDirectory();
      return '${directory.path}/dio_client.log';
    } catch (e) {
      return './dio_client.log';
    }
  }

  static void _checkLogFileSize(String logFilePath) {
    final File logFile = File(logFilePath);
    const int maxFileSize = 10 * 1024 * 1024; // 10 MB
    if (logFile.lengthSync() > maxFileSize) {
      _truncateLogFile(logFile);
    }
  }

  static void _truncateLogFile(File logFile) {
    final List<String> lines = logFile.readAsLinesSync();
    final int linesToRemove = lines.length ~/ 2; // Remove half of the lines
    final List<String> trimmedLines = lines.sublist(linesToRemove);
    logFile.writeAsStringSync(trimmedLines.join('\n'));
  }
}
