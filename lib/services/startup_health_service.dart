import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// The native marker is written before Flutter starts, not by this query.
class StartupHealthService {
  static final instance = StartupHealthService();
  final MethodChannel _channel;
  final bool _isAndroid;
  final Duration timeout;
  bool _healthy = false;
  bool _marking = false;
  int errorEpoch = 0;
  bool _recording = false;

  StartupHealthService({
    MethodChannel? channel,
    bool? isAndroid,
    this.timeout = const Duration(seconds: 2),
  }) : _channel =
           channel ?? const MethodChannel('eink_launcher/startup_health'),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  Future<bool> shouldRecover() async {
    if (!_isAndroid) return false;
    try {
      final response = await _channel
          .invokeMethod<bool>('shouldRecover')
          .timeout(timeout);
      return response ?? true;
    } catch (_) {
      // A missing/broken Android bridge must not trap the user at startup.
      return true;
    }
  }

  Future<void> markHealthy() async {
    if (!_isAndroid || _healthy || _marking) return;
    _marking = true;
    try {
      await _channel.invokeMethod<void>('markHealthy').timeout(timeout);
      _healthy = true;
    } catch (_) {
      // Diagnostics are best effort; never break a usable launcher.
    } finally {
      _marking = false;
    }
  }

  void recordError(Object error, StackTrace stack) {
    errorEpoch++;
    if (!_isAndroid || _recording) return;
    _recording = true;
    unawaited(_record('$error\n$stack'));
  }

  Future<void> _record(String details) async {
    try {
      await _channel
          .invokeMethod<void>('recordError', {
            'details': details.length > 8192
                ? details.substring(0, 8192)
                : details,
          })
          .timeout(timeout);
    } catch (_) {
      // In particular, do not recursively report a failed diagnostics channel.
    } finally {
      _recording = false;
    }
  }
}
