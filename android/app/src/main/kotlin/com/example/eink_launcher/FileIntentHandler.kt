package com.example.eink_launcher

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FileIntentHandler(context: Context, messenger: BinaryMessenger) {
    private val methodChannel = MethodChannel(
        messenger,
        "eink_launcher/file_intent",
    )
    private val eventChannel = EventChannel(
        messenger,
        "eink_launcher/file_intent_events",
    )
    private val context = context

    init {
        methodChannel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                val initialFile = getFileFromIntentUri()
                if (initialFile != null) {
                    result.success(initialFile)
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                dartFileChannel = events
            }

            override fun onCancel(arguments: Any?) {
                dartFileChannel = null
            }
        })
    }

    private fun getFileFromIntentUri(): Map<String, String>? {
        val intent = (context as? android.app.Activity)?.intent ?: return null
        return when {
            intent.action == Intent.ACTION_VIEW && intent.data != null -> {
                val uri = intent.data!!
                val path = getPathFromUri(context, uri)
                if (path != null) {
                    mapOf(
                        "path" to path,
                        "mimeType" to getMimeTypeFromUri(context, uri)
                    )
                } else null
            }
            else -> null
        }
    }

    companion object {
        private var dartFileChannel: EventChannel.EventSink? = null

        fun sendFilePathToDart(path: String) {
            dartFileChannel?.success(mapOf("path" to path))
        }

        fun getPathFromUri(context: Context, uri: Uri): String? {
            return when {
                // Handle content:// URIs
                uri.scheme == "content" -> {
                    when {
                        isDocumentsUri(uri) -> getDocumentsPath(context, uri)
                        isMediaUri(uri) -> getMediaPath(context, uri)
                        else -> getContentPath(context, uri)
                    }
                }
                // Handle file:// URIs
                uri.scheme == "file" -> uri.path
                else -> null
            }
        }

        private fun isDocumentsUri(uri: Uri): Boolean {
            return try {
                DocumentsContract.isDocumentUri(null, uri)
            } catch (e: Exception) {
                false
            }
        }

        private fun isMediaUri(uri: Uri): Boolean {
            return uri.authority == MediaStore.AUTHORITY
        }

        private fun getDocumentsPath(context: Context, uri: Uri): String? {
            val docId = DocumentsContract.getDocumentId(uri)
            val parts = docId.split(":")
            val type = if (parts.isNotEmpty()) parts[0] else return null

            return when (type) {
                "primary" -> {
                    if (parts.size > 1) {
                        "${android.os.Environment.getExternalStorageDirectory()}/${parts[1]}"
                    } else null
                }
                "home" -> {
                    if (parts.size > 1) {
                        "${android.os.Environment.getExternalStorageDirectory()}/Documents/${parts[1]}"
                    } else null
                }
                else -> getContentPath(context, uri)
            }
        }

        private fun getMediaPath(context: Context, uri: Uri): String? {
            val projection = arrayOf(MediaStore.MediaColumns.DATA)
            return try {
                context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                    val columnIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
                    if (cursor.moveToFirst()) {
                        cursor.getString(columnIndex)
                    } else null
                }
            } catch (e: Exception) {
                e.printStackTrace()
                null
            }
        }

        private fun getContentPath(context: Context, uri: Uri): String? {
            // For other content providers, try to copy to cache
            return try {
                val inputStream = context.contentResolver.openInputStream(uri) ?: return null
                val fileName = getFileNameFromUri(context, uri) ?: "temp_file"
                val cacheFile = File(context.cacheDir, fileName)
                cacheFile.outputStream().use { output ->
                    inputStream.copyTo(output)
                }
                cacheFile.absolutePath
            } catch (e: Exception) {
                e.printStackTrace()
                null
            }
        }

        private fun getFileNameFromUri(context: Context, uri: Uri): String? {
            return when {
                uri.scheme == "content" -> {
                    try {
                        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
                        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                            val columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                            if (columnIndex >= 0 && cursor.moveToFirst()) {
                                return cursor.getString(columnIndex)
                            }
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                    null
                }
                else -> uri.lastPathSegment
            }
        }

        fun getMimeTypeFromUri(context: Context, uri: Uri): String {
            return context.contentResolver.getType(uri) ?: "application/octet-stream"
        }
    }
}
