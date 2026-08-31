package com.example.eink_launcher

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Registers at startup, but does no memory query until the first PDF opens. */
class PdfMemoryHandler(context: Context, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "eink_launcher/pdf_memory").setMethodCallHandler { call, result ->
            if (call.method != "getMemoryClass") {
                result.notImplemented()
            } else {
                try {
                    val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    val memoryClass = manager?.memoryClass
                    if (memoryClass == null || memoryClass <= 0) {
                        result.error("memory_unavailable", "Memory class is unavailable.", null)
                    } else {
                        // Normal per-app heap class in MiB, not total/free RAM or largeHeap.
                        result.success(memoryClass)
                    }
                } catch (_: Exception) {
                    result.error("memory_unavailable", "Memory class is unavailable.", null)
                }
            }
        }
    }
}
