// lib/logger.dart
import 'package:flutter/foundation.dart';

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  void log(String message, {String level = 'INFO'}) {
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      debugPrint('[$timestamp] [$level] $message');
    }
  }

  void debug(String message) => log(message, level: 'DEBUG');
  void info(String message) => log(message, level: 'INFO');
  void warning(String message) => log(message, level: 'WARNING');
  void error(String message) => log(message, level: 'ERROR');
}