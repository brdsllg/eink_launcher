import 'package:flutter/foundation.dart';

import 'startup_health_service.dart';

/// Preserve normal Flutter diagnostics while retaining bounded local evidence.
/// https://docs.flutter.dev/testing/errors
class LauncherErrorService {
  static VoidCallback install({StartupHealthService? health}) {
    final service = health ?? StartupHealthService.instance;
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    FlutterError.onError = (details) {
      service.recordError(
        details.exception,
        details.stack ?? StackTrace.current,
      );
      (previousFlutter ?? FlutterError.presentError)(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      service.recordError(error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
    return () {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    };
  }
}
