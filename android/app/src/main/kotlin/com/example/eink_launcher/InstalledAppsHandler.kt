package com.example.eink_launcher

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class InstalledAppsHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "eink_launcher/apps")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLaunchableApps" -> {
                    val includeSystemApps =
                        call.argument<Boolean>("includeSystemApps") ?: false
                    result.success(getLaunchableApps(includeSystemApps))
                }
                "launchApp" -> launchApp(call.argument<String>("packageName"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getLaunchableApps(includeSystemApps: Boolean): List<Map<String, Any>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.packageManager.queryIntentActivities(
                launcherIntent,
                PackageManager.ResolveInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            activity.packageManager.queryIntentActivities(launcherIntent, 0)
        }

        return activities
            .asSequence()
            .map { resolved ->
                val applicationInfo = resolved.activityInfo.applicationInfo
                val isSystemApp =
                    applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM != 0 ||
                        applicationInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
                Triple(resolved, applicationInfo.packageName, isSystemApp)
            }
            .filter { (_, _, isSystemApp) -> includeSystemApps || !isSystemApp }
            .distinctBy { (_, packageName, _) -> packageName }
            .map { (resolved, packageName, isSystemApp) ->
                mapOf(
                    "name" to resolved.loadLabel(activity.packageManager).toString(),
                    "packageName" to packageName,
                    "isSystemApp" to isSystemApp,
                )
            }
            .toList()
    }

    private fun launchApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrBlank()) {
            result.error("invalid_package", "No package name was provided.", null)
            return
        }
        val launchIntent = activity.packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            result.error("not_launchable", "The app cannot be launched.", null)
            return
        }
        try {
            activity.startActivity(launchIntent)
            result.success(null)
        } catch (error: Exception) {
            result.error("launch_failed", error.message, null)
        }
    }
}
