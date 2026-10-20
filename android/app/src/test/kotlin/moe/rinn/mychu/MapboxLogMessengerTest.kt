package moe.rinn.mychu

import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MapboxLogMessengerTest {
    private class Messenger : BinaryMessenger {
        var sends = 0
        override fun send(channel: String, message: ByteBuffer?) { sends++ }
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            sends++
            callback?.reply(message)
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }

    @Test
    fun forwardsWhileAttachedAndCompletesCallbacksAfterDetach() {
        val engineMessenger = Messenger()
        val logMessenger = MapboxLogMessenger(engineMessenger)
        logMessenger.send("logs", null)
        var replies = 0
        logMessenger.send("logs", null) { replies++ }
        assertEquals(2, engineMessenger.sends)
        assertEquals(1, replies)
        logMessenger.detach()
        logMessenger.send("logs", null)
        logMessenger.send("logs", null) { response ->
            assertTrue(response == null)
            replies++
        }
        assertEquals(2, engineMessenger.sends)
        assertEquals(2, replies)
    }
}
