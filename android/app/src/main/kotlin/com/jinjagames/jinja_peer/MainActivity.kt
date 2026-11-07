package com.jinjagames.jinja_peer

import android.Manifest
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * Native helpers for JinjaPeer on Android:
 *  - saveToDownloads: publish a received file to the public Downloads/JinjaPeer
 *    folder (MediaStore, no storage permission needed on Android 10+)
 *  - open / share / openDownloads: hand a file to other apps safely
 *  - startTransfer / updateTransfer / stopTransfer: foreground service that
 *    keeps transfers running while the screen is off or the app is in the
 *    background
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jinjapeer/android")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "saveToDownloads" -> {
                            val path = call.argument<String>("path")!!
                            val name = call.argument<String>("name")!!
                            val relDir = call.argument<String>("relDir") ?: ""
                            io.execute {
                                val out = try {
                                    saveToDownloads(File(path), name, relDir)
                                } catch (e: Exception) {
                                    null
                                }
                                main.post { result.success(out) }
                            }
                        }
                        "open" -> result.success(open(call.argument<String>("target")!!))
                        "share" -> result.success(share(call.argument<String>("target")!!))
                        "openDownloads" -> result.success(startSafely(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)))
                        "exists" -> result.success(exists(call.argument<String>("target")!!))
                        "startTransfer", "updateTransfer" -> {
                            askNotificationPermission()
                            val i = Intent(this, TransferService::class.java)
                                .putExtra("text", call.argument<String>("text") ?: "Aktarım sürüyor")
                                .putExtra("progress", call.argument<Int>("progress") ?: -1)
                            ContextCompat.startForegroundService(this, i)
                            result.success(true)
                        }
                        "stopTransfer" -> {
                            stopService(Intent(this, TransferService::class.java))
                            result.success(true)
                        }
                        "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("android", e.message, null)
                }
            }
    }

    private fun mimeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    /** Returns {uri, path} of the published file, or null if it stays private. */
    private fun saveToDownloads(src: File, name: String, relDir: String): Map<String, String>? {
        val sub = if (relDir.isBlank()) "JinjaPeer" else "JinjaPeer/$relDir"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mimeOf(name))
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$sub")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
            try {
                resolver.openOutputStream(uri)!!.use { out ->
                    FileInputStream(src).use { it.copyTo(out, 256 * 1024) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            var shown = "${Environment.DIRECTORY_DOWNLOADS}/$sub/$name"
            resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) shown = "${Environment.DIRECTORY_DOWNLOADS}/$sub/${it.getString(0)}"
            }
            src.delete()
            return mapOf("uri" to uri.toString(), "path" to shown)
        }
        // Android 9 and older: plain file in the public folder (needs permission).
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 41)
            return null
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), sub)
        dir.mkdirs()
        var target = File(dir, name)
        var n = 1
        while (target.exists()) {
            target = File(dir, "${name.substringBeforeLast('.', name)} ($n)" +
                    (if (name.contains('.')) ".${name.substringAfterLast('.')}" else ""))
            n++
        }
        src.copyTo(target)
        src.delete()
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), null, null)
        return mapOf("uri" to Uri.fromFile(target).toString(), "path" to target.absolutePath)
    }

    private fun uriFor(target: String): Uri =
        if (target.startsWith("content://")) Uri.parse(target)
        else FileProvider.getUriForFile(this, "$packageName.files", File(target.removePrefix("file://")))

    private fun exists(target: String): Boolean = try {
        if (target.startsWith("content://")) {
            contentResolver.openFileDescriptor(Uri.parse(target), "r")?.use { true } ?: false
        } else File(target.removePrefix("file://")).exists()
    } catch (e: Exception) {
        false
    }

    private fun open(target: String): Boolean {
        val uri = uriFor(target)
        val mime = contentResolver.getType(uri) ?: mimeOf(target)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return startSafely(Intent.createChooser(i, "Şununla aç").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun share(target: String): Boolean {
        val uri = uriFor(target)
        val mime = contentResolver.getType(uri) ?: mimeOf(target)
        val i = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return startSafely(Intent.createChooser(i, "Paylaş").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun startSafely(i: Intent): Boolean = try {
        startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private var askedNotifications = false

    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && !askedNotifications &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            askedNotifications = true
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
        }
    }
}
