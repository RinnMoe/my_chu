package moe.rinn.mychu

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object VivoSuperXDemoChannel {
    const val CHANNEL = "mychu/vivo_superx_demo"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "post" -> post(call, context, result)
                    "cancel" -> {
                        VivoSuperXDemoNotifier.cancel(context)
                        result.success(null)
                    }
                    "status" -> result.success(VivoSuperXDemoNotifier.status(context))
                    else -> result.notImplemented()
                }
            }
    }

    private fun post(
        call: MethodCall,
        context: Context,
        result: MethodChannel.Result,
    ) {
        val raw = call.argument<String>("payload")
        if (raw.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "payload is required", null)
            return
        }
        val payload = try {
            VivoSuperXDemoPayload.fromJson(JSONObject(raw))
        } catch (_: Throwable) {
            result.error("INVALID_PAYLOAD", "Vivo SuperX payload is invalid", null)
            return
        }
        try {
            VivoSuperXDemoNotifier.post(context, payload)
            result.success(null)
        } catch (error: SecurityException) {
            result.error("PERMISSION_DENIED", error.message, null)
        } catch (_: Throwable) {
            result.error("POST_FAILED", "Vivo SuperX notification failed", null)
        }
    }
}
