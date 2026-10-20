package moe.rinn.mychu

import io.flutter.plugin.common.BinaryMessenger
import java.lang.ref.WeakReference
import java.nio.ByteBuffer

/** Mapbox 2.28.x keeps its log messenger in a process-wide static backend.
 * Forward logs while attached without making that backend own the engine.
 */
internal class MapboxLogMessenger(messenger: BinaryMessenger) : BinaryMessenger {
    private val target = WeakReference(messenger)

    fun detach() = target.clear()

    override fun send(channel: String, message: ByteBuffer?) {
        target.get()?.send(channel, message)
    }

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        val messenger = target.get()
        if (messenger != null) messenger.send(channel, message, callback)
        else callback?.reply(null)
    }

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
        target.get()?.setMessageHandler(channel, handler)
    }
}
