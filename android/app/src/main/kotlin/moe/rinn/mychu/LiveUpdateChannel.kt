package moe.rinn.mychu

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object LiveUpdateChannel {
    const val CHANNEL = "mychu/live_update"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "upsert" -> upsert(call, context, result)
                    "cancel" -> cancel(call, context, result)
                    "cancelDemo" -> {
                        val key = LiveUpdateStore.DEMO_KEY
                        val liveUpdate = LiveUpdateStore.read(context, key)
                        LiveUpdateStore.delete(context, key)
                        if (liveUpdate != null) {
                            LiveUpdateNotifier.cancel(context, liveUpdate)
                            LiveUpdateScheduler.cancel(context, liveUpdate)
                        }
                        result.success(null)
                    }
                    "clearAll" -> {
                        LiveUpdateStore.readAllFormal(context).forEach {
                            LiveUpdateNotifier.cancel(context, it)
                            LiveUpdateScheduler.cancel(context, it)
                        }
                        LiveUpdateStore.read(context, LiveUpdateStore.DEMO_KEY)?.let {
                            LiveUpdateNotifier.cancel(context, it)
                        }
                        LiveUpdateStore.clearAll(context)
                        LiveUpdateNotifier.cancelKnown(context)
                        result.success(null)
                    }
                    "getStatus" -> {
                        val promotedSupported = Build.VERSION.SDK_INT_FULL >= 3600001
                        val manager = context.getSystemService(NotificationManager::class.java)
                        val canPost = try {
                            promotedSupported && manager.canPostPromotedNotifications()
                        } catch (_: Throwable) {
                            false
                        }
                        result.success(
                            mapOf(
                                "promotedSupported" to promotedSupported,
                                "canPostPromotedNotifications" to canPost,
                            ),
                        )
                    }
                    "openChannelSettings" -> {
                        try {
                            LiveUpdateNotifier.openChannelSettings(context)
                            result.success(null)
                        } catch (_: Throwable) {
                            result.error(
                                "OPEN_SETTINGS_FAILED",
                                "无法打开实时动态通知设置",
                                null,
                            )
                        }
                    }
                    "openPromotionSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT_FULL < 3600001) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(null)
                        } catch (_: Throwable) {
                            result.error(
                                "OPEN_SETTINGS_FAILED",
                                "无法打开实时动态推广设置",
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun upsert(
        call: MethodCall,
        context: Context,
        result: MethodChannel.Result,
    ) {
        val raw = call.argument<String>("package")
        if (raw.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "package is required", null)
            return
        }
        val liveUpdate = try {
            LiveUpdatePackage.fromJson(JSONObject(raw))
        } catch (error: Throwable) {
            result.error("INVALID_PACKAGE", "Live Update package is invalid", null)
            return
        }
        val key = if (liveUpdate.isDemo) {
            LiveUpdateStore.DEMO_KEY
        } else {
            LiveUpdateStore.keyForAccount(liveUpdate.accountKey)
        }
        if (LiveUpdateStore.isDismissed(context, liveUpdate)) {
            LiveUpdateStore.delete(context, key)
            LiveUpdateNotifier.cancel(context, liveUpdate)
            LiveUpdateScheduler.cancel(context, liveUpdate)
            result.success(null)
            return
        }
        LiveUpdateStore.save(context, key, liveUpdate)
        LiveUpdateScheduler.schedule(context, liveUpdate)
        if (liveUpdate.cancelExisting) {
            LiveUpdateNotifier.cancel(context, liveUpdate)
        }
        if (liveUpdate.postImmediately) {
            LiveUpdateNotifier.post(context, liveUpdate, liveUpdate.render)
        }
        result.success(null)
    }

    private fun cancel(
        call: MethodCall,
        context: Context,
        result: MethodChannel.Result,
    ) {
        val accountKey = call.argument<String>("accountKey")
        if (accountKey.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "accountKey is required", null)
            return
        }
        val key = LiveUpdateStore.keyForAccount(accountKey)
        val liveUpdate = LiveUpdateStore.read(context, key)
        LiveUpdateStore.delete(context, key)
        if (liveUpdate != null) {
            LiveUpdateNotifier.cancel(context, liveUpdate)
            LiveUpdateScheduler.cancel(context, liveUpdate)
        }
        result.success(null)
    }
}
