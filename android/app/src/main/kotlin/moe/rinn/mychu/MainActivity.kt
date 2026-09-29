package moe.rinn.mychu

import android.content.ContentValues
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import moe.rinn.mychu.desktopwidgets.DesktopWidgetRefreshReceiver
import moe.rinn.mychu.desktopwidgets.WidgetSnapshotStore

class MainActivity : FlutterActivity() {
    private val CHANNEL = "mychu/cookie"
    private val FILE_CHANNEL = "mychu/file_save"
    private val APP_INSTALLER_CHANNEL = "mychu/app_installer"
    private val EXTERNAL_APP_LAUNCHER_CHANNEL = "mychu/external_app_launcher"
    private val APP_LAUNCH_CHANNEL = "mychu/app_launch"
    private val DESKTOP_WIDGET_CHANNEL = "mychu/desktop_widgets"
    private var appLaunchChannel: MethodChannel? = null
    private var pendingTargetAppId: String? = null
    private var pendingWidgetLaunchRequest: String? = null
    private var temporalChangeChannel: TemporalChangeChannel? = null
    private val desktopWidgetScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val desktopWidgetUpdateMutex = Mutex()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        LiveUpdateChannel.register(
            context = this,
            flutterEngine = flutterEngine,
        )
        VivoSuperXDemoChannel.register(
            context = this,
            flutterEngine = flutterEngine,
        )
        PlatformCompatibilityChannel.register(this, flutterEngine)
        AndroidDeviceCompatibilityChannel.register(this, flutterEngine)
        ScheduledAlertChannel.register(this, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DESKTOP_WIDGET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "publishSnapshot") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val snapshot = call.argument<String>("snapshot")
            if (snapshot.isNullOrBlank()) {
                result.error("INVALID_SNAPSHOT", "桌面课表快照无效", null)
                return@setMethodCallHandler
            }
            desktopWidgetScope.launch {
                try {
                    desktopWidgetUpdateMutex.withLock {
                        WidgetSnapshotStore(applicationContext).writeSnapshot(snapshot)
                        applicationContext.sendBroadcast(
                            Intent(
                                applicationContext,
                                DesktopWidgetRefreshReceiver::class.java,
                            ).setAction(DesktopWidgetRefreshReceiver.ACTION_REFRESH),
                        )
                    }
                    withContext(Dispatchers.Main.immediate) {
                        result.success(null)
                    }
                } catch (_: Exception) {
                    withContext(Dispatchers.Main.immediate) {
                        result.error("WIDGET_UPDATE_FAILED", "桌面课表更新失败", null)
                    }
                }
            }
        }
        temporalChangeChannel?.dispose()
        temporalChangeChannel = TemporalChangeChannel(this, flutterEngine)
        appLaunchChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LAUNCH_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consume") {
                    val widgetRequest = pendingWidgetLaunchRequest
                    pendingWidgetLaunchRequest = null
                    if (widgetRequest != null) {
                        result.success(
                            mapOf("source" to "desktopWidget", "request" to widgetRequest),
                        )
                    } else {
                        val pending = pendingTargetAppId
                        pendingTargetAppId = null
                        result.success(pending)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
        handleLaunchIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getCookies") {
                val url = call.argument<String>("url")
                if (url != null) {
                    val cookies = CookieManager.getInstance().getCookie(url)
                    result.success(cookies)
                } else {
                    result.error("INVALID_ARG", "url is required", null)
                }
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveToDownloads") {
                val fileName = call.argument<String>("fileName")
                val sourcePath = call.argument<String>("sourcePath")
                if (fileName.isNullOrBlank() || sourcePath.isNullOrBlank()) {
                    result.error("INVALID_ARG", "fileName and sourcePath are required", null)
                    return@setMethodCallHandler
                }
                val saved = saveToDownloads(fileName, File(sourcePath))
                if (saved != null) {
                    result.success(saved)
                } else {
                    result.error("SAVE_FAILED", "无法保存到系统下载目录", null)
                }
            } else if (call.method == "openFile") {
                val path = call.argument<String>("path")
                val fileName = call.argument<String>("fileName")
                if (path.isNullOrBlank() || fileName.isNullOrBlank()) {
                    result.error("INVALID_ARG", "path and fileName are required", null)
                    return@setMethodCallHandler
                }
                result.success(openFileExternally(path, fileName))
            } else if (call.method == "shareFile") {
                val path = call.argument<String>("path")
                val fileName = call.argument<String>("fileName")
                if (path.isNullOrBlank() || fileName.isNullOrBlank()) {
                    result.error("INVALID_ARG", "path and fileName are required", null)
                    return@setMethodCallHandler
                }
                result.success(shareFileExternally(path, fileName))
            } else if (call.method == "openInWakeUp") {
                val path = call.argument<String>("path")
                val fileName = call.argument<String>("fileName")
                if (path.isNullOrBlank() ||
                    fileName.isNullOrBlank() ||
                    !fileName.endsWith(".wakeup_schedule", ignoreCase = true)
                ) {
                    result.error("INVALID_ARG", "A saved WakeUp schedule is required", null)
                    return@setMethodCallHandler
                }
                result.success(openInWakeUp(path, fileName))
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "installPackage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val fileName = call.argument<String>("fileName")
            if (path.isNullOrBlank() || fileName.isNullOrBlank() || !fileName.endsWith(".apk", ignoreCase = true)) {
                result.error("INVALID_ARG", "A saved APK is required", null)
                return@setMethodCallHandler
            }
            result.success(installPackage(path, fileName))
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_APP_LAUNCHER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "launch") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val uri = call.argument<String>("uri")
            val androidPackage = call.argument<String>("androidPackage")
            if (uri.isNullOrBlank() || androidPackage.isNullOrBlank()) {
                result.error("INVALID_ARG", "uri and androidPackage are required", null)
                return@setMethodCallHandler
            }
            try {
                startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                        setPackage(androidPackage)
                    },
                )
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.success(false)
            } catch (_: SecurityException) {
                result.success(false)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
    }

    override fun onDestroy() {
        desktopWidgetScope.cancel()
        temporalChangeChannel?.dispose()
        temporalChangeChannel = null
        super.onDestroy()
    }

    private fun handleLaunchIntent(intent: Intent?) {
        when (intent?.action) {
            ACTION_OPEN_APP -> {
                val target = intent.getStringExtra(EXTRA_TARGET_APP_ID)?.trim()
                if (!target.isNullOrEmpty()) {
                    pendingWidgetLaunchRequest = null
                    pendingTargetAppId = target
                    appLaunchChannel?.invokeMethod("openTarget", target)
                }
            }
            ACTION_OPEN_WIDGET_TARGET -> {
                val request = intent.getStringExtra(EXTRA_WIDGET_LAUNCH_REQUEST)?.trim()
                if (!request.isNullOrEmpty()) {
                    pendingTargetAppId = null
                    pendingWidgetLaunchRequest = request
                    appLaunchChannel?.invokeMethod("openWidgetTarget", request)
                }
            }
        }
    }

    /** 保存到公共下载目录 Download/MyCHU，返回可授予外部应用的 URI；失败返回 null。 */
    private fun saveToDownloads(fileName: String, source: File): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveViaMediaStore(fileName, source)
            } else {
                saveViaLegacy(fileName, source)
            }
        } catch (e: Exception) {
            null
        }
    }

    /** Shows the system chooser for a saved courseware file. */
    private fun openFileExternally(filePath: String, fileName: String): Boolean {
        val uri = resolveFileUri(filePath) ?: return false
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType(fileName))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(Intent.createChooser(intent, "选择打开方式"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** Shares a saved course schedule through Android's system chooser. */
    private fun shareFileExternally(filePath: String, fileName: String): Boolean {
        val uri = resolveFileUri(filePath) ?: return false
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType(fileName)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(Intent.createChooser(intent, "分享课表"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** Opens a saved WakeUp schedule directly in the installed WakeUp app. */
    private fun openInWakeUp(filePath: String, fileName: String): Boolean {
        return try {
            // WakeUp validates Uri.getPath() before opening the stream. A
            // MediaStore Downloads URI is exposed as /downloads/<id>, so it
            // loses the .wakeup_schedule suffix even though the display name
            // is correct. Copy the already-saved content into our
            // FileProvider area to preserve the extension in the grantable
            // URI path.
            val uri = prepareWakeUpUri(filePath, fileName) ?: return false
            val intent = Intent(Intent.ACTION_VIEW).apply {
                // WakeUp's exported backup handler is registered for the
                // generic binary MIME used by its legacy file importer.
                setDataAndType(uri, "application/octet-stream")
                setPackage(WAKE_UP_PACKAGE)
                clipData = ClipData.newRawUri(fileName, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun prepareWakeUpUri(filePath: String, fileName: String): Uri? {
        val sourceUri = resolveFileUri(filePath) ?: return null
        val safeName = File(fileName).name
        if (!safeName.endsWith(".wakeup_schedule", ignoreCase = true)) return null
        val exportDir = File(filesDir, "wakeup_exports")
        if (!exportDir.exists() && !exportDir.mkdirs()) return null
        val target = File(exportDir, safeName)
        contentResolver.openInputStream(sourceUri)?.use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: return null
        return FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            target,
        )
    }

    /** Hands a saved APK to Android's package installer. */
    private fun installPackage(filePath: String, fileName: String): Boolean {
        val uri = resolveFileUri(filePath) ?: return false
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun resolveFileUri(filePath: String): Uri? {
        if (filePath.startsWith("content://")) return Uri.parse(filePath)

        val file = File(filePath)
        if (!file.isFile) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
        } else {
            Uri.fromFile(file)
        }
    }

    private fun saveViaMediaStore(fileName: String, source: File): String {
        val displayName = uniqueMediaName(fileName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType(displayName))
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/MyCHU",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values) ?: return ""
        return try {
            contentResolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            } ?: throw IllegalStateException("无法打开下载文件输出流")
            val completed = ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            }
            contentResolver.update(uri, completed, null, null)
            // Keep the grantable URI instead of reconstructing it later from
            // a display path. This also avoids vendor-specific MediaStore
            // selection quirks when opening the file immediately after save.
            uri.toString()
        } catch (error: Exception) {
            try {
                contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
                // The original save error is more useful to the Flutter side.
            }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveViaLegacy(fileName: String, source: File): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "MyCHU",
        )
        if (!dir.exists() && !dir.mkdirs()) return ""
        val target = uniqueLegacyFile(dir, fileName)
        source.copyTo(target)
        return target.absolutePath
    }

    private fun uniqueMediaName(fileName: String): String {
        val existing = HashSet<String>()
        val projection = arrayOf(MediaStore.Downloads.DISPLAY_NAME)
        val selection = "${MediaStore.Downloads.RELATIVE_PATH} LIKE ?"
        val selectionArgs = arrayOf("${Environment.DIRECTORY_DOWNLOADS}/MyCHU%")
        contentResolver.query(
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                cursor.getString(index)?.let { existing.add(it) }
            }
        }
        return uniqueName(fileName, existing)
    }

    private fun uniqueLegacyFile(dir: File, fileName: String): File {
        val existing = dir.list()?.toSet() ?: emptySet()
        return File(dir, uniqueName(fileName, existing))
    }

    private fun uniqueName(fileName: String, existing: Set<String>): String {
        if (fileName !in existing) return fileName
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while ("$stem ($index)$ext" in existing) index++
        return "$stem ($index)$ext"
    }

    private fun mimeType(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "pdf" -> "application/pdf"
            "apk" -> "application/vnd.android.package-archive"
            "ppt", "pptx" -> "application/vnd.ms-powerpoint"
            "doc", "docx" -> "application/msword"
            "xls", "xlsx" -> "application/vnd.ms-excel"
            "zip" -> "application/zip"
            "rar" -> "application/x-rar-compressed"
            "7z" -> "application/x-7z-compressed"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "ics" -> "text/calendar"
            "txt" -> "text/plain"
            else -> "application/octet-stream"
        }
    }

    companion object {
        const val ACTION_OPEN_APP = "moe.rinn.mychu.action.OPEN_APP"
        const val EXTRA_TARGET_APP_ID = "mychu_target_app_id"
        const val ACTION_OPEN_WIDGET_TARGET = "moe.rinn.mychu.action.OPEN_WIDGET_TARGET"
        const val EXTRA_WIDGET_LAUNCH_REQUEST = "mychu_widget_launch_request"
        private const val WAKE_UP_PACKAGE = "com.suda.yzune.wakeupschedule"
    }
}
