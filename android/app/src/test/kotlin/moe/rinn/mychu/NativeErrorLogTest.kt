package moe.rinn.mychu

import org.junit.After
import org.junit.Before
import org.junit.Assert.*
import org.junit.Test

class NativeErrorLogTest {
    @Before fun prepare() { NativeErrorLog.clear(); NativeErrorLog.onChanged = null }
    @After fun clean() { NativeErrorLog.clear(); NativeErrorLog.onChanged = null }

    @Test fun preservesOperationOriginalCauseAndStackBeforeFlutterStarts() {
        val error = IllegalStateException("save failed", IllegalArgumentException("original cause"))
        NativeErrorLog.record(error, "save courseware.pdf")
        val entries = NativeErrorLog.takeErrors()
        assertEquals(1, entries.size)
        val text = entries.single()["content"] as String
        assertTrue(text.contains("save courseware.pdf"))
        assertTrue(text.contains("original cause"))
        assertTrue(text.contains("NativeErrorLogTest"))
        assertTrue(entries.single()["timestamp"] is Long)
        assertTrue(NativeErrorLog.takeErrors().isEmpty())
    }

    @Test fun boundsPendingErrorsAndNotifiesTheCurrentFlutterHost() {
        var notifications = 0
        NativeErrorLog.onChanged = { notifications++ }
        repeat(305) { NativeErrorLog.record(IllegalStateException("failure $it"), "host operation") }
        val entries = NativeErrorLog.takeErrors()
        assertEquals(305, notifications)
        assertEquals(300, entries.size)
        assertTrue((entries.first()["content"] as String).contains("IllegalStateException: failure 5"))
        assertTrue((entries.last()["content"] as String).contains("IllegalStateException: failure 304"))
    }

    @Test fun clearDropsOnlyPendingProcessErrors() {
        NativeErrorLog.record(IllegalStateException("old"), "old account")
        NativeErrorLog.clear()
        NativeErrorLog.record(IllegalStateException("new"), "new account")
        assertEquals(1, NativeErrorLog.takeErrors().size)
    }

    @Test fun concurrentHostCallbacksDoNotLoseEntries() {
        val threads = (0 until 8).map { index ->
            Thread { repeat(20) { NativeErrorLog.record(IllegalStateException("$index-$it"), "worker") } }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }
        val entries = NativeErrorLog.takeErrors()
        assertEquals(160, entries.size)
        assertEquals(160, entries.map { it["content"] }.toSet().size)
    }
}
