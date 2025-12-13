import 'package:flutter/foundation.dart';

class Logger {
  static bool enabled = true; // toggle to silence logs
  static bool debugEnabled = true; // verbose debug

  static void info(String tag, String msg) {
    if (!enabled) return;
    debugPrint('INFO: [$tag] $msg');
  }

  static void debug(String tag, String msg) {
    if (!enabled || !debugEnabled) return;
    debugPrint('DBG:  [$tag] $msg');
  }

  static void error(String tag, String msg) {
    if (!enabled) return;
    debugPrint('ERR:  [$tag] $msg');
  }
}
