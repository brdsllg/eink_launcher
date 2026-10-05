// Pure-Dart fallback for laptop-side tooling (`dart run`) where the Flutter
// engine (dart:ui) and path_provider are unavailable. Never used on device:
// wherever dart:ui exists, app_cache_directory.dart selects the Flutter
// implementation instead.
import 'dart:io';

Future<Directory> getAppCacheDirectory() async {
  final env = Platform.environment;
  final home = env['HOME'];
  final base = env['XDG_CACHE_HOME']?.isNotEmpty == true
      ? env['XDG_CACHE_HOME']!
      : home != null && home.isNotEmpty
          ? '$home/.cache'
          : Directory.systemTemp.path;
  return Directory('$base/eink_launcher');
}
