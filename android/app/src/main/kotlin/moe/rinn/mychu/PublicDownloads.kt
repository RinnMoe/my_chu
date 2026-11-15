package moe.rinn.mychu

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.OutputStream

internal class PublicDownloads(context: Context) {
    private val contentResolver = context.applicationContext.contentResolver
    fun write(fileName: String, mime: String, write: (OutputStream) -> Unit): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) saveViaMediaStore(fileName, mime, write)
        else saveViaLegacy(fileName, write)

    private fun saveViaMediaStore(fileName: String, mime: String, write: (java.io.OutputStream) -> Unit): String {
        val displayName = uniqueMediaName(fileName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, displayName)
            put(MediaStore.Downloads.MIME_TYPE, mime)
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
                write(out)
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
            NativeErrorLog.record(error, "PublicDownloads")
            try {
                contentResolver.delete(uri, null, null)
            } catch (diagnosticError: Exception) {
                NativeErrorLog.record(diagnosticError, "PublicDownloads")
                // The original save error is more useful to the Flutter side.
            }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveViaLegacy(fileName: String, write: (java.io.OutputStream) -> Unit): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "MyCHU",
        )
        if (!dir.exists() && !dir.mkdirs()) return ""
        val target = uniqueLegacyFile(dir, fileName)
        try {
            target.outputStream().use(write)
        } catch (error: Exception) {
            NativeErrorLog.record(error, "PublicDownloads")
            runCatching { target.delete() }.onFailure { NativeErrorLog.record(it, "PublicDownloads") }
            throw error
        }
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

}
