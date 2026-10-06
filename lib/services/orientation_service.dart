import 'package:flutter/services.dart';

/// Single place for screen rotation requests.
///
/// The file browser and the reader both locked orientation directly, so a
/// push/pop could fire duplicate or fighting platform calls. This wrapper
/// keeps the last request and skips repeats — same visible behavior, fewer
/// native calls and no flicker.
class OrientationService {
  static ScreenLock _last = ScreenLock.free;
  static bool _applied = false;

  static ScreenLock get current => _last;

  static Future<void> lockPortrait() => _apply(
        ScreenLock.portrait,
        const [DeviceOrientation.portraitUp],
      );

  static Future<void> lockLandscape() => _apply(
        ScreenLock.landscape,
        const [DeviceOrientation.landscapeLeft],
      );

  static Future<void> unlock() => _apply(ScreenLock.free, const []);

  static Future<void> applyLandscape(bool landscape) =>
      landscape ? lockLandscape() : lockPortrait();

  static Future<void> _apply(
    ScreenLock lock,
    List<DeviceOrientation> orientations,
  ) {
    if (_applied && _last == lock) return Future.value();
    _last = lock;
    _applied = true;
    return SystemChrome.setPreferredOrientations(orientations);
  }

  /// Tests only.
  static void resetForTesting() {
    _last = ScreenLock.free;
    _applied = false;
  }
}

enum ScreenLock { portrait, landscape, free }
