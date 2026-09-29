package moe.rinn.mychu

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

object ScheduledAlertChannel {
    private const val CHANNEL = "mychu/scheduled_alerts"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "replace" -> replace(call, context, result)
                    "clearProvider" -> {
                        val account = call.argument<String>("accountKey").orEmpty()
                        val provider = call.argument<String>("providerId").orEmpty()
                        ScheduledAlertScheduler.cancelProvider(context, account, provider)
                        result.success(null)
                    }
                    "clearAll" -> {
                        ScheduledAlertScheduler.clearAll(context)
                        result.success(null)
                    }
                    "reschedule" -> {
                        ScheduledAlertScheduler.rescheduleAll(context)
                        result.success(null)
                    }
                    "consumeReceipts" -> result.success(ScheduledAlertStore.consumeReceipts(context))
                    else -> result.notImplemented()
                }
            }
    }

    private fun replace(call: MethodCall, context: Context, result: MethodChannel.Result) {
        val account = call.argument<String>("accountKey").orEmpty()
        val provider = call.argument<String>("providerId").orEmpty()
        val raw = call.argument<String>("alerts")
        if (account.isBlank() || provider.isBlank() || raw.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "scheduled alert payload is incomplete", null)
            return
        }
        val alerts = try {
            val array = JSONArray(raw)
            buildList<ScheduledAlert> {
                for (index in 0 until array.length()) {
                    val json = array.optJSONObject(index) ?: continue
                    val alert = ScheduledAlert.fromJson(json) ?: continue
                    add(alert)
                }
            }
        } catch (_: Throwable) {
            result.error("INVALID_PAYLOAD", "scheduled alert payload is invalid", null)
            return
        }
        ScheduledAlertScheduler.replace(context, account, provider, alerts)
        result.success(null)
    }
}
