package moe.rinn.mychu

import org.junit.Assert.*
import org.junit.Test

class NativeCrashRecorderTest {
    @Test fun disabledRecorderDoesNotWrite() {
        NativeCrashRecorder.record(Thread.currentThread(), IllegalStateException("raw"), enabled = false,
            write = { _, _ -> fail("disabled recorder wrote a report") })
    }
    @Test fun processSwitchCanEnableAndDisableRecording() {
        var count = 0
        try {
            NativeCrashRecorder.setCrashRecording(true)
            assertTrue(NativeCrashRecorder.isCrashRecording())
            NativeCrashRecorder.record(Thread.currentThread(), IllegalStateException("enabled"), write = { _, _ -> count++ })
            NativeCrashRecorder.setCrashRecording(false)
            NativeCrashRecorder.record(Thread.currentThread(), IllegalStateException("disabled"), write = { _, _ -> count++ })
            assertEquals(1, count)
        } finally { NativeCrashRecorder.setCrashRecording(false) }
    }
    @Test fun originalMessagesCausesAndAllFramesArePreserved() {
        val error = IllegalStateException("original", IllegalArgumentException("cause"))
        error.stackTrace = arrayOf(StackTraceElement("external.package.Class", "load", "full-path.kt", 42))
        val text = NativeCrashRecorder.render(Thread.currentThread(), error)
        assertTrue(text.contains("original"))
        assertTrue(text.contains("cause"))
        assertTrue(text.contains("external.package.Class.load"))
    }
    @Test fun everyCrashIsWrittenWithoutPruningOrDeduplication() {
        val reports = mutableListOf<Pair<String, String>>()
        val error = IllegalStateException("repeated crash")
        repeat(5) {
            NativeCrashRecorder.record(Thread.currentThread(), error, enabled = true,
                write = { name, text -> reports.add(name to text) })
        }
        assertEquals(5, reports.size)
        assertEquals(5, reports.map { it.first }.toSet().size)
        assertTrue(reports.all { it.second.contains("repeated crash") })
    }
}
