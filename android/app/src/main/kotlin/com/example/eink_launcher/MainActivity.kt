package com.example.eink_launcher

import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var batteryReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        InstalledAppsHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        PdfMemoryHandler(this, flutterEngine.dartExecutor.binaryMessenger)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "eink_launcher/battery_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                unregisterBatteryReceiver()
                batteryReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context, intent: Intent) {
                        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                        val percentage = if (level >= 0 && scale > 0) {
                            (level * 100 / scale).coerceIn(0, 100)
                        } else {
                            0
                        }
                        val status = intent.getIntExtra(
                            BatteryManager.EXTRA_STATUS,
                            BatteryManager.BATTERY_STATUS_UNKNOWN,
                        )
                        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                            status == BatteryManager.BATTERY_STATUS_FULL
                        events.success(
                            mapOf(
                                "level" to percentage,
                                "charging" to charging,
                            ),
                        )
                    }
                }
                val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(
                        batteryReceiver,
                        filter,
                        Context.RECEIVER_NOT_EXPORTED,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    registerReceiver(batteryReceiver, filter)
                }
            }

            override fun onCancel(arguments: Any?) {
                unregisterBatteryReceiver()
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "eink_launcher/open_with",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openWith") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path == null) {
                result.error("invalid_path", "No file path was provided.", null)
                return@setMethodCallHandler
            }

            val file = File(path)
            if (!file.isFile) {
                result.error("missing_file", "The selected file does not exist.", null)
                return@setMethodCallHandler
            }
            val mimeType = call.argument<String>("mimeType")
                ?: "application/octet-stream"

            try {
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileProvider.com.crazecoder.openfile",
                    file,
                )
                val openIntent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mimeType)
                    addCategory(Intent.CATEGORY_DEFAULT)
                    clipData = ClipData.newRawUri("selected file", uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val launchIntent = if (wouldLaunchConcreteActivity(openIntent)) {
                    Intent.createChooser(openIntent, "Open with")
                } else {
                    openIntent
                }.apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(launchIntent)
                result.success(null)
            } catch (_: ActivityNotFoundException) {
                result.error("no_app", "No app can open this file.", null)
            } catch (error: Exception) {
                result.error("open_failed", error.message, null)
            }
        }
    }

    /**
     * True when Android resolved the intent to an actual handler rather than
     * its resolver UI. In that case Open with must force a chooser to avoid
     * immediately launching the default app.
     */
    private fun wouldLaunchConcreteActivity(intent: Intent): Boolean {
        @Suppress("DEPRECATION")
        val resolved = packageManager.resolveActivity(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        ) ?: return false
        @Suppress("DEPRECATION")
        val candidates = packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )
        val resolvedActivity = resolved.activityInfo ?: return false
        return candidates.any { candidate ->
            val activity = candidate.activityInfo
            activity.packageName == resolvedActivity.packageName &&
                activity.name == resolvedActivity.name
        }
    }

    private fun unregisterBatteryReceiver() {
        batteryReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // It may already be detached during an engine restart.
            }
        }
        batteryReceiver = null
    }

    override fun onDestroy() {
        unregisterBatteryReceiver()
        super.onDestroy()
    }
}
