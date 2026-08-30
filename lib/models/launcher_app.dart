class LauncherApp {
  final String name;
  final String packageName;
  final bool isSystemApp;

  const LauncherApp({
    required this.name,
    required this.packageName,
    required this.isSystemApp,
  });

  factory LauncherApp.fromMap(Map<String, dynamic> map) {
    return LauncherApp(
      name: map['name'] as String,
      packageName: map['packageName'] as String,
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }
}
