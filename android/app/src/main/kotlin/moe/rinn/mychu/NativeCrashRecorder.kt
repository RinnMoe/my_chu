package moe.rinn.mychu

import android.content.Context
import java.time.Instant

/** Writes enabled crash reports directly to public Download/MyCHU. */
internal object NativeCrashRecorder : Thread.UncaughtExceptionHandler {
    private var context: Context? = null
    private var previous: Thread.UncaughtExceptionHandler? = null
    @Volatile private var recording = false

    fun install(applicationContext: Context) {
        if (context != null) return
        context = applicationContext.applicationContext
        previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler(this)
    }
    fun isCrashRecording(): Boolean = recording
    fun setCrashRecording(enabled: Boolean) { recording = enabled }
    override fun uncaughtException(thread: Thread, error: Throwable) {
        runCatching { record(thread, error) }.onFailure { NativeErrorLog.record(it, "NativeCrashRecorder") }
        val handler = previous
        if (handler != null) handler.uncaughtException(thread, error)
        else android.os.Process.killProcess(android.os.Process.myPid())
    }
    internal fun render(thread: Thread, error: Throwable): String =
        "${Instant.now()} [Android JVM] thread=${thread.name}\n${error.stackTraceToString()}"

    internal fun record(thread: Thread, error: Throwable,
        enabled: Boolean = recording,
        write: (String, String) -> Unit = ::writePublicReport) {
        if (!enabled) return
        write(fileName("JVM"), render(thread, error))
    }
    fun saveDartCrash(content: String) {
        if (recording) writePublicReport(fileName("Dart"), content)
    }
    private fun fileName(kind: String): String =
        "MyCHU_崩溃报告_${kind}_${System.currentTimeMillis()}_${System.nanoTime()}.log"
    private fun writePublicReport(name: String, content: String) {
        val appContext = checkNotNull(context) { "Crash recorder is not installed" }
        val saved = PublicDownloads(appContext).write(name, "text/plain") { it.write(content.toByteArray(Charsets.UTF_8)) }
        check(saved.isNotEmpty()) { "Unable to save crash report to public Downloads" }
    }
}
