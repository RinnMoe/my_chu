package moe.rinn.mychu

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

internal class ClassicBluetoothPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    // A blocking read must never hold up a write. Closing the socket interrupts both.
    private val reader = Executors.newSingleThreadExecutor()
    private val writer = Executors.newSingleThreadExecutor()
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var session: Session? = null

    private class Session(val id: Long, val socket: BluetoothSocket)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mychu/classic_bluetooth")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        closeSession()
        reader.shutdown()
        writer.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("session")?.toLong()
        if (id == null) {
            result.error("invalid_session", null, null)
            return
        }
        val current = session?.takeIf { it.id == id }
        when (call.method) {
            "connect" -> connect(id, call.argument<String>("address"), result)
            "close" -> {
                if (current != null) closeSession()
                result.success(null)
            }
            "read" -> if (current == null) {
                result.error("closed", null, null)
            } else {
                reader.execute {
                    operate(current, result, "disconnected") {
                        val buffer = ByteArray(1024)
                        val count = current.socket.inputStream.read(buffer)
                        if (count < 0) throw IOException("End of RFCOMM stream")
                        buffer.copyOf(count)
                    }
                }
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (current == null || bytes == null) {
                    result.error("closed", null, null)
                } else {
                    writer.execute {
                        operate(current, result, "write_failed") {
                            current.socket.outputStream.write(bytes)
                            null
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // Missing or revoked BLUETOOTH_CONNECT is reported through the channel.
    @SuppressLint("MissingPermission")
    private fun connect(id: Long, address: String?, result: MethodChannel.Result) {
        if (session != null) {
            result.error("busy", null, null)
            return
        }
        if (address == null || !BluetoothAdapter.checkBluetoothAddress(address)) {
            result.error("invalid_address", null, null)
            return
        }
        try {
            val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter
            if (adapter == null) {
                result.error("unsupported", null, null)
                return
            }
            if (!adapter.isEnabled) {
                result.error("disabled", null, null)
                return
            }
            val socket = adapter.getRemoteDevice(address).createRfcommSocketToServiceRecord(SPP_UUID)
            val current = Session(id, socket)
            session = current
            writer.execute {
                operate(current, result, "connect_failed") {
                    socket.connect()
                    null
                }
            }
        } catch (_: SecurityException) {
            result.error("permission", null, null)
        } catch (_: IOException) {
            result.error("connect_failed", null, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun operate(
        current: Session,
        result: MethodChannel.Result,
        failureCode: String,
        operation: () -> Any?,
    ) {
        try {
            val value = operation()
            main.post {
                if (session === current) result.success(value)
                else result.error("closed", null, null)
            }
        } catch (_: SecurityException) {
            fail(current, result, "permission")
        } catch (_: IOException) {
            fail(current, result, failureCode)
        }
    }

    private fun fail(current: Session, result: MethodChannel.Result, code: String) {
        main.post {
            if (session === current) {
                closeSession()
                result.error(code, null, null)
            } else {
                result.error("closed", null, null)
            }
        }
    }

    private fun closeSession() {
        val current = session ?: return
        session = null
        try {
            current.socket.close()
        } catch (_: IOException) {
            // The session is already retired.
        }
    }

    private companion object {
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
