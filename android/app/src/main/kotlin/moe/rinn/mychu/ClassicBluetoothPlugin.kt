package moe.rinn.mychu

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
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
    private var pending: PendingConnect? = null
    private var bondReceiver: BroadcastReceiver? = null
    private var bondTimeout: Runnable? = null

    private class Session(val id: Long, val socket: BluetoothSocket)

    private data class PendingConnect(
        val id: Long,
        val adapter: BluetoothAdapter,
        val device: BluetoothDevice,
        val result: MethodChannel.Result,
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mychu/classic_bluetooth")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        finishPending("closed")
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
                if (pending?.id == id) finishPending("closed")
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
        if (session != null || pending != null) {
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
            val device = adapter.getRemoteDevice(address)
            val bondState = device.bondState
            if (BuildConfig.DEBUG) Log.i(TAG, "connect address=$address bond=$bondState")
            when (bondState) {
                BluetoothDevice.BOND_BONDED -> connectSocket(id, adapter, device, result)
                BluetoothDevice.BOND_NONE -> beginBond(id, adapter, device, result, initiateBond = true)
                BluetoothDevice.BOND_BONDING -> beginBond(id, adapter, device, result, initiateBond = false)
                else -> result.error("pair_failed", null, null)
            }
        } catch (_: SecurityException) {
            result.error("permission", null, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connectSocket(
        id: Long,
        adapter: BluetoothAdapter,
        device: BluetoothDevice,
        result: MethodChannel.Result,
    ) {
        try {
            val socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            val current = Session(id, socket)
            session = current
            writer.execute {
                try {
                    adapter.cancelDiscovery()
                } catch (_: SecurityException) {
                    // Classic flow only requests BLUETOOTH_CONNECT on Android 12+.
                }
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
    private fun beginBond(
        id: Long,
        adapter: BluetoothAdapter,
        device: BluetoothDevice,
        result: MethodChannel.Result,
        initiateBond: Boolean,
    ) {
        pending = PendingConnect(id, adapter, device, result)
        registerBondReceiver()
        try {
            if (initiateBond && !device.createBond()) {
                if (device.bondState == BluetoothDevice.BOND_BONDED) {
                    clearPending()
                    connectSocket(id, adapter, device, result)
                } else {
                    finishPending("pair_failed")
                }
                return
            }
            if (!initiateBond) {
                when (device.bondState) {
                    BluetoothDevice.BOND_BONDED -> {
                        clearPending()
                        connectSocket(id, adapter, device, result)
                        return
                    }
                    BluetoothDevice.BOND_NONE -> {
                        finishPending("pair_failed")
                        return
                    }
                }
            }
            scheduleBondTimeout()
        } catch (_: SecurityException) {
            finishPending("permission")
        }
    }

    private fun registerBondReceiver() {
        if (bondReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                } ?: return
                val p = pending ?: return
                if (device.address != p.device.address) return
                val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                if (BuildConfig.DEBUG) Log.i(TAG, "bondChanged address=${device.address} state=$state")
                when (state) {
                    BluetoothDevice.BOND_BONDED -> {
                        clearPending()
                        connectSocket(p.id, p.adapter, device, p.result)
                    }
                    BluetoothDevice.BOND_NONE -> finishPending("pair_failed")
                }
            }
        }
        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(receiver, filter)
        }
        bondReceiver = receiver
    }

    private fun unregisterBondReceiver() {
        val receiver = bondReceiver ?: return
        bondReceiver = null
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Receiver was already unregistered.
        }
    }

    private fun scheduleBondTimeout() {
        cancelBondTimeout()
        val timeout = Runnable { finishPending("bond_timeout") }
        bondTimeout = timeout
        main.postDelayed(timeout, BOND_TIMEOUT_MS)
    }

    private fun cancelBondTimeout() {
        bondTimeout?.let { main.removeCallbacks(it) }
        bondTimeout = null
    }

    private fun clearPending() {
        pending = null
        cancelBondTimeout()
        unregisterBondReceiver()
    }

    private fun finishPending(code: String) {
        val p = pending ?: return
        clearPending()
        if (Looper.myLooper() == Looper.getMainLooper()) {
            p.result.error(code, null, null)
        } else {
            main.post { p.result.error(code, null, null) }
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
        const val TAG = "ClassicBT"
        const val BOND_TIMEOUT_MS = 60_000L
        val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }
}
