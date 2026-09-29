package moe.rinn.mychu.desktopwidgets

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.time.Instant

internal class WidgetSnapshotStore(context: Context) {
    private val snapshotFile = File(context.filesDir, SNAPSHOT_FILE_NAME)
    private val atomicFile = AtomicFile(snapshotFile)

    fun writeSnapshot(source: String) {
        if (source.toByteArray(StandardCharsets.UTF_8).size > MAX_SNAPSHOT_BYTES) {
            throw IllegalArgumentException("Desktop widget snapshot is too large")
        }
        TodayScheduleSnapshotParser.parseForNow(source)

        var stream: FileOutputStream? = null
        try {
            stream = atomicFile.startWrite()
            stream.write(source.toByteArray(StandardCharsets.UTF_8))
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            if (stream != null) atomicFile.failWrite(stream)
            throw error
        }
    }

    fun readToday(now: Instant = Instant.now()): TodayScheduleWidgetData {
        val today = TodayScheduleSnapshotParser.businessDate(now)
        if (!snapshotFile.exists() || snapshotFile.length() > MAX_SNAPSHOT_BYTES) {
            return TodayScheduleWidgetData(today, TodayScheduleStatus.UNAVAILABLE)
        }
        return try {
            atomicFile.openRead().bufferedReader(StandardCharsets.UTF_8).use {
                TodayScheduleSnapshotParser.parseForNow(it.readText(), now)
            }
        } catch (_: Exception) {
            TodayScheduleWidgetData(today, TodayScheduleStatus.UNAVAILABLE)
        }
    }

    private companion object {
        const val SNAPSHOT_FILE_NAME = "desktop_widget_snapshot_v1.json"
        const val MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024
    }
}
