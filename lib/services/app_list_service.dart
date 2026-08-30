import 'package:flutter/services.dart';

import '../models/launcher_app.dart';

class AppListService {
  static const MethodChannel _channel = MethodChannel('eink_launcher/apps');

  static List<LauncherApp>? _cachedApps;
  static List<LauncherApp>? _cachedAppsWithSystem;

  /// Loads launchable apps, sorted by name. Cached separately for
  /// [includeSystemApps] true/false so toggling doesn't discard the other
  /// list, and each variant only re-queries the OS when actually needed.
  static Future<List<LauncherApp>> getLaunchableApps({
    bool forceRefresh = false,
    bool includeSystemApps = false,
  }) async {
    if (!forceRefresh) {
      final cached = includeSystemApps ? _cachedAppsWithSystem : _cachedApps;
      if (cached != null) return cached;
    }
    final rawApps =
        await _channel.invokeMethod<List<dynamic>>('getLaunchableApps', {
          'includeSystemApps': includeSystemApps,
        }) ??
        const [];
    final apps = rawApps
        .map(
          (value) => LauncherApp.fromMap(
            Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
          ),
        )
        .toList();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (includeSystemApps) {
      _cachedAppsWithSystem = apps;
    } else {
      _cachedApps = apps;
    }
    return apps;
  }

  static void invalidateCache() {
    _cachedApps = null;
    _cachedAppsWithSystem = null;
  }

  static Future<void> launch(String packageName) {
    return _channel.invokeMethod<void>('launchApp', {
      'packageName': packageName,
    });
  }
}
