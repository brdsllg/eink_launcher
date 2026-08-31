package com.example.eink_launcher

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Separate preferences from Flutter's user settings; two bounded local errors. */
internal object StartupHealthHandler {
    private const val PREFS = "launcher_startup_health"
    private var started = false
    private var recovery = false

    @Synchronized
    fun beginLaunch(context: Context) {
        // Activity/engine recreation within a process is not a failed launch.
        if (started) return
        started = true
        recovery = try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val state = StartupHealthPolicy(
                prefs.getBoolean("pending", false),
                prefs.getInt("failures", 0),
                prefs.getLong("window_start", 0),
            ).nextLaunch(System.currentTimeMillis())
            // This tiny marker must reach disk before engine initialization.
            val saved = prefs.edit()
                .putBoolean("pending", true)
                .putInt("failures", state.failures)
                .putLong("window_start", state.windowStartMillis)
                .commit()
            state.shouldRecover || !saved
        } catch (_: Exception) {
            true
        }
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "eink_launcher/startup_health")
            .setMethodCallHandler { call, result ->
                try {
                    val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    when (call.method) {
                        "shouldRecover" -> result.success(recovery)
                        "markHealthy" -> {
                            if (!prefs.edit().putBoolean("pending", false)
                                    .putInt("failures", 0).commit()) {
                                result.error("health_write", "Could not save startup health.", null)
                            } else {
                                recovery = false
                                result.success(null)
                            }
                        }
                        "recordError" -> {
                            val details = call.argument<String>("details").orEmpty().take(8192)
                            prefs.edit()
                                .putString("previous_error", prefs.getString("last_error", null)?.take(8192))
                                .putString("last_error", "${System.currentTimeMillis()}\n$details".take(8192))
                                .apply()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("health_unavailable", "Startup health is unavailable.", null)
                }
            }
    }
}
