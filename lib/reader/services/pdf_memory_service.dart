import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Lazily queries Android's normal per-app heap class, once per process.
///
/// This is a sizing hint, not available RAM or a limit on PDFium/GPU memory:
/// https://developer.android.com/reference/android/app/ActivityManager#getMemoryClass()
/// The provisional 25% policy (4–128 MiB, 32 MiB fallback) needs Bigme profiling.
class PdfMemoryService {
  static final instance = PdfMemoryService();

  static const minCacheBytes = 4 * 1024 * 1024;
  static const maxCacheBytes = 128 * 1024 * 1024;
  static const fallbackCacheBytes = 32 * 1024 * 1024;

  final MethodChannel _channel;
  final bool _isAndroid;
  final Duration queryTimeout;
  Future<int>? _budget;

  PdfMemoryService({
    MethodChannel? channel,
    bool? isAndroid,
    this.queryTimeout = const Duration(seconds: 1),
  }) : _channel = channel ?? const MethodChannel('eink_launcher/pdf_memory'),
       _isAndroid = isAndroid ?? Platform.isAndroid;

  /// Concurrent PDF opens, retries, and resumes all share the same lookup.
  /// Constructing the service (or a session) never invokes the channel.
  Future<int> cacheBudgetBytes() {
    // No native work (or shared platform Future) is needed on host platforms.
    if (!_isAndroid) return Future.value(fallbackCacheBytes);
    return _budget ??= _loadBudget();
  }

  static int budgetForMemoryClass(Object? memoryClassMiB) {
    if (memoryClassMiB is! int || memoryClassMiB <= 0) {
      return fallbackCacheBytes;
    }
    // Clamp before multiplication to avoid overflow on malformed large reports.
    // Android's documented baseline memory class is 16 MiB (4 MiB at 25%).
    return memoryClassMiB.clamp(
          minCacheBytes * 4 ~/ (1024 * 1024),
          maxCacheBytes * 4 ~/ (1024 * 1024),
        ) *
        1024 *
        1024 ~/
        4;
  }

  Future<int> _loadBudget() async {
    try {
      final memoryClass = await _channel
          .invokeMethod<Object?>('getMemoryClass')
          .timeout(queryTimeout);
      return budgetForMemoryClass(memoryClass);
    } on MissingPluginException {
      return fallbackCacheBytes;
    } on PlatformException {
      return fallbackCacheBytes;
    } on TimeoutException {
      return fallbackCacheBytes;
    }
  }
}
