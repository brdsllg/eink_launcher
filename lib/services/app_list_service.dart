import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

class AppListService {
  static List<AppInfo>? _cachedApps;
  static List<AppInfo>? _cachedAppsWithSystem;

  /// Loads launchable apps, sorted by name. Cached separately for
  /// [includeSystemApps] true/false so toggling doesn't discard the other
  /// list, and each variant only re-queries the OS when actually needed.
  static Future<List<AppInfo>> getLaunchableApps({
    bool forceRefresh = false,
    bool includeSystemApps = false,
  }) async {
    if (!forceRefresh) {
      final cached = includeSystemApps ? _cachedAppsWithSystem : _cachedApps;
      if (cached != null) return cached;
    }
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: !includeSystemApps,
      excludeNonLaunchableApps: true,
      withIcon: false,
    );
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
    return InstalledApps.startApp(packageName);
  }
}
