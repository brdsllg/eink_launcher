package com.example.eink_launcher

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Parcelable
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
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
        return getFileFromIntent(context, intent)
    }

    companion object {
        private var dartFileChannel: EventChannel.EventSink? = null

        fun sendFilePathToDart(path: String) {
            dartFileChannel?.success(mapOf("path" to path))
        }

        /** Shared entry point for cold-start (getInitialFile) and warm (onNewIntent). */
        fun getFileFromIntent(context: Context, intent: Intent): Map<String, String>? {
            val uri = extractUri(context, intent) ?: return null
            val path = getPathFromUri(context, uri) ?: return null
            return mapOf(
                "path" to path,
                "mimeType" to getMimeTypeFromUri(context, uri),
            )
        }

        /** Returns the first usable content/file Uri for VIEW, SEND, or SEND_MULTIPLE. */
        fun extractUri(context: Context, intent: Intent): Uri? {
            return when (intent.action) {
                Intent.ACTION_VIEW -> {
                    // Most file managers put the file in intent.data, but some
                    // share-style VIEW intents carry it in EXTRA_STREAM instead.
                    intent.data
                        ?: intent.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) as? Uri
                        ?: firstUriFromClipData(intent)
                }
                Intent.ACTION_SEND -> {
                    intent.getParcelableExtra<Parcelable>(Intent.EXTRA_STREAM) as? Uri
                        ?: intent.data
                        ?: firstUriFromClipData(intent)
                        ?: textAsTempFile(context, intent)
                }
                Intent.ACTION_SEND_MULTIPLE -> {
                    val list = intent.getParcelableArrayListExtra<Parcelable>(
                        Intent.EXTRA_STREAM,
                    )
                    val uris = list?.filterIsInstance<Uri>()
                    // The reader is single-document: open the first shared file.
                    // Unsupported types are rejected in Dart with guidance.
                    uris?.firstOrNull()
                        ?: intent.data
                        ?: textAsTempFile(context, intent)
                }
                else -> null
            }
        }

        private fun firstUriFromClipData(intent: Intent): Uri? {
            val clip = intent.clipData ?: return null
            for (i in 0 until clip.itemCount) {
                val uri = clip.getItemAt(i)?.uri
                if (uri != null) return uri
            }
            return null
        }

        /**
         * Plain-text shares (EXTRA_TEXT with no stream) carry no file. Persist
         * them as a .txt in cache so the reader can still open them.
         */
        private fun textAsTempFile(context: Context, intent: Intent): Uri? {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                ?: intent.getStringExtra(Intent.EXTRA_TEXT)
                ?: return null
            if (text.isBlank()) return null
            return try {
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                    ?.trim()?.take(60)?.replace(Regex("[^A-Za-z0-9-_ ]"), "")?.trim()
                val name = if (subject.isNullOrBlank()) "shared-text.txt" else "$subject.txt"
                val file = File(context.cacheDir, sanitizeFileName(name))
                file.writeText(text)
                Uri.fromFile(file)
            } catch (e: Exception) {
                e.printStackTrace()
                null
            }
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
                // Handle file:// URIs (also used for our own shared-text temp files)
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
            val docId = try {
                DocumentsContract.getDocumentId(uri)
            } catch (e: Exception) {
                return getContentPath(context, uri)
            }
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
            // For other content providers, copy to cache so the reader gets a
            // plain file path. The copy keeps the original file name (and
            // therefore its extension); when the provider gives no usable name,
            // one is derived from the MIME type so the reader can detect the
            // format instead of failing on an extensionless temp file.
            return try {
                val inputStream = context.contentResolver.openInputStream(uri) ?: return null
                val mimeType = try {
                    context.contentResolver.getType(uri)
                } catch (e: Exception) {
                    null
                }
                val fileName = ensureExtension(
                    getFileNameFromUri(context, uri) ?: "shared-file",
                    mimeType,
                )
                val cacheFile = uniqueCacheFile(context, fileName)
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
            if (uri.scheme == "content") {
                // OpenableColumns works across DocumentsProviders; MediaColumns
                // only covers the media store.
                try {
                    context.contentResolver.query(
                        uri,
                        arrayOf(OpenableColumns.DISPLAY_NAME),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        val columnIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (columnIndex >= 0 && cursor.moveToFirst()) {
                            val name = cursor.getString(columnIndex)
                            if (!name.isNullOrBlank()) return sanitizeFileName(name)
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                try {
                    val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
                    context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                        val columnIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                        if (columnIndex >= 0 && cursor.moveToFirst()) {
                            val name = cursor.getString(columnIndex)
                            if (!name.isNullOrBlank()) return sanitizeFileName(name)
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            val segment = uri.lastPathSegment?.substringAfterLast('/')
            return segment?.takeIf { it.isNotBlank() }?.let(::sanitizeFileName)
        }

        private fun sanitizeFileName(name: String): String {
            var clean = name.substringAfterLast('/').substringAfterLast('\\').trim()
            if (clean.isEmpty() || clean == "." || clean == "..") return "shared-file"
            clean = clean.replace(Regex("[\u0000-\u001F<>:\"|?*]"), "_")
            return clean.take(180).ifBlank { "shared-file" }
        }

        /** Appends a reader-known extension when the shared name has none. */
        private fun ensureExtension(fileName: String, mimeType: String?): String {
            val dot = fileName.lastIndexOf('.')
            if (dot > 0 && dot < fileName.length - 1) return fileName
            return fileName + extensionForMimeType(mimeType)
        }

        private fun extensionForMimeType(mimeType: String?): String {
            return when (mimeType?.lowercase()?.substringBefore(';')?.trim()) {
                "application/pdf" -> ".pdf"
                "application/epub+zip" -> ".epub"
                "text/markdown", "text/x-markdown" -> ".md"
                "text/plain", "text/csv", "text/tab-separated-values" -> ".txt"
                else -> if (mimeType?.startsWith("text/", ignoreCase = true) == true) ".txt" else ".pdf"
            }
        }

        /** Avoids overwriting a previous share that used the same file name. */
        private fun uniqueCacheFile(context: Context, fileName: String): File {
            var file = File(context.cacheDir, fileName)
            if (!file.exists()) return file
            val dot = fileName.lastIndexOf('.')
            val stem = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var n = 1
            while (file.exists() && n < 1000) {
                file = File(context.cacheDir, "$stem-$n$ext")
                n++
            }
            return file
        }

        fun getMimeTypeFromUri(context: Context, uri: Uri): String {
            return context.contentResolver.getType(uri) ?: "application/octet-stream"
        }
    }
}
