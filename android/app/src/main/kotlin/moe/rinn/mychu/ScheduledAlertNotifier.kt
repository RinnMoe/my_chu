package moe.rinn.mychu

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object ScheduledAlertNotifier {
    private const val CHANNEL_ID = "mychu_scheduled_reminders"

    fun post(context: Context, alert: ScheduledAlert): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        ensureChannel(context)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(context)
        }
        builder.setSmallIcon(R.drawable.ic_stat_course)
            .setContentTitle(alert.title)
            .setContentText(alert.body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(contentIntent(context, alert))
        val timeout = alert.validUntil - System.currentTimeMillis()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && timeout > 0) {
            builder.setTimeoutAfter(timeout)
        }
        context.getSystemService(NotificationManager::class.java)
            .notify(alert.key.hashCode(), builder.build())
        return true
    }

    fun cancel(context: Context, alert: ScheduledAlert) {
        context.getSystemService(NotificationManager::class.java).cancel(alert.key.hashCode())
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "定时提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "课前、考试和待办截止提醒"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }

    private fun contentIntent(context: Context, alert: ScheduledAlert): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_APP
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (!alert.targetAppId.isNullOrBlank()) putExtra(MainActivity.EXTRA_TARGET_APP_ID, alert.targetAppId)
        }
        return PendingIntent.getActivity(
            context,
            480500 + alert.key.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
