package moe.rinn.mychu

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object PlatformCompatibilityChannel {
    private const val CHANNEL = "mychu/platform_compatibility"

    fun register(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    "exactAlarmStatus" -> result.success(exactAlarmStatus(context))
                    "openExactAlarmSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                context.startActivity(
                                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                        data = Uri.parse("package:${context.packageName}")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    },
                                )
                            }
                            result.success(null)
                        } catch (_: Throwable) {
                            result.error("OPEN_SETTINGS_FAILED", "无法打开精确提醒设置", null)
                        }
                    }
                    "setExactAlarmRequested" -> {
                        val requested = call.argument<Boolean>("requested") == true
                        ScheduledAlertStore.setExactRequested(context, requested)
                        ScheduledAlertScheduler.rescheduleAll(context)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun exactAlarmStatus(context: Context): Map<String, Boolean> {
        val exactAuthorized = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
        return mapOf(
            "exactAlarmSupported" to true,
            "exactAlarmAuthorized" to exactAuthorized,
            "exactAlarmRequested" to ScheduledAlertStore.exactRequested(context),
        )
    }
}
